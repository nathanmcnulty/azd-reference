'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const source = path.resolve(__dirname, '../../examples/swa-report-viewer');
const { getRoles } = require(path.join(source, 'api/roles.cjs'));
const { sourceHashes, configFor, sha256, jsonBytes, prepareBundle, writeBundle, verifyBundle } = require(path.join(source, 'prepare.cjs'));
const tenantId = '11111111-1111-1111-1111-111111111111';
const objectId = '22222222-2222-2222-2222-222222222222';
const policy = { tenantId, appRole: 'Report.Reader', siteRole: 'report_reader' };
function validBody() {
  return { identityProvider: 'aad', userId: 'opaque-platform-user', claims: [
    { typ: 'http://schemas.microsoft.com/identity/claims/tenantid', val: tenantId },
    { typ: 'http://schemas.microsoft.com/identity/claims/objectidentifier', val: objectId },
    { typ: 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role', val: 'Report.Reader' },
  ] };
}
function fixture() {
  const projection = { schemaVersion: '1.0', tenantId, environmentId: 'fixture', runId: 'run-1', generation: 1,
    title: 'Synthetic report', sections: [{ heading: 'Results', rows: ['Test passed'] }] };
  const bytes = jsonBytes(projection);
  const approval = { schemaVersion: '1.0', target: {
    tenantId, siteResourceId: '/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/fixture/providers/Microsoft.Web/staticSites/fixture',
    environment: 'production', solutionEnvironmentId: 'fixture', applicationClientId: '44444444-4444-4444-4444-444444444444',
    federatedIdentityClientId: '55555555-5555-5555-5555-555555555555',
  }, sourceHashes: sourceHashes(), configSha256: sha256(jsonBytes(configFor(tenantId))), policySha256: sha256(jsonBytes(policy)),
  projection: { byteLength: bytes.length, sha256: sha256(bytes), runId: projection.runId, generation: 1 },
  previous: { generation: 0, artifactSha256: null } };
  return { projection, bytes, approval };
}
function projectionCase(mutate) {
  const value = fixture(); mutate(value.projection);
  value.bytes = jsonBytes(value.projection);
  value.approval.projection.byteLength = value.bytes.length;
  value.approval.projection.sha256 = sha256(value.bytes);
  return value;
}
function temporary(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'swa-offline-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  return path.join(root, 'artifact');
}

test('maps the exact tenant app role, never built-in authenticated or admin', () => {
  assert.deepEqual(getRoles(validBody(), policy), { roles: ['report_reader'] });
});
test('accepts the explicitly supported short claim names', () => {
  const body = validBody(); body.claims.forEach((c, i) => { c.typ = ['tid', 'oid', 'roles'][i]; });
  assert.deepEqual(getRoles(body, policy), { roles: ['report_reader'] });
});
test('ignores access tokens and client role/header assertions', () => {
  const body = validBody(); body.accessToken = 'not-used'; body.userRoles = ['administrator'];
  body.headers = { 'x-ms-client-principal': 'forged' };
  assert.deepEqual(getRoles(body, policy), { roles: ['report_reader'] });
  body.claims.pop(); assert.deepEqual(getRoles(body, policy), { roles: [] });
});
const roleMutations = {
  'missing body': () => null,
  'array body': () => [],
  'missing provider': b => { delete b.identityProvider; return b; },
  'other provider': b => { b.identityProvider = 'github'; return b; },
  'provider case variant': b => { b.identityProvider = 'AAD'; return b; },
  'empty user': b => { b.userId = ''; return b; },
  'oversize user': b => { b.userId = 'a'.repeat(257); return b; },
  'no claims': b => { b.claims = []; return b; },
  'object claims': b => { b.claims = {}; return b; },
  'too many claims': b => { b.claims = Array(129).fill({ typ: 'x', val: 'x' }); return b; },
  'missing tenant': b => { b.claims.shift(); return b; },
  'wrong tenant': b => { b.claims[0].val = objectId; return b; },
  'ambiguous equal tenant': b => { b.claims.push({ typ: 'tid', val: tenantId }); return b; },
  'ambiguous different tenant': b => { b.claims.push({ typ: 'tid', val: objectId }); return b; },
  'missing object': b => { b.claims.splice(1, 1); return b; },
  'malformed object': b => { b.claims[1].val = 'not-a-guid'; return b; },
  'duplicate object': b => { b.claims.push({ typ: 'oid', val: objectId }); return b; },
  'unassigned': b => { b.claims.pop(); return b; },
  'wrong app role': b => { b.claims[2].val = 'Report.Admin'; return b; },
  'case variant role': b => { b.claims[2].val = 'report.reader'; return b; },
  'role array': b => { b.claims[2].val = ['Report.Reader']; return b; },
  'JSON role string': b => { b.claims[2].val = '["Report.Reader"]'; return b; },
  'duplicate role': b => { b.claims.push({ typ: 'roles', val: 'Report.Reader' }); return b; },
  'extra claim properties': b => { b.claims[2].extra = true; return b; },
  'oversize claim': b => { b.claims.push({ typ: 'x', val: 'a'.repeat(2049) }); return b; },
  'null claim': b => { b.claims.push(null); return b; },
};
for (const marker of ['_claim_names', '_claim_sources', 'hasgroups']) roleMutations[`overage ${marker}`] = b => { b.claims.push({ typ: marker, val: 'true' }); return b; };
for (const [name, mutate] of Object.entries(roleMutations)) test(`denies ${name}`, () => assert.deepEqual(getRoles(mutate(validBody()), policy), { roles: [] }));
for (const invalid of [null, {}, { ...policy, tenantId: 'common' }, { ...policy, appRole: 'Admin' }, { ...policy, siteRole: 'authenticated' }]) {
  test(`fails closed for invalid policy ${JSON.stringify(invalid)}`, () => assert.deepEqual(getRoles(validBody(), invalid), { roles: [] }));
}

test('fixed configuration protects all paths without a fallback bypass', () => {
  const config = configFor(tenantId);
  assert.deepEqual(config.routes, [{ route: '/*', allowedRoles: ['report_reader'] }]);
  assert.equal(config.navigationFallback, undefined);
  assert.equal(config.auth.rolesSource, '/api/GetRoles');
  assert.equal(config.auth.identityProviders.azureActiveDirectory.registration.openIdIssuer, `https://login.microsoftonline.com/${tenantId}/v2.0`);
  assert.equal(config.auth.identityProviders.azureActiveDirectory.registration.clientSecretSettingName, 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID');
  assert.equal(config.platform.apiRuntime, 'node:22');
  assert.equal(config.globalHeaders['Cache-Control'], 'no-store');
  assert.match(config.globalHeaders['Content-Security-Policy'], /default-src 'none'/);
});
test('prepares deterministic exact files and verifies the serialized artifact', t => {
  const { bytes, approval } = fixture(); const first = prepareBundle(bytes, approval); const second = prepareBundle(bytes, approval);
  assert.equal(first.manifestSha256, second.manifestSha256);
  const output = temporary(t); writeBundle(output, first);
  const result = verifyBundle(output, first.manifestSha256);
  assert.equal(result.state, 'prepared-not-published');
  assert.equal(result.files.length, 8);
  assert.equal(result.target.siteResourceId, approval.target.siteResourceId);
  assert.deepEqual(result.previous, { generation: 0, artifactSha256: null });
  assert.match(fs.readFileSync(path.join(output, 'app/index.html'), 'utf8'), /Test passed/);
});
test('escapes active report markup instead of copying executable HTML', () => {
  const { bytes, approval } = projectionCase(p => { p.title = '<script>alert(1)</script>'; p.sections[0].rows = ['<img src="https://evil.invalid" onerror="x">', '&<>"\'']; });
  const html = prepareBundle(bytes, approval).files['app/index.html'].toString();
  assert(!html.includes('<script')); assert(!html.includes('<img')); assert(html.includes('&lt;script&gt;'));
  assert(html.includes('&amp;&lt;&gt;&quot;&#39;'));
});
test('new artifact is repeatable but cannot overwrite a previously prepared directory', t => {
  const { bytes, approval } = fixture(); const bundle = prepareBundle(bytes, approval); const output = temporary(t);
  writeBundle(output, bundle);
  assert.throws(() => writeBundle(output, bundle), /EEXIST/);
  assert.equal(verifyBundle(output, bundle.manifestSha256).projection.generation, 1);
});
test('exact successor records previous generation without pretending to publish or CAS', () => {
  const { bytes, approval } = projectionCase(p => { p.generation = 8; });
  approval.previous = { generation: 7, artifactSha256: 'a'.repeat(64) }; approval.projection.generation = 8;
  const result = JSON.parse(prepareBundle(bytes, approval).manifestBytes);
  assert.equal(result.previous.generation, 7); assert.equal(result.state, 'prepared-not-published');
});
const approvalMutations = {
  'extra approval field': a => { a.deploymentToken = 'not-a-token'; },
  'wrong schema': a => { a.schemaVersion = '2.0'; },
  'preview environment': a => { a.target.environment = 'preview'; },
  'same sign-in app and identity': a => { a.target.federatedIdentityClientId = a.target.applicationClientId; },
  'invalid sign-in app': a => { a.target.applicationClientId = 'invalid'; },
  'invalid FIC identity': a => { a.target.federatedIdentityClientId = 'invalid'; },
  'other tenant': a => { a.target.tenantId = objectId; },
  'invalid target ID': a => { a.target.siteResourceId = 'https://untrusted.invalid'; },
  'invalid subscription GUID': a => { a.target.siteResourceId = a.target.siteResourceId.replace('33333333-3333-3333-3333-333333333333', '-'.repeat(36)); },
  'config substitution': a => { a.configSha256 = 'a'.repeat(64); },
  'policy substitution': a => { a.policySha256 = 'a'.repeat(64); },
  'missing source hash': a => { delete a.sourceHashes['api/roles.cjs']; },
  'source hash substitution': a => { a.sourceHashes['api/GetRoles/index.cjs'] = 'a'.repeat(64); },
  'extra source': a => { a.sourceHashes['../evil'] = 'a'.repeat(64); },
  'publisher code drift': a => { a.sourceHashes['prepare.cjs'] = 'a'.repeat(64); },
  'projection hash mismatch': a => { a.projection.sha256 = 'a'.repeat(64); },
  'projection length mismatch': a => { a.projection.byteLength += 1; },
  'excessive size': a => { a.projection.byteLength = 262145; },
  'unknown prior generation': a => { a.previous.generation = -1; },
  'missing prior digest': a => { a.previous.generation = 1; a.projection.generation = 2; },
  'stale generation': a => { a.projection.generation = 0; },
  'generation gap': a => { a.projection.generation = 2; },
  'fractional generation': a => { a.projection.generation = 1.5; },
  'unsafe integer': a => { a.previous.generation = Number.MAX_SAFE_INTEGER; a.previous.artifactSha256 = 'a'.repeat(64); a.projection.generation = Number.MAX_SAFE_INTEGER + 1; },
};
for (const [name, mutate] of Object.entries(approvalMutations)) test(`rejects ${name}`, () => {
  const { bytes, approval } = fixture(); mutate(approval); assert.throws(() => prepareBundle(bytes, approval));
});
const projectionMutations = {
  'report config': p => { p.config = { routes: [] }; },
  'report code': p => { p.api = 'malicious'; },
  'report path': p => { p.path = '../staticwebapp.config.json'; },
  'report URL': p => { p.url = 'https://evil.invalid'; },
  'report assets': p => { p.assets = ['evil.js']; },
  'wrong projection tenant': p => { p.tenantId = objectId; },
  'wrong projection environment': p => { p.environmentId = 'other'; },
  'wrong projection run': p => { p.runId = 'run-2'; },
  'wrong projection generation': p => { p.generation = 2; },
  'extra section keys': p => { p.sections[0].html = 'raw'; },
  'section overflow': p => { p.sections = Array(33).fill({ heading: 'x', rows: [] }); },
  'row overflow': p => { p.sections[0].rows = Array(201).fill('x'); },
  'total row overflow': p => { p.sections = Array(6).fill({ heading: 'x', rows: Array(200).fill('x') }); },
  'text overflow': p => { p.sections[0].rows = ['x'.repeat(2001)]; },
  'control characters': p => { p.title = 'x\u0000y'; },
  'nonstring report value': p => { p.sections[0].rows = [{ key: 'x' }]; },
};
for (const [name, mutate] of Object.entries(projectionMutations)) test(`rejects ${name}`, () => {
  const { bytes, approval } = projectionCase(mutate); assert.throws(() => prepareBundle(bytes, approval));
});
for (const bytes of [Buffer.from('{invalid'), Buffer.from([0xff])]) test(`rejects malformed projection ${bytes.toString('hex')}`, () => {
  const { approval } = fixture(); approval.projection.byteLength = bytes.length; approval.projection.sha256 = sha256(bytes);
  assert.throws(() => prepareBundle(bytes, approval));
});
for (const file of ['api/roles.cjs', 'api/GetRoles/index.cjs', 'api/policy.json', 'app/index.html', 'app/staticwebapp.config.json']) {
  test(`rejects prepared file tampering: ${file}`, t => {
    const { bytes, approval } = fixture(); const bundle = prepareBundle(bytes, approval); const output = temporary(t); writeBundle(output, bundle);
    fs.appendFileSync(path.join(output, file), 'tampered'); assert.throws(() => verifyBundle(output, bundle.manifestSha256));
  });
}
for (const kind of ['extra file', 'missing file', 'extra directory', 'descriptor tamper', 'wrong external digest', 'partial output']) {
  test(`rejects artifact inventory: ${kind}`, t => {
    const { bytes, approval } = fixture(); const bundle = prepareBundle(bytes, approval); const output = temporary(t); writeBundle(output, bundle);
    if (kind === 'extra file') fs.writeFileSync(path.join(output, 'app/evil.js'), 'evil');
    if (kind === 'missing file') fs.unlinkSync(path.join(output, 'app/index.html'));
    if (kind === 'extra directory') fs.mkdirSync(path.join(output, 'unexpected'));
    if (kind === 'descriptor tamper') fs.appendFileSync(path.join(output, 'artifact.json'), ' ');
    if (kind === 'partial output') fs.unlinkSync(path.join(output, 'artifact.json'));
    assert.throws(() => verifyBundle(output, kind === 'wrong external digest' ? 'a'.repeat(64) : bundle.manifestSha256));
  });
}
test('rejects file symlink substitution', { skip: process.platform === 'win32' ? 'Windows symlink privilege is not assumed.' : false }, t => {
  const { bytes, approval } = fixture(); const bundle = prepareBundle(bytes, approval); const output = temporary(t); writeBundle(output, bundle);
  fs.unlinkSync(path.join(output, 'app/index.html'));
  fs.symlinkSync(path.join(output, 'api/roles.cjs'), path.join(output, 'app/index.html'));
  assert.throws(() => verifyBundle(output, bundle.manifestSha256));
});
test('rejects a modified in-memory bundle before creating any output', t => {
  const { bytes, approval } = fixture(); const bundle = prepareBundle(bytes, approval); const output = temporary(t);
  bundle.files['app/staticwebapp.config.json'] = Buffer.from('{}');
  assert.throws(() => writeBundle(output, bundle)); assert.equal(fs.existsSync(output), false);
});
test('actual packaged callback maps only POST bodies and never header-only identity', async t => {
  const { bytes, approval } = fixture(); const bundle = prepareBundle(bytes, approval); const output = temporary(t); writeBundle(output, bundle);
  const handler = require(path.join(output, 'api/GetRoles/index.cjs'));
  const context = { log: () => assert.fail('must not log identity or tokens') };
  await handler(context, { method: 'POST', body: validBody() }); assert.deepEqual(context.res.body, { roles: ['report_reader'] });
  assert.equal(context.res.headers['Cache-Control'], 'no-store');
  await handler(context, { method: 'GET', body: validBody() }); assert.deepEqual(context.res.body, { roles: [] });
  await handler(context, { method: 'POST', headers: { 'x-ms-client-principal': Buffer.from(JSON.stringify(validBody())).toString('base64') } });
  assert.deepEqual(context.res.body, { roles: [] });
  await handler(context, null); assert.deepEqual(context.res.body, { roles: [] });
});

for (const field of ['tenantId', 'applicationClientId', 'federatedIdentityClientId', 'solutionEnvironmentId']) {
  for (const kind of ['array', 'object', 'number', 'null']) {
    test(`rejects non-string target ${field}: ${kind}`, () => {
      const { bytes, approval } = fixture();
      const old = approval.target[field];
      approval.target[field] = { array: [old], object: { value: old }, number: 123, null: null }[kind];
      assert.throws(() => prepareBundle(bytes, approval));
    });
  }
}
test('rejects distinct array objects containing the same application and FIC ID', () => {
  const { bytes, approval } = fixture();
  approval.target.applicationClientId = [objectId]; approval.target.federatedIdentityClientId = [objectId];
  assert.throws(() => prepareBundle(bytes, approval));
});
for (const kind of ['array', 'object', 'number', 'null']) {
  for (const field of ['configSha256', 'policySha256', 'sourceHash', 'projectionHash', 'previousHash']) {
    test(`rejects non-string ${field}: ${kind}`, () => {
      const { bytes, approval } = projectionCase(p => { p.generation = 2; });
      approval.projection.generation = 2; approval.previous = { generation: 1, artifactSha256: 'a'.repeat(64) };
      let holder = approval, key = field;
      if (field === 'sourceHash') { holder = approval.sourceHashes; key = 'api/roles.cjs'; }
      if (field === 'projectionHash') { holder = approval.projection; key = 'sha256'; }
      if (field === 'previousHash') { holder = approval.previous; key = 'artifactSha256'; }
      const old = holder[key]; holder[key] = { array: [old], object: { value: old }, number: 123, null: null }[kind];
      assert.throws(() => prepareBundle(bytes, approval));
    });
  }
}
