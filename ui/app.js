import { buildRows, filterRows, summarize } from './state.js';
import { renderList, renderSummary, showNotice, showStopDialog } from './view.js';

const POLL_MS = 2000;
const bridge = window.webkit?.messageHandlers?.devServers;
const hasBridge = Boolean(bridge);

const $ = (selector) => document.querySelector(selector);
const listEl = $('#list');
const summaryEl = $('#summary');
const noticeEl = $('#notice');
const queryEl = $('#query');
const runningEl = $('#running-only');
const stopDialog = $('#stop-dialog');

const send = (action, payload = {}) => bridge.postMessage({ action, ...payload });

const STARTING_GRACE_MS = 20000;
const view = { list: [], statuses: [], busy: new Set(), starting: new Map() };

const startingIds = () => {
  const now = Date.now();
  for (const [id, until] of view.starting) {
    const up = view.statuses.some((status) => status.id === id && status.listening);
    if (up || until < now) view.starting.delete(id);
  }
  return new Set(view.starting.keys());
};

const render = () => {
  const rows = buildRows(view.list, view.statuses, startingIds());
  const shown = filterRows(rows, { query: queryEl.value, runningOnly: runningEl.checked });
  renderList(listEl, shown, { onAction: handleAction, busy: view.busy.size > 0, bridge: hasBridge });
  renderSummary(summaryEl, summarize(rows));
  return rows;
};

const fail = (message) => showNotice(noticeEl, message, 'error');

const handleAction = async (action, id) => {
  if (view.busy.has(id)) return;
  const rows = buildRows(view.list, view.statuses);
  const row = rows.find((candidate) => candidate.id === id);
  view.busy.add(id);
  render();
  try {
    let reply = await send(action, { id });
    if (action === 'stop' && reply?.needsConfirmation) {
      const confirmed = await showStopDialog(stopDialog, {
        name: row?.name ?? id,
        pid: reply.pid,
        command: reply.command,
      });
      reply = confirmed ? await send('confirmStop', { id, pid: reply.pid }) : { ok: true };
    }
    if (action === 'start' && reply?.ok) view.starting.set(id, Date.now() + STARTING_GRACE_MS);
    if (reply?.ok === false) fail(reply.error ?? `${action} failed for ${id}`);
    else showNotice(noticeEl, '', 'info');
  } catch (error) {
    fail(`${action} failed for ${id}: ${error?.message ?? error}`);
  } finally {
    view.busy.delete(id);
    await refreshStatus();
  }
};

// list and status answer with an array, or with { ok: false, error } when the registry is invalid.
const refreshStatus = async () => {
  if (!hasBridge) return;
  try {
    const reply = await send('status');
    if (!Array.isArray(reply)) {
      fail(reply?.error ?? 'Status check failed.');
      return;
    }
    view.statuses = reply;
    render();
  } catch (error) {
    fail(`Status check failed: ${error?.message ?? error}`);
  }
};

const loadStaticList = async () => {
  try {
    const response = await fetch('../registry.json');
    const registry = await response.json();
    return registry.servers.map(({ id, name, port, url, managed, notes }) => ({ id, name, port, url, managed, notes }));
  } catch {
    return [];
  }
};

const poll = async () => {
  if (!document.hidden) await refreshStatus();
  setTimeout(poll, POLL_MS);
};

const init = async () => {
  queryEl.addEventListener('input', render);
  runningEl.addEventListener('change', render);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refreshStatus();
  });

  if (hasBridge) {
    try {
      const reply = await send('list');
      if (!Array.isArray(reply)) {
        fail(`The registry could not be loaded: ${reply?.error ?? 'unknown error'}. Fix registry.json, then View > Reload Registry.`);
        render();
        return;
      }
      view.list = reply;
    } catch (error) {
      fail(`Could not load the server list: ${error?.message ?? error}`);
    }
    render();
    poll();
    return;
  }

  view.list = await loadStaticList();
  showNotice(
    noticeEl,
    view.list.length
      ? 'Not running inside the Dev Servers app: this is the static registry. Status and actions need the app.'
      : 'Not running inside the Dev Servers app, and registry.json could not be read from here. Open the app to see live servers.',
    'warn',
  );
  render();
};

init();
