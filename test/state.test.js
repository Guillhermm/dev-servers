import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRows, filterRows, summarize } from '../ui/state.js';

const list = [
  { id: 'a', name: 'Alpha', port: 8417, url: 'http://127.0.0.1:8417/', managed: true, notes: 'static' },
  { id: 'b', name: 'Beta', port: 8418, url: 'http://127.0.0.1:8418/', managed: true, notes: '' },
  { id: 'c', name: 'Gamma', port: 5173, url: 'http://127.0.0.1:5173/', managed: true, notes: 'vite' },
  { id: 'd', name: 'Delta', port: 5173, url: 'http://127.0.0.1:5173/', managed: true, notes: 'vite' },
  { id: 'o', name: 'Ollama', port: 11434, url: 'http://127.0.0.1:11434/', managed: false, notes: '' },
];
const byId = (rows, id) => rows.find((row) => row.id === id);

test('stopped and running rows from status', () => {
  const rows = buildRows(list, [
    { id: 'a', listening: true, pid: 10, command: 'python3 serve.py', ownedByApp: true },
    { id: 'b', listening: false },
  ]);
  assert.equal(byId(rows, 'a').state, 'running');
  assert.equal(byId(rows, 'a').canStop, true);
  assert.equal(byId(rows, 'a').canStart, false);
  assert.equal(byId(rows, 'a').pid, 10);
  assert.equal(byId(rows, 'b').state, 'stopped');
  assert.equal(byId(rows, 'b').canStart, true);
  assert.equal(byId(rows, 'b').canStop, false);
});

test('missing status counts as stopped', () => {
  assert.equal(byId(buildRows(list, []), 'a').state, 'stopped');
});

test('a shared port can start while free and is a conflict while taken', () => {
  const free = buildRows(list, []);
  for (const id of ['c', 'd']) {
    assert.equal(byId(free, id).state, 'stopped');
    assert.equal(byId(free, id).canStart, true);
  }
  const taken = buildRows(list, [
    { id: 'c', listening: true, pid: 5, command: 'node vite', ownedByApp: true },
    { id: 'd', listening: true, pid: 5, command: 'node vite', ownedByApp: true },
  ]);
  for (const id of ['c', 'd']) {
    assert.equal(byId(taken, id).state, 'conflict');
    assert.equal(byId(taken, id).canStart, false);
    assert.equal(byId(taken, id).canStop, true);
  }
  assert.equal(summarize(taken).conflicts, 2);
});

test('a listening process the app did not start is foreign and stoppable', () => {
  const rows = buildRows(list, [{ id: 'b', listening: true, pid: 7, command: 'python3 -m http.server', ownedByApp: false }]);
  const row = byId(rows, 'b');
  assert.equal(row.state, 'foreign');
  assert.equal(row.canStop, true);
  assert.equal(row.command, 'python3 -m http.server');
});

test('unmanaged entries never get Stop or Start', () => {
  const up = byId(buildRows(list, [{ id: 'o', listening: true, pid: 1, command: 'ollama', ownedByApp: false }]), 'o');
  assert.equal(up.state, 'running');
  assert.equal(up.canStop, false);
  assert.equal(up.canStart, false);
  const down = byId(buildRows(list, []), 'o');
  assert.equal(down.canStart, false);
  assert.equal(down.canStop, false);
});

test('filter by text and running only', () => {
  const rows = buildRows(list, [{ id: 'a', listening: true, pid: 1, command: 'x', ownedByApp: true }]);
  assert.deepEqual(filterRows(rows, { query: '8418' }).map((r) => r.id), ['b']);
  assert.deepEqual(filterRows(rows, { query: 'VITE' }).map((r) => r.id), ['c', 'd']);
  assert.deepEqual(filterRows(rows, { runningOnly: true }).map((r) => r.id), ['a']);
  assert.equal(filterRows(rows, {}).length, rows.length);
});

test('a server just started cannot be started again before it listens', () => {
  const row = byId(buildRows(list, [], new Set(['b'])), 'b');
  assert.equal(row.state, 'stopped');
  assert.equal(row.canStart, false);
});
