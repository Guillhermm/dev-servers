// Pure view-model: registry list + bridge status in, display rows out.

export const STATES = ['running', 'stopped', 'conflict', 'foreign'];

const portCounts = (list) => {
  const counts = new Map();
  for (const server of list) counts.set(server.port, (counts.get(server.port) ?? 0) + 1);
  return counts;
};

// starting: ids launched but not yet listening, so Start stays off until the port answers.
export const buildRows = (list, statuses = [], starting = new Set()) => {
  const byId = new Map(statuses.map((status) => [status.id, status]));
  const counts = portCounts(list);
  return list.map((server) => {
    const status = byId.get(server.id);
    const listening = status?.listening === true;
    const managed = server.managed !== false;
    const shared = counts.get(server.port) > 1;
    const foreign = listening && managed && status.ownedByApp === false;
    let state = listening ? 'running' : 'stopped';
    if (foreign) state = 'foreign';
    // Two entries on one port: a listener there can belong to either, so it is ambiguous only while up.
    if (shared && listening) state = 'conflict';
    return {
      id: server.id,
      name: server.name,
      port: server.port,
      url: server.url,
      state,
      listening,
      pid: listening ? (status.pid ?? null) : null,
      command: listening ? (status.command ?? '') : '',
      canStart: managed && !listening && !starting.has(server.id),
      canStop: managed && listening,
      managed,
      notes: server.notes ?? '',
    };
  });
};

export const filterRows = (rows, { query = '', runningOnly = false } = {}) => {
  const needle = query.trim().toLowerCase();
  return rows.filter((row) => {
    if (runningOnly && !row.listening) return false;
    if (!needle) return true;
    return [row.name, row.id, String(row.port), row.notes].some((field) => field.toLowerCase().includes(needle));
  });
};

export const summarize = (rows) => ({
  total: rows.length,
  running: rows.filter((row) => row.listening).length,
  conflicts: rows.filter((row) => row.state === 'conflict').length,
});
