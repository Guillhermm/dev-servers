import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const registry = JSON.parse(readFileSync(join(root, 'registry.json'), 'utf8'));
const { servers } = registry;

// Framework default ports that several projects legitimately share (documented in notes).
const SHARED_PORTS = new Set([5173, 4321]);

test('registry has version 1 and servers', () => {
  assert.equal(registry.version, 1);
  assert.ok(Array.isArray(servers) && servers.length > 0);
});

test('ids are valid and unique', () => {
  const ids = servers.map((s) => s.id);
  for (const id of ids) assert.match(id, /^[a-z0-9-]+$/);
  assert.equal(new Set(ids).size, ids.length);
});

test('every entry has the required fields', () => {
  for (const s of servers) {
    for (const key of ['name', 'path', 'cwd', 'host', 'url', 'notes']) assert.equal(typeof s[key], 'string', `${s.id}.${key}`);
    assert.ok(Number.isInteger(s.port) && s.port > 0 && s.port < 65536, `${s.id} port`);
    assert.equal(typeof s.managed, 'boolean', `${s.id}.managed`);
    assert.equal(typeof s.env, 'object', `${s.id}.env`);
    assert.equal(s.health.type, 'tcp');
    assert.ok(URL.canParse(s.url), `${s.id} url`);
  }
});

test('ports are unique except documented shared defaults', () => {
  const byPort = new Map();
  for (const s of servers) byPort.set(s.port, [...(byPort.get(s.port) ?? []), s]);
  for (const [port, entries] of byPort) {
    if (entries.length === 1) continue;
    assert.ok(SHARED_PORTS.has(port), `port ${port} is shared by ${entries.map((e) => e.id)}`);
    for (const e of entries) assert.match(e.notes, /shared/i, `${e.id} must say the port is shared`);
  }
});

test('start is a non-empty argv of strings', () => {
  for (const s of servers) {
    assert.ok(Array.isArray(s.start) && s.start.length > 0, `${s.id} start`);
    assert.ok(s.start.every((part) => typeof part === 'string' && part !== ''), `${s.id} start parts`);
  }
});

test('paths and cwd exist on disk', () => {
  for (const s of servers) {
    assert.ok(existsSync(s.path), `${s.id} path ${s.path}`);
    assert.ok(existsSync(s.cwd), `${s.id} cwd ${s.cwd}`);
  }
});

test('unmanaged services are present', () => {
  const unmanaged = servers.filter((s) => !s.managed).map((s) => s.id);
  for (const id of ['ollama', 'open-webui', 'caddy']) assert.ok(unmanaged.includes(id), id);
});

test('no innerHTML anywhere in ui/', () => {
  const dir = join(root, 'ui');
  const walk = (d) => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]));
  for (const file of walk(dir)) {
    assert.ok(!/inner\s*HTML|outer\s*HTML|insertAdjacentHTML/i.test(readFileSync(file, 'utf8')), file);
  }
});
