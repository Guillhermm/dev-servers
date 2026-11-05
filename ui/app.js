import { STARTING_GRACE_MS, buildRows, filterRows, launchNotices, summarize } from './state.js';
import { clearNotices, pushNotice, renderList, renderSummary, showLogDialog, showStopDialog } from './view.js';

const POLL_MS = 2000;
const bridge = window.webkit?.messageHandlers?.devServers;
const hasBridge = Boolean(bridge);

const $ = (selector) => document.querySelector(selector);
const listEl = $('#list');
const summaryEl = $('#summary');
const noticesEl = $('#notices');
const queryEl = $('#query');
const runningEl = $('#running-only');
const stopDialog = $('#stop-dialog');
const logDialog = $('#log-dialog');

const send = (action, payload = {}) => bridge.postMessage({ action, ...payload });

const view = { list: [], statuses: [], busy: new Set(), starting: new Map(), notified: new Set() };

const nameOf = (id) => view.list.find((server) => server.id === id)?.name ?? id;

const notify = (notice) => pushNotice(noticesEl, notice);
const fail = (text) => notify({ kind: 'error', text });

const startingIds = () => {
  for (const [id] of view.starting) {
    const up = view.statuses.some((status) => status.id === id && status.listening);
    if (up) view.starting.delete(id);
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

const showLog = async (id) => {
  const reply = await send('tail', { id });
  if (reply?.ok === false) {
    fail(reply.error ?? `No log for ${nameOf(id)}.`);
    return;
  }
  showLogDialog(logDialog, {
    name: nameOf(id),
    path: reply.path,
    text: reply.text,
    onOpenExternally: () => send('log', { id }),
  });
};

const reportLaunches = () => {
  const { notices, settled } = launchNotices(view.list, view.statuses, {
    starting: view.starting,
    notified: view.notified,
  });
  for (const id of settled) view.starting.delete(id);
  for (const notice of notices) {
    view.notified.add(notice.key);
    notify({ ...notice, onShowLog: () => showLog(notice.id) });
  }
};

const handleAction = async (action, id) => {
  if (view.busy.has(id)) return;
  if (action === 'log') {
    await showLog(id).catch((error) => fail(`Could not read the log: ${error?.message ?? error}`));
    return;
  }
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
    if (reply?.ok === false) fail(`${nameOf(id)}: ${reply.error ?? `${action} failed`}`);
  } catch (error) {
    fail(`${action} failed for ${nameOf(id)}: ${error?.message ?? error}`);
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
      notify({ key: 'status', kind: 'error', text: reply?.error ?? 'Status check failed.' });
      return;
    }
    view.statuses = reply;
    reportLaunches();
    render();
  } catch (error) {
    notify({ key: 'status', kind: 'error', text: `Status check failed: ${error?.message ?? error}` });
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
  clearNotices(noticesEl);

  if (hasBridge) {
    try {
      const reply = await send('list');
      if (!Array.isArray(reply)) {
        fail(`The registry could not be loaded: ${reply?.error ?? 'unknown error'}. Fix it, then View > Reload Registry.`);
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
  notify({
    kind: 'warn',
    text: view.list.length
      ? 'Not running inside the Dev Servers app: this is the static registry. Status and actions need the app.'
      : 'Not running inside the Dev Servers app, and registry.json could not be read from here. Open the app to see live servers.',
  });
  render();
};

init();
