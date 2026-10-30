// Explicitly authorized production acceptance only. This is never selected by
// the ordinary shell test suite. Secrets and full snapshots remain private.
import assert from 'node:assert/strict';
import { spawn, execFile as execFileCallback } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFile = promisify(execFileCallback);
assert.equal(process.env.SUBMAN_PRODUCTION_ACCEPT, '1', 'explicit production acceptance authorization is required');
const base = new URL(process.env.SUBMAN_PRODUCTION_API_URL);
assert.equal(base.protocol, 'https:');
assert.equal(base.username + base.password + base.search + base.hash, '');
const apiUrl = base.href.replace(/\/$/, '');
const gistId = process.env.SUBMAN_PRODUCTION_GIST_ID;
assert(/^[0-9a-f]{32}$/.test(gistId), 'exact expected Gist ID is required');
const headersFile = process.env.SUBMAN_PRODUCTION_HEADERS_FILE;
assert(headersFile, 'private API header file is required');
assert.equal((await stat(headersFile)).mode & 0o077, 0, 'API header file must be private');
const authMatches = [...(await readFile(headersFile, 'utf8')).matchAll(/^Authorization: Bearer ([^\r\n]+)$/gmi)];
assert.equal(authMatches.length, 1, 'exactly one API Bearer header is required');
const authorization = `Bearer ${authMatches[0][1]}`;
const dir = process.env.SUBMAN_PRODUCTION_ARTIFACT_DIR;
assert(dir, 'private production evidence directory is required');
await mkdir(dir, { recursive: true, mode: 0o700 });
assert.equal((await stat(dir)).mode & 0o077, 0, 'evidence directory must be private');
const testsDir = dirname(fileURLToPath(import.meta.url));
const runtimeDir = join(dir, 'runtime');
await mkdir(runtimeDir, { mode: 0o700 });
await copyFile(join(testsDir, '../install.sh'), join(runtimeDir, 'install.sh'));
const prefix = `spec-${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
const keyPrefix = `external:sing-box-vps:${prefix}:`;
const aggregateId = randomUUID();
const workspaceId = `gist:${gistId}`;
const hash = value => createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
const privateWrite = (name, value) => writeFile(join(dir, name), JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
const { stdout: githubTokenRaw } = await execFile('gh', ['auth', 'token']);
const githubToken = githubTokenRaw.trim();
assert(githubToken, 'existing GitHub authentication is unavailable');
async function github(path) {
  const response = await fetch(`https://api.github.com${path}`, {
    headers: { Authorization: `Bearer ${githubToken}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
    redirect: 'error', signal: AbortSignal.timeout(30000),
  });
  assert.equal(response.status, 200, `GitHub read failed with HTTP ${response.status}`);
  return response.json();
}
const owner = await github('/user');
async function snapshot(name) {
  const gist = await github(`/gists/${gistId}`);
  assert.equal(gist.owner.login, owner.login, 'current GitHub user must own the exact target');
  assert.equal(gist.description, 'SubMan-Data');
  const file = gist.files['subman.json'];
  assert(file && !file.truncated && typeof file.content === 'string', 'complete Workspace content is required');
  const document = JSON.parse(file.content);
  assert.equal(document.schemaVersion, 2, 'acceptance must not implicitly migrate a Workspace');
  assert.equal(document.workspaceId, workspaceId);
  if (name) await privateWrite(name, gist);
  return { gist, document };
}
async function listNodes() {
  const response = await fetch(`${apiUrl}/api/nodes`, {
    headers: { Authorization: authorization, 'Accept-Encoding': 'identity' }, redirect: 'error', signal: AbortSignal.timeout(30000),
  });
  assert.equal(response.status, 200, `node read failed with HTTP ${response.status}`);
  const body = await response.json();
  assert.equal(body.workspace.gistId, gistId, 'API target Workspace differs from authorization');
  assert.equal(body.workspace.file, 'subman.json');
  assert.equal(response.headers.get('etag'), `"subman-revision-${body.workspace.revision}"`);
  return { body, etag: response.headers.get('etag') };
}
const own = node => node.tags.some(tag => tag.label.startsWith(keyPrefix));
const identities = nodes => Object.fromEntries(nodes.map(node => [node.tags.find(tag => tag.label.startsWith(keyPrefix)).label, node.id]));
const baseline = await snapshot('before-gist.json');
const apiBaseline = await listNodes();
assert.equal(apiBaseline.body.workspace.revision, baseline.document.revision, 'Workspace changed during baseline capture');
assert.equal(hash(apiBaseline.body.data), hash(baseline.document.data.nodes), 'API and Gist node views differ');
assert(!apiBaseline.body.data.some(own), 'test identity prefix already exists');
const originalData = hash(baseline.document.data);
const outputHashes = Object.fromEntries(Object.entries(baseline.gist.files).filter(([name]) => name !== 'subman.json').map(([name, file]) => {
  assert(!file.truncated && typeof file.content === 'string', 'complete publication snapshot is required');
  return [name, hash(file.content)];
}));
if (process.env.SUBMAN_PRODUCTION_PLAN_ONLY === '1') {
  console.log(JSON.stringify({ proof: 'read-only production baseline and ownership check',
    nodes: baseline.document.data.nodes.length, aggregates: baseline.document.data.aggregates.length,
    revision: baseline.document.revision, expectedWorkspace: true, githubOwnerConfirmed: true,
    plannedNewNodes: 6, plannedNewAggregates: 1, writesPerformed: 0 }));
  process.exit(0);
}
async function mutate(kind, payload) {
  const before = await snapshot();
  const mutation = { mutationId: randomUUID(), workspaceId, expectedRevision: before.document.revision,
    source: 'browser', createdAt: new Date().toISOString(), kind, payload };
  let response;
  try {
    response = await fetch(`${apiUrl}/api/workspaces/${encodeURIComponent(workspaceId)}/mutations`, {
      method: 'POST', headers: { Authorization: `Bearer ${githubToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(mutation), redirect: 'error', signal: AbortSignal.timeout(30000),
    });
  } catch {
    response = null;
  }
  if (response?.status !== 200) {
    const observed = (await snapshot()).document.data.aggregates.find(item => item.id === aggregateId);
    const reconciled = kind === 'aggregate.delete' ? !observed : observed &&
      observed.name === payload.aggregate.name && hash(observed.nodeIds) === hash(payload.aggregate.nodeIds);
    assert(reconciled, `test aggregate mutation not confirmed (HTTP ${response?.status ?? 'unknown'})`);
    return;
  }
  const result = await response.json();
  assert.equal(result.workspaceId, workspaceId);
  assert.equal(result.committedRevision, before.document.revision + 1);
  return result;
}
async function driver(stage) {
  await new Promise((resolve, reject) => {
    const child = spawn('bash', [join(testsDir, 'subman_app_test_helper.sh'), stage], {
      stdio: 'inherit', env: { ...process.env,
        SUBMAN_APP_PRODUCTION_ACCEPT: '1', SUBMAN_APP_URL: apiUrl, SUBMAN_APP_GIST_ID: gistId,
        SUBMAN_APP_HEADERS_FILE: headersFile, SUBMAN_APP_KEY_PREFIX: prefix,
        SUBMAN_APP_DISPLAY_SUFFIX: `-${prefix}`, SUBMAN_APP_PROTOCOLS: 'vmess',
        SUBMAN_APP_RUNTIME_SOURCE_DIR: runtimeDir,
      },
    });
    child.once('error', reject);
    child.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`production driver ${stage}: exit ${code}, signal ${signal}`)));
  });
}
async function deleteOwnedNode(id) {
  for (let attempt = 0; attempt < 2; attempt++) {
    const current = await listNodes();
    const node = current.body.data.find(item => item.id === id);
    if (!node) return;
    assert(own(node), 'cleanup must never delete an unrelated node');
    let response;
    try {
      response = await fetch(`${apiUrl}/api/nodes/${encodeURIComponent(id)}`, {
        method: 'DELETE', headers: { Authorization: authorization, 'If-Match': current.etag },
        redirect: 'error', signal: AbortSignal.timeout(30000),
      });
    } catch {
      const reconciled = await listNodes();
      assert(!reconciled.body.data.some(item => item.id === id), 'cleanup outcome unknown; readback still contains test node');
      return;
    }
    if (response.status === 412) continue;
    if (response.status !== 200) {
      const reconciled = await listNodes();
      assert(!reconciled.body.data.some(item => item.id === id), `cleanup failed with HTTP ${response.status}`);
    }
    return;
  }
  throw new Error('concurrent changes prevented conditional test-node cleanup');
}
let failure;
let report;
try {
  await driver('create');
  const created = await snapshot('created-gist.json');
  const nodes = created.document.data.nodes.filter(own);
  assert.equal(nodes.length, 6, 'six isolated VMess candidates must be created');
  const ids = identities(nodes);
  assert.equal(new Set(Object.values(ids)).size, 6);
  const now = new Date().toISOString();
  await mutate('aggregate.upsert', { aggregate: {
    id: aggregateId, name: `SPEC acceptance ${prefix}`, nodeIds: Object.values(ids),
    subscriptionIds: [], excludeTagIds: [], renameMap: {}, allowedTypes: [], updatedAt: now,
  } });
  const aggregateBefore = (await snapshot()).document.data.aggregates.find(item => item.id === aggregateId);
  await driver('rename');
  const renamed = await snapshot('renamed-gist.json');
  const updated = renamed.document.data.nodes.filter(own);
  assert.equal(hash(identities(updated)), hash(ids), 'actual remote node IDs or external keys changed');
  assert.equal(hash(renamed.document.data.aggregates.find(item => item.id === aggregateId)), hash(aggregateBefore), 'test aggregate membership changed');
  for (const node of updated) {
    assert(node.name.startsWith('改名🚀'));
    assert(Buffer.byteLength(node.name) <= 256);
    assert.equal(JSON.parse(Buffer.from(node.raw.slice(8), 'base64').toString()).ps, node.name);
    assert.notEqual(node.name, nodes.find(item => item.id === node.id).name);
  }
  for (const [collection, values] of Object.entries(baseline.document.data)) {
    for (const value of values) {
      const observed = renamed.document.data[collection].find(item => item.id === value.id);
      assert.equal(hash(observed), hash(value), `existing ${collection} record changed`);
    }
  }
  report = { proof: 'production SubMan API and GitHub Gist readback', nodeCount: 6, stableNodeIds: 6,
    preservedTestAggregates: 1, existingDataUnchanged: true, prefixHash: hash(prefix),
    runtimeSha256: hash(await readFile(join(runtimeDir, 'install.sh'), 'utf8')) };
} catch (error) {
  failure = error;
} finally {
  try {
    const current = await snapshot();
    const aggregate = current.document.data.aggregates.find(item => item.id === aggregateId);
    if (aggregate) {
      assert.equal(aggregate.name, `SPEC acceptance ${prefix}`, 'test aggregate ownership check failed');
      const currentOwnedIds = new Set(current.document.data.nodes.filter(own).map(item => item.id));
      assert(aggregate.nodeIds.every(id => currentOwnedIds.has(id)), 'test aggregate acquired unrelated members; cleanup stopped');
      await mutate('aggregate.delete', { id: aggregateId });
    }
    const currentNodes = (await listNodes()).body.data.filter(own);
    for (const node of currentNodes) await deleteOwnedNode(node.id);
    const final = await snapshot('after-cleanup-gist.json');
    assert.equal(hash(final.document.data), originalData, 'existing business data differs after test cleanup');
    const finalOutputs = Object.fromEntries(Object.entries(final.gist.files).filter(([name]) => name !== 'subman.json').map(([name, file]) => [name, hash(file.content)]));
    assert.equal(hash(finalOutputs), hash(outputHashes), 'existing publication output changed');
    if (report) Object.assign(report, { cleanup: 'complete', publicationUnchanged: true,
      baselineRevision: baseline.document.revision, finalRevision: final.document.revision,
      tombstonesRetained: true, production: true });
  } catch (cleanupError) {
    failure = new Error(`test cleanup incomplete: ${cleanupError.message}`);
  }
}
if (failure) {
  await privateWrite('failure.json', { error: failure.message, prefix, aggregateId });
  throw new Error(`production acceptance failed; private recovery evidence retained: ${failure.message}`);
}
await privateWrite('acceptance.json', report);
console.log(JSON.stringify(report));
