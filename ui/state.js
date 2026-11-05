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

export const STARTING_GRACE_MS = 30000;

const logLines = (launch) => (Array.isArray(launch?.log) ? launch.log : []);

// Turns each entry's latest launch into at most one notice. `starting` maps id to the time its
// grace period ends; `notified` holds keys already shown, so a notice appears once per launch.
// `settled` lists ids whose starting state should end now.
export const launchNotices = (list, statuses, { starting = new Map(), notified = new Set(), now = Date.now() } = {}) => {
  const byId = new Map(statuses.map((status) => [status.id, status]));
  const notices = [];
  const settled = [];
  for (const server of list) {
    const status = byId.get(server.id);
    const launch = status?.launch;
    const until = starting.get(server.id);
    const wasStarting = until !== undefined;
    if (!launch) continue;
    const port = `port ${server.port}`;

    if (!launch.running && !launch.expected) {
      const key = `${server.id}:${launch.pid}:exit`;
      if (status.listening) {
        // A wrapper that hands off to a daemon exits 0 while the server keeps listening.
        if (launch.code === 0) continue;
      }
      if (launch.code === 0 && !status.listening && wasStarting && until > now) continue;
      if (wasStarting) settled.push(server.id);
      if (notified.has(key)) continue;
      const text = wasStarting || launch.code === 0
        ? `${server.name} did not start: ${launch.code === 0 ? `it exited and nothing listens on ${port}` : launch.reason}.`
        : `${server.name} stopped unexpectedly: ${launch.reason}.`;
      notices.push({ id: server.id, key, kind: 'error', text, log: logLines(launch) });
      continue;
    }

    if (launch.running && wasStarting && until <= now && !status.listening) {
      settled.push(server.id);
      const key = `${server.id}:${launch.pid}:slow`;
      if (notified.has(key)) continue;
      const seconds = Math.round(STARTING_GRACE_MS / 1000);
      notices.push({
        id: server.id,
        key,
        kind: 'warn',
        text: `${server.name} is running but nothing listens on ${port} after ${seconds} s. It may be using another port; check the log.`,
        log: [],
      });
    }
  }
  return { notices, settled };
};
