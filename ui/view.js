const STATE_LABELS = {
  running: 'Running',
  stopped: 'Stopped',
  conflict: 'Port shared',
  foreign: 'Started elsewhere',
};

const el = (doc, tag, className, text) => {
  const node = doc.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

const actionButton = (doc, label, action, id, enabled, onAction) => {
  const button = el(doc, 'button', `btn btn-${action}`, label);
  button.type = 'button';
  button.disabled = !enabled;
  button.addEventListener('click', () => onAction(action, id));
  return button;
};

export const renderRow = (doc, row, { onAction, busy = false, bridge = true }) => {
  const item = el(doc, 'li', `row state-${row.state}`);
  item.dataset.id = row.id;

  const dot = el(doc, 'span', 'dot');
  dot.title = STATE_LABELS[row.state];
  dot.setAttribute('role', 'img');
  dot.setAttribute('aria-label', STATE_LABELS[row.state]);

  const main = el(doc, 'div', 'main');
  const title = el(doc, 'div', 'title');
  title.append(el(doc, 'span', 'name', row.name), el(doc, 'span', 'port', `:${row.port}`));
  if (!row.managed) title.append(el(doc, 'span', 'badge badge-unmanaged', 'Unmanaged'));
  if (row.state === 'conflict') title.append(el(doc, 'span', 'badge badge-conflict', 'Port shared'));
  if (row.state === 'foreign') title.append(el(doc, 'span', 'badge badge-foreign', 'Started elsewhere'));
  main.append(title);
  if (row.notes) main.append(el(doc, 'div', 'notes', row.notes));
  if (row.listening && row.pid !== null) {
    main.append(el(doc, 'div', 'process', `PID ${row.pid} ${row.command}`.trim()));
  }

  const actions = el(doc, 'div', 'actions');
  const live = bridge && !busy;
  actions.append(
    actionButton(doc, 'Start', 'start', row.id, live && row.canStart, onAction),
    actionButton(doc, 'Stop', 'stop', row.id, live && row.canStop, onAction),
    actionButton(doc, 'Open', 'open', row.id, live && row.listening, onAction),
    actionButton(doc, 'Log', 'log', row.id, live && row.managed, onAction),
  );

  item.append(dot, main, actions);
  return item;
};

export const renderList = (root, rows, options) => {
  const doc = root.ownerDocument;
  root.replaceChildren();
  if (rows.length === 0) {
    const empty = el(doc, 'li', 'empty', 'No servers match.');
    root.append(empty);
    return;
  }
  for (const row of rows) root.append(renderRow(doc, row, options));
};

export const renderSummary = (node, summary) => {
  node.textContent = `${summary.running} running of ${summary.total}` +
    (summary.conflicts ? `, ${summary.conflicts} sharing a port` : '');
};

// The footer holds a short stack of notices, newest last. Only info notices fade on their own.
const MAX_NOTICES = 4;
const AUTO_HIDE_MS = 6000;

export const pushNotice = (root, { key, kind = 'info', text, log = [], onShowLog }) => {
  const doc = root.ownerDocument;
  if (key) root.querySelector(`[data-key="${CSS.escape(key)}"]`)?.remove();
  const item = el(doc, 'div', 'toast');
  item.dataset.kind = kind;
  if (key) item.dataset.key = key;
  item.setAttribute('role', kind === 'error' ? 'alert' : 'status');

  const body = el(doc, 'div', 'toast-body');
  body.append(el(doc, 'p', 'toast-text', text));
  if (log.length) body.append(el(doc, 'pre', 'toast-log', log.join('\n')));

  const actions = el(doc, 'div', 'toast-actions');
  if (onShowLog) {
    const show = el(doc, 'button', 'btn btn-log', 'Show log');
    show.type = 'button';
    show.addEventListener('click', onShowLog);
    actions.append(show);
  }
  const close = el(doc, 'button', 'toast-close', '\u00d7');
  close.type = 'button';
  close.setAttribute('aria-label', 'Dismiss');
  close.addEventListener('click', () => item.remove());
  actions.append(close);

  item.append(body, actions);
  root.append(item);
  while (root.children.length > MAX_NOTICES) root.firstElementChild.remove();
  if (kind === 'info') {
    setTimeout(() => item.remove(), AUTO_HIDE_MS);
  }
  return item;
};

export const clearNotices = (root) => root.replaceChildren();

export const showLogDialog = (dialog, { name, path, text, onOpenExternally }) => {
  dialog.querySelector('[data-slot="name"]').textContent = name;
  dialog.querySelector('[data-slot="path"]').textContent = path ?? '';
  const pre = dialog.querySelector('[data-slot="log"]');
  pre.textContent = text === '' ? '(the log is empty)' : text;
  const external = dialog.querySelector('[data-action="open-external"]');
  external.onclick = onOpenExternally;
  dialog.showModal();
  pre.scrollTop = pre.scrollHeight;
};

export const showStopDialog = (dialog, { name, pid, command }) => {
  dialog.querySelector('[data-slot="name"]').textContent = name;
  dialog.querySelector('[data-slot="pid"]').textContent = String(pid ?? '?');
  dialog.querySelector('[data-slot="command"]').textContent = command ?? '';
  return new Promise((resolve) => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
    dialog.returnValue = '';
    dialog.showModal();
  });
};
