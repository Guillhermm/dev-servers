import { test } from 'node:test';
import assert from 'node:assert/strict';
import { launchNotices } from '../ui/state.js';

const list = [{ id: 'a', name: 'Alpha', port: 8417 }];
const now = 1_000_000;
const failed = { pid: 7, running: false, code: 127, signal: null, expected: false, reason: 'command not found (exit 127)', log: ['zsh:1: command not found: npm'] };

test('a failed start becomes one error notice with the log tail and ends the starting state', () => {
  const { notices, settled } = launchNotices(list, [{ id: 'a', listening: false, launch: failed }], {
    starting: new Map([['a', now + 5000]]),
    now,
  });
  assert.deepEqual(settled, ['a']);
  assert.equal(notices.length, 1);
  assert.equal(notices[0].kind, 'error');
  assert.match(notices[0].text, /Alpha did not start: command not found/);
  assert.deepEqual(notices[0].log, ['zsh:1: command not found: npm']);
});

test('a notice already shown is not repeated', () => {
  const { notices } = launchNotices(list, [{ id: 'a', listening: false, launch: failed }], {
    notified: new Set(['a:7:exit']),
    now,
  });
  assert.equal(notices.length, 0);
});

test('a stop the user asked for says nothing', () => {
  const launch = { ...failed, code: null, signal: 15, expected: true, reason: 'killed by SIGTERM' };
  assert.equal(launchNotices(list, [{ id: 'a', listening: false, launch }], { now }).notices.length, 0);
});

test('a running server that dies later is reported as stopped unexpectedly', () => {
  const launch = { ...failed, code: 1, reason: 'exited with code 1' };
  const { notices } = launchNotices(list, [{ id: 'a', listening: false, launch }], { now });
  assert.match(notices[0].text, /stopped unexpectedly: exited with code 1/);
});

test('exit 0 with the port listening is a daemonizing wrapper, not a failure', () => {
  const launch = { ...failed, code: 0, reason: 'exited normally (code 0)' };
  const { notices } = launchNotices(list, [{ id: 'a', listening: true, launch }], { starting: new Map([['a', now + 1]]), now });
  assert.equal(notices.length, 0);
});

test('exit 0 without a listener waits for the grace period, then fails', () => {
  const launch = { ...failed, code: 0, reason: 'exited normally (code 0)' };
  const statuses = [{ id: 'a', listening: false, launch }];
  assert.equal(launchNotices(list, statuses, { starting: new Map([['a', now + 1]]), now }).notices.length, 0);
  const late = launchNotices(list, statuses, { starting: new Map([['a', now - 1]]), now });
  assert.match(late.notices[0].text, /nothing listens on port 8417/);
});

test('still running but not listening after the grace period warns once', () => {
  const launch = { pid: 9, running: true };
  const statuses = [{ id: 'a', listening: false, launch }];
  const early = launchNotices(list, statuses, { starting: new Map([['a', now + 1]]), now });
  assert.equal(early.notices.length, 0);
  assert.deepEqual(early.settled, []);
  const late = launchNotices(list, statuses, { starting: new Map([['a', now - 1]]), now });
  assert.equal(late.notices[0].kind, 'warn');
  assert.deepEqual(late.settled, ['a']);
});
