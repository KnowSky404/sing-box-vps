// Run the actual SubMan Worker and SQLite coordinator. Only the GitHub provider
// boundary is simulated, and every other outbound request is rejected.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const testsDir = dirname(fileURLToPath(import.meta.url));
const artifactDir = process.env.SUBMAN_APP_ARTIFACT_DIR;
assert(artifactDir, 'SUBMAN_APP_ARTIFACT_DIR is required');
const appDir = join(artifactDir, 'app');
const runtimeDir = join(artifactDir, 'runtime');
await mkdir(runtimeDir, { recursive: true });
await copyFile(join(testsDir, '../install.sh'), join(runtimeDir, 'install.sh'));
const require = createRequire(join(appDir, 'package.json'));
const { build } = require('esbuild');
const { Miniflare, Response: WorkerResponse } = require('miniflare');
const bundle = join(artifactDir, 'subman-worker.mjs');
await build({
  entryPoints: [join(appDir, '.svelte-kit/cloudflare/_worker.js')],
  outfile: bundle, bundle: true, format: 'esm', platform: 'neutral',
  conditions: ['workerd', 'worker', 'browser'],
  mainFields: ['browser', 'module', 'main'],
  external: ['cloudflare:*', 'node:*'],
  alias: { $lib: join(appDir, 'src/lib') },
});
const gistId = 'isolated-spec-acceptance';
const workspaceId = `gist:${gistId}`;
const now = new Date().toISOString();
const document = {
  version: 2, schemaVersion: 2, workspaceId, revision: 1, updatedAt: now,
  lastMutationId: null,
  data: { nodes: [], subscriptions: [], aggregates: [], publishTargets: [], clientExports: [] },
  tombstones: { nodes: [], subscriptions: [], aggregates: [], publishTargets: [], clientExports: [] },
};
const publication = 'existing generated output must remain unchanged\r\n';
const files = { 'subman.json': JSON.stringify(document), 'existing-output.txt': publication };
const patches = [];
const outbound = [];
function gist() {
  return {
    id: gistId, description: 'SubMan-Data', public: false,
    owner: { login: 'isolated-fixture' }, updated_at: new Date().toISOString(),
    html_url: `https://gist.github.com/isolated-fixture/${gistId}`,
    files: Object.fromEntries(Object.entries(files).map(([name, content]) => [name, {
      filename: name, language: 'Text', content, size: Buffer.byteLength(content), truncated: false,
      raw_url: `https://gist.githubusercontent.com/isolated-fixture/${gistId}/raw/${name}`,
    }])),
  };
}
const mf = new Miniflare({
  name: 'subman-spec-acceptance', modules: [{ type: 'ESModule', path: bundle }],
  modulesRoot: artifactDir,
  rootPath: artifactDir, defaultPersistRoot: join(artifactDir, 'runtime-state'), cf: false,
  compatibilityDate: '2026-07-28', compatibilityFlags: ['nodejs_compat'],
  host: '127.0.0.1', port: 0,
  bindings: { GITHUB_TOKEN: 'isolated-github-fixture', SUBMAN_API_TOKEN: 'isolated-api-fixture' },
  durableObjects: { WORKSPACE_COORDINATOR: { className: 'WorkspaceCoordinator', useSQLite: true } },
  durableObjectsPersist: join(artifactDir, 'sqlite'),
  serviceBindings: { ASSETS: () => new WorkerResponse('isolated fixture has no assets', { status: 404 }) },
  async outboundService(request) {
    const url = new URL(request.url);
    outbound.push({ host: url.host, path: url.pathname, method: request.method });
    assert.equal(url.host, 'api.github.com', 'unexpected external network request');
    assert.equal(request.headers.get('Authorization'), 'Bearer isolated-github-fixture');
    if (url.pathname === '/gists' && request.method === 'GET') return WorkerResponse.json([gist()]);
    assert.equal(url.pathname, `/gists/${gistId}`, 'unexpected Gist target');
    if (request.method === 'PATCH') {
      const patch = await request.json();
      patches.push(Object.keys(patch.files).sort());
      for (const [name, file] of Object.entries(patch.files)) {
        assert.equal(name, 'subman.json', 'node update must not republish outputs');
        assert(file && typeof file.content === 'string');
        files[name] = file.content;
      }
      await writeFile(join(artifactDir, 'gist-state.json'), JSON.stringify(files, null, 2));
      return WorkerResponse.json(gist());
    }
    assert.equal(request.method, 'GET', 'unexpected provider mutation');
    return WorkerResponse.json(gist());
  },
});
async function driver(stage, apiUrl) {
  await new Promise((resolve, reject) => {
    const child = spawn('bash', [join(testsDir, 'subman_app_test_helper.sh'), stage], {
      stdio: 'inherit',
      env: { ...process.env, SUBMAN_APP_URL: apiUrl, SUBMAN_APP_GIST_ID: gistId,
        SUBMAN_APP_RUNTIME_SOURCE_DIR: runtimeDir },
    });
    child.once('error', reject);
    child.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`driver ${stage}: exit ${code}, signal ${signal}`)));
  });
}
function snapshot() { return JSON.parse(files['subman.json']); }
function identities(value) {
  return Object.fromEntries(value.data.nodes.map(node => [node.tags.find(tag => tag.label.startsWith('external:')).label, node.id]));
}
try {
  const apiUrl = String(await mf.ready).replace(/\/$/, '');
  const unauthorized = await mf.dispatchFetch(`${apiUrl}/api/nodes`);
  assert.equal(unauthorized.status, 401);
  await driver('create', apiUrl);
  const before = snapshot();
  assert.equal(before.data.nodes.length, 30);
  const idsBefore = identities(before);
  assert.equal(new Set(Object.values(idsBefore)).size, 30);
  const aggregateId = randomUUID();
  const aggregateResponse = await mf.dispatchFetch(`${apiUrl}/api/workspaces/${encodeURIComponent(workspaceId)}/mutations`, {
    method: 'POST', headers: { Authorization: 'Bearer isolated-github-fixture', 'Content-Type': 'application/json' },
    body: JSON.stringify({
      mutationId: randomUUID(), workspaceId, expectedRevision: before.revision,
      source: 'browser', createdAt: new Date().toISOString(), kind: 'aggregate.upsert',
      payload: { aggregate: {
        id: aggregateId, name: 'Existing aggregate', nodeIds: Object.values(idsBefore),
        subscriptionIds: [], excludeTagIds: [], renameMap: {}, allowedTypes: [], updatedAt: new Date().toISOString(),
      } },
    }),
  });
  assert.equal(aggregateResponse.status, 200, await aggregateResponse.text());
  const aggregateBefore = snapshot().data.aggregates;
  await driver('rename', apiUrl);
  const after = snapshot();
  assert.equal(after.data.nodes.length, 30);
  assert.deepEqual(identities(after), idsBefore, 'rename must preserve actual SubMan-assigned node IDs and keys');
  assert.deepEqual(after.data.aggregates, aggregateBefore, 'rename must preserve aggregate membership');
  assert.equal(files['existing-output.txt'], publication);
  assert.equal(after.revision, before.revision + 31);
  for (const node of after.data.nodes) {
    assert(node.name.startsWith('改名🚀'), 'saved Unicode name must reach actual storage');
    assert(Buffer.byteLength(node.name) <= 256);
    const old = before.data.nodes.find(item => item.id === node.id);
    assert.notEqual(node.name, old.name);
    if (node.raw.startsWith('vmess://')) {
      assert.equal(JSON.parse(Buffer.from(node.raw.slice(8), 'base64').toString()).ps, node.name);
    } else {
      assert.equal(decodeURIComponent(new URL(node.raw).hash.slice(1)), node.name);
    }
  }
  assert(patches.every(names => names.length === 1 && names[0] === 'subman.json'));
  const report = {
    proof: 'actual SubMan Worker HTTP routes and SQLite Durable Object; isolated GitHub provider fixture',
    submanCommit: process.env.SUBMAN_SOURCE_SHA,
    runtimeSha256: createHash('sha256').update(await readFile(join(runtimeDir, 'install.sh'))).digest('hex'),
    workerSha256: createHash('sha256').update(await readFile(bundle)).digest('hex'),
    protocolCount: 5, nodesBefore: 30, nodesAfter: 30, stableIds: 30,
    aggregatesPreserved: after.data.aggregates.length, revision: after.revision,
    providerPatchCount: patches.length, publicationUnchanged: true,
    unexpectedExternalRequests: outbound.filter(item => item.host !== 'api.github.com').length,
    realGitHub: false, production: false,
  };
  await writeFile(join(artifactDir, 'acceptance.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
} finally {
  await mf.dispose();
}
