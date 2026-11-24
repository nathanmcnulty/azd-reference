'use strict';

// Offline preparation only. No HTTP client, credentials, deployment command,
// report archive extraction, path selection or runner-supplied configuration.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
const NAME = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/;
const MAX_PROJECTION = 256 * 1024;
const SOURCE_FILES = Object.freeze([
  'api/GetRoles/function.json', 'api/GetRoles/index.cjs', 'api/host.json',
  'api/package.json', 'api/roles.cjs', 'prepare.cjs',
]);
const ARTIFACT_FILES = Object.freeze([
  'api/GetRoles/function.json', 'api/GetRoles/index.cjs', 'api/host.json',
  'api/package.json', 'api/roles.cjs', 'api/policy.json',
  'app/index.html', 'app/staticwebapp.config.json',
].sort());
function matches(pattern, value) { return typeof value === 'string' && pattern.test(value); }
function fail() { throw new Error('SWA offline preparation contract rejected.'); }
function exactKeys(value, expected) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== expected.length ||
      Object.keys(value).sort().some((key, index) => key !== [...expected].sort()[index])) fail();
}
function sha256(bytes) { return crypto.createHash('sha256').update(bytes).digest('hex'); }
function jsonBytes(value) { return Buffer.from(JSON.stringify(value, null, 2) + '\n', 'utf8'); }
function readSource(relative) {
  const filename = path.join(__dirname, relative);
  if (!fs.lstatSync(filename).isFile() || fs.lstatSync(filename).isSymbolicLink()) fail();
  return fs.readFileSync(filename);
}
function sourceHashes() {
  return Object.fromEntries(SOURCE_FILES.map(name => [name, sha256(readSource(name))]));
}
function configFor(tenantId) {
  return {
    routes: [{ route: '/*', allowedRoles: ['report_reader'] }],
    auth: {
      rolesSource: '/api/GetRoles',
      identityProviders: { azureActiveDirectory: { registration: {
        openIdIssuer: `https://login.microsoftonline.com/${tenantId}/v2.0`,
        clientIdSettingName: 'AZURE_CLIENT_ID',
        clientSecretSettingName: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID',
      } } },
    },
    platform: { apiRuntime: 'node:22' },
    globalHeaders: {
      'Content-Security-Policy': "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; sandbox",
      'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    },
  };
}
function validateTarget(target) {
  exactKeys(target, ['tenantId', 'siteResourceId', 'environment', 'solutionEnvironmentId', 'applicationClientId', 'federatedIdentityClientId']);
  if (!matches(GUID, target.tenantId) || !matches(GUID, target.applicationClientId) || !matches(GUID, target.federatedIdentityClientId) ||
      target.applicationClientId === target.federatedIdentityClientId || target.environment !== 'production' ||
      (typeof target.solutionEnvironmentId !== 'string' || !matches(NAME, target.solutionEnvironmentId)) || typeof target.siteResourceId !== 'string' ||
      !/^\/subscriptions\/[0-9a-f-]{36}\/resourceGroups\/[a-zA-Z0-9_-]{1,90}\/providers\/Microsoft\.Web\/staticSites\/[a-zA-Z0-9][a-zA-Z0-9-]{0,59}$/.test(target.siteResourceId) ||
      !matches(GUID, target.siteResourceId.split('/')[2])) fail();
}
function validateApproval(approval) {
  exactKeys(approval, ['schemaVersion', 'target', 'sourceHashes', 'configSha256', 'policySha256', 'projection', 'previous']);
  if (approval.schemaVersion !== '1.0') fail();
  validateTarget(approval.target);
  exactKeys(approval.sourceHashes, SOURCE_FILES);
  for (const filename of SOURCE_FILES) {
    if (!matches(HASH, approval.sourceHashes[filename]) || approval.sourceHashes[filename] !== sha256(readSource(filename))) fail();
  }
  const policy = { tenantId: approval.target.tenantId, appRole: 'Report.Reader', siteRole: 'report_reader' };
  const configBytes = jsonBytes(configFor(approval.target.tenantId));
  const policyBytes = jsonBytes(policy);
  if (!matches(HASH, approval.configSha256) || sha256(configBytes) !== approval.configSha256 ||
      !matches(HASH, approval.policySha256) || sha256(policyBytes) !== approval.policySha256) fail();
  exactKeys(approval.previous, ['generation', 'artifactSha256']);
  if (!Number.isSafeInteger(approval.previous.generation) || approval.previous.generation < 0 ||
      !(approval.previous.generation === 0 ? approval.previous.artifactSha256 === null : matches(HASH, approval.previous.artifactSha256))) fail();
  exactKeys(approval.projection, ['byteLength', 'sha256', 'runId', 'generation']);
  const projection = approval.projection;
  if (!Number.isSafeInteger(projection.byteLength) || projection.byteLength < 1 || projection.byteLength > MAX_PROJECTION ||
      !matches(HASH, projection.sha256) || typeof projection.runId !== 'string' || !matches(NAME, projection.runId) ||
      !Number.isSafeInteger(projection.generation) || projection.generation !== approval.previous.generation + 1) fail();
  return { policyBytes, configBytes };
}
function text(value, max) {
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value)) fail();
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}
function renderProjection(bytes, approval) {
  if (!Buffer.isBuffer(bytes) || bytes.length !== approval.projection.byteLength || bytes.length > MAX_PROJECTION ||
      sha256(bytes) !== approval.projection.sha256) fail();
  let projection;
  try { projection = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch { fail(); }
  exactKeys(projection, ['schemaVersion', 'tenantId', 'environmentId', 'runId', 'generation', 'title', 'sections']);
  if (projection.schemaVersion !== '1.0' || projection.tenantId !== approval.target.tenantId ||
      projection.environmentId !== approval.target.solutionEnvironmentId || projection.runId !== approval.projection.runId ||
      projection.generation !== approval.projection.generation || !Array.isArray(projection.sections) ||
      projection.sections.length > 32) fail();
  const title = text(projection.title, 200);
  let html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${title}</title></head><body><h1>${title}</h1>`;
  html += `<p>Run: ${text(projection.runId, 64)}; generation: ${projection.generation}</p>`;
  let count = 0;
  for (const section of projection.sections) {
    exactKeys(section, ['heading', 'rows']);
    if (!Array.isArray(section.rows) || section.rows.length > 200 || (count += section.rows.length) > 1000) fail();
    html += `<section><h2>${text(section.heading, 200)}</h2><ul>`;
    for (const row of section.rows) html += `<li>${text(row, 2000)}</li>`;
    html += '</ul></section>';
  }
  html += '</body></html>\n';
  const output = Buffer.from(html, 'utf8');
  if (output.length > MAX_PROJECTION * 6) fail();
  return output;
}
function prepareBundle(projectionBytes, approval) {
  const { policyBytes, configBytes } = validateApproval(approval);
  const files = Object.fromEntries(SOURCE_FILES.filter(name => name !== 'prepare.cjs').map(name => [name, readSource(name)]));
  // Recheck exactly the bytes copied, not only the earlier filesystem reads.
  for (const [name, bytes] of Object.entries(files)) if (sha256(bytes) !== approval.sourceHashes[name]) fail();
  files['api/policy.json'] = policyBytes;
  files['app/staticwebapp.config.json'] = configBytes;
  files['app/index.html'] = renderProjection(projectionBytes, approval);
  const manifest = {
    schemaVersion: '1.0', state: 'prepared-not-published', target: approval.target,
    projection: approval.projection, previous: approval.previous, sourceHashes: approval.sourceHashes,
    files: ARTIFACT_FILES.map(name => ({ path: name, byteLength: files[name].length, sha256: sha256(files[name]) })),
  };
  const manifestBytes = jsonBytes(manifest);
  return { files, manifestBytes, manifestSha256: sha256(manifestBytes) };
}
function writeBundle(outputDirectory, bundle) {
  // A fresh directory only. An interrupted write remains for diagnosis; it is not
  // a valid artifact because the descriptor is written last. No cleanup/replay.
  exactKeys(bundle.files, ARTIFACT_FILES);
  if (sha256(bundle.manifestBytes) !== bundle.manifestSha256) fail();
  const descriptor = JSON.parse(bundle.manifestBytes);
  if (descriptor.state !== 'prepared-not-published' || !Array.isArray(descriptor.files) ||
      descriptor.files.length !== ARTIFACT_FILES.length ||
      descriptor.files.map(entry => entry.path).sort().join(',') !== ARTIFACT_FILES.join(',')) fail();
  for (const entry of descriptor.files) {
    if (!Buffer.isBuffer(bundle.files[entry.path]) || bundle.files[entry.path].length !== entry.byteLength ||
        sha256(bundle.files[entry.path]) !== entry.sha256) fail();
  }
  fs.mkdirSync(outputDirectory);
  fs.mkdirSync(path.join(outputDirectory, 'app'));
  fs.mkdirSync(path.join(outputDirectory, 'api'));
  fs.mkdirSync(path.join(outputDirectory, 'api', 'GetRoles'));
  for (const name of ARTIFACT_FILES) fs.writeFileSync(path.join(outputDirectory, name), bundle.files[name], { flag: 'wx' });
  fs.writeFileSync(path.join(outputDirectory, 'artifact.json'), bundle.manifestBytes, { flag: 'wx' });
  verifyBundle(outputDirectory, bundle.manifestSha256);
}
function verifyBundle(directory, expectedManifestSha256) {
  if (!matches(HASH, expectedManifestSha256) || fs.lstatSync(directory).isSymbolicLink()) fail();
  const actual = [];
  function walk(relative) {
    for (const name of fs.readdirSync(path.join(directory, relative))) {
      const child = relative ? `${relative}/${name}` : name;
      const info = fs.lstatSync(path.join(directory, child));
      if (info.isSymbolicLink()) fail();
      if (info.isDirectory()) {
        if (!['api', 'api/GetRoles', 'app'].includes(child)) fail();
        walk(child);
      } else if (info.isFile()) { actual.push(child); } else fail();
    }
  }
  walk('');
  if (actual.sort().join(',') !== [...ARTIFACT_FILES, 'artifact.json'].sort().join(',')) fail();
  const manifestPath = path.join(directory, 'artifact.json');
  if (fs.statSync(manifestPath).size > 16384) fail();
  const bytes = fs.readFileSync(manifestPath);
  if (sha256(bytes) !== expectedManifestSha256) fail();
  const manifest = JSON.parse(bytes);
  if (manifest.state !== 'prepared-not-published' || !Array.isArray(manifest.files) || manifest.files.length !== ARTIFACT_FILES.length ||
      manifest.files.map(entry => entry.path).sort().join(',') !== ARTIFACT_FILES.join(',')) fail();
  for (const entry of manifest.files) {
    if (!Number.isSafeInteger(entry.byteLength) || entry.byteLength < 1 || entry.byteLength > MAX_PROJECTION * 6 || !matches(HASH, entry.sha256)) fail();
    const filename = path.join(directory, entry.path);
    if (fs.statSync(filename).size !== entry.byteLength || sha256(fs.readFileSync(filename)) !== entry.sha256) fail();
  }
  return manifest;
}
module.exports = { sourceHashes, configFor, sha256, jsonBytes, prepareBundle, writeBundle, verifyBundle };
