import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const read = (name) => JSON.parse(readFileSync(join(root, name), 'utf8'));

// The example ships with the repo; registry.json is each user's own and is gitignored, so it is
// checked only where it exists.
const registries = [['registry.example.json', read('registry.example.json')]];
if (existsSync(join(root, 'registry.json'))) registries.push(['registry.json', read('registry.json')]);

for (const [file, registry] of registries) {
  const { servers } = registry;

  test(`${file}: version 1 with servers`, () => {
    assert.equal(registry.version, 1);
    assert.ok(Array.isArray(servers) && servers.length > 0);
  });

  test(`${file}: ids are valid and unique`, () => {
    const ids = servers.map((s) => s.id);
    for (const id of ids) assert.match(id, /^[a-z0-9-]+$/);
    assert.equal(new Set(ids).size, ids.length);
  });

  test(`${file}: every entry has the required fields`, () => {
    for (const s of servers) {
      for (const key of ['name', 'path', 'cwd', 'host', 'url', 'notes']) assert.equal(typeof s[key], 'string', `${s.id}.${key}`);
      assert.ok(Number.isInteger(s.port) && s.port >= 1024 && s.port < 65536, `${s.id} port`);
      assert.equal(typeof s.managed, 'boolean', `${s.id}.managed`);
      assert.equal(typeof s.env, 'object', `${s.id}.env`);
      assert.equal(s.health.type, 'tcp');
      assert.ok(['http:', 'https:'].includes(new URL(s.url).protocol), `${s.id} url`);
    }
  });

  test(`${file}: a port is shared only when every entry on it says so`, () => {
    const byPort = new Map();
    for (const s of servers) byPort.set(s.port, [...(byPort.get(s.port) ?? []), s]);
    for (const [port, entries] of byPort) {
      if (entries.length === 1) continue;
      for (const e of entries) assert.match(e.notes, /shared/i, `port ${port}: ${e.id} must say the port is shared`);
    }
  });

  test(`${file}: start is a non-empty argv of strings`, () => {
    for (const s of servers) {
      assert.ok(Array.isArray(s.start) && s.start.length > 0, `${s.id} start`);
      assert.ok(s.start.every((part) => typeof part === 'string' && part !== ''), `${s.id} start parts`);
    }
  });
}

if (registries.length > 1) {
  test('registry.json: paths and cwd exist on disk', () => {
    for (const s of read('registry.json').servers) {
      assert.ok(existsSync(s.path), `${s.id} path ${s.path}`);
      assert.ok(existsSync(s.cwd), `${s.id} cwd ${s.cwd}`);
    }
  });
}

test('no innerHTML anywhere in ui/', () => {
  const dir = join(root, 'ui');
  const walk = (d) => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]));
  for (const file of walk(dir)) {
    assert.ok(!/inner\s*HTML|outer\s*HTML|insertAdjacentHTML/i.test(readFileSync(file, 'utf8')), file);
  }
});
