'use strict';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  MAX_CATALOG_BYTES,
  assertCatalogPath,
  fetchCatalog,
  isLfsPointer,
  parseAndValidateCatalog,
  resolveEventContext,
} = require('../src/catalog');

const actionRoot = path.resolve(__dirname, '..');
const repositoryRoot = path.resolve(actionRoot, '..', '..', '..');
const schema = JSON.parse(fs.readFileSync(path.join(repositoryRoot, 'schemas/catalog-metadata.schema.json'), 'utf8'));
const validFixture = fs.readFileSync(path.join(repositoryRoot, 'tests/fixtures/valid/catalog-metadata.json'), 'utf8');
const invalidFixture = fs.readFileSync(path.join(repositoryRoot, 'tests/fixtures/invalid/catalog-metadata.json'), 'utf8');

test('accepts canonical valid metadata and an empty object', () => {
  assert.equal(parseAndValidateCatalog(validFixture, schema).valid, true);
  assert.equal(parseAndValidateCatalog('{}', schema).valid, true);
});

test('rejects canonical invalid metadata and unknown properties', () => {
  assert.equal(parseAndValidateCatalog(invalidFixture, schema).valid, false);
  const result = parseAndValidateCatalog('{"unexpected":true}', schema);
  assert.equal(result.valid, false);
  assert.equal(result.errors[0].code, 'schema.additionalProperties');
});

test('rejects duplicate properties, comments, and excessive strings', () => {
  assert.equal(parseAndValidateCatalog('{"title":"one","title":"two"}', schema).errors[0].code, 'duplicateProperty');
  assert.equal(parseAndValidateCatalog('{/* comment */"title":"one"}', schema).valid, false);
  assert.equal(parseAndValidateCatalog(JSON.stringify({title: 'x'.repeat(4097)}), schema).valid, false);
});

test('rejects unsafe catalog paths', () => {
  assert.equal(assertCatalogPath('.azd/catalog.json'), '.azd/catalog.json');
  assert.equal(assertCatalogPath('solution/.azd/catalog.json'), 'solution/.azd/catalog.json');
  for (const value of ['../catalog.json', '/catalog.json', 'solution//catalog.json', 'solution\\catalog.json']) {
    assert.throws(() => assertCatalogPath(value));
  }
});

test('binds pull request and push events to exact repository identities and SHAs', () => {
  const sha = 'a'.repeat(40);
  const pullRequest = resolveEventContext({
    repository: {id: 1, full_name: 'base/repo'},
    pull_request: {head: {sha, repo: {id: 2, full_name: 'fork/repo', private: false}}},
  }, 'pull_request', {});
  assert.deepEqual(pullRequest, {
    eventKind: 'pull_request',
    baseRepositoryId: '1',
    sourceRepositoryId: '2',
    sourceRepositoryFullName: 'fork/repo',
    sourceRepositoryPrivate: false,
    validatedCommitSha: sha,
  });

  const push = resolveEventContext({repository: {id: 1, full_name: 'base/repo'}}, 'push', {GITHUB_SHA: sha});
  assert.equal(push.sourceRepositoryFullName, 'base/repo');
  assert.equal(push.validatedCommitSha, sha);
});

test('recognizes Git LFS pointers', () => {
  assert.equal(isLfsPointer(Buffer.from('version https://git-lfs.github.com/spec/v1\n')), true);
  assert.equal(isLfsPointer(Buffer.from('{"title":"normal"}')), false);
});

test('fetches the exact repository, path, and full commit', async () => {
  const calls = [];
  const result = await fetchCatalog({
    apiUrl: 'https://api.github.test',
    token: 'secret',
    context: {
      baseRepositoryId: '1',
      sourceRepositoryId: '2',
      sourceRepositoryFullName: 'fork-owner/example',
      sourceRepositoryPrivate: false,
      validatedCommitSha: 'a'.repeat(40),
    },
    catalogPath: '.azd/catalog.json',
    fetchImpl: async (url, options) => {
      calls.push({url, options});
      if (url.includes('/git/commits/')) return {ok: true, status: 200};
      return {
        ok: true,
        status: 200,
        async json() {
          return {
            type: 'file',
            size: 2,
            encoding: 'base64',
            content: Buffer.from('{}').toString('base64'),
            sha: 'blob-sha',
          };
        },
      };
    },
  });

  assert.equal(result.text, '{}');
  assert.equal(result.blobSha, 'blob-sha');
  assert.equal(calls[1].url, `https://api.github.test/repos/fork-owner/example/contents/.azd/catalog.json?ref=${'a'.repeat(40)}`);
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.equal(calls[1].options.headers.Authorization, undefined);
});

test('treats a missing enrolled catalog as a validation result', async () => {
  const result = await fetchCatalog({
    apiUrl: 'https://api.github.test',
    token: 'secret',
    context: {baseRepositoryId: '1', sourceRepositoryId: '1', sourceRepositoryFullName: 'owner/example', sourceRepositoryPrivate: false, validatedCommitSha: 'b'.repeat(40)},
    catalogPath: '.azd/catalog.json',
    fetchImpl: async (url) => url.includes('/git/commits/')
      ? ({ok: true, status: 200})
      : ({ok: false, status: 404, statusText: 'Not Found'}),
  });
  assert.deepEqual(result, {missing: true});
});

test('classifies API failures as operational errors', async () => {
  await assert.rejects(
    fetchCatalog({
      apiUrl: 'https://api.github.test',
      token: 'secret',
      context: {baseRepositoryId: '1', sourceRepositoryId: '1', sourceRepositoryFullName: 'owner/example', sourceRepositoryPrivate: false, validatedCommitSha: 'c'.repeat(40)},
      catalogPath: '.azd/catalog.json',
      fetchImpl: async () => ({ok: false, status: 503, statusText: 'Unavailable'}),
    }),
    (error) => error.operational === true && /503/.test(error.message),
  );
});

test('rejects symlinks and oversized blobs', async () => {
  const base = {
    apiUrl: 'https://api.github.test',
    token: 'secret',
    context: {baseRepositoryId: '1', sourceRepositoryId: '1', sourceRepositoryFullName: 'owner/example', sourceRepositoryPrivate: false, validatedCommitSha: 'd'.repeat(40)},
    catalogPath: '.azd/catalog.json',
  };
  await assert.rejects(
    fetchCatalog({...base, fetchImpl: async (url) => url.includes('/git/commits/')
      ? ({ok: true, status: 200})
      : ({
        ok: true,
        status: 200,
        async json() { return {type: 'file', target: '../elsewhere', size: 2, encoding: 'base64', content: 'e30='}; },
      })}),
    /ordinary repository blob/,
  );
  await assert.rejects(
    fetchCatalog({...base, fetchImpl: async (url) => url.includes('/git/commits/')
      ? ({ok: true, status: 200})
      : ({
        ok: true,
        status: 200,
        async json() { return {type: 'file', size: MAX_CATALOG_BYTES + 1, encoding: 'base64', content: ''}; },
      })}),
    /byte limit/,
  );
});

test('classifies an unavailable source commit as operational', async () => {
  await assert.rejects(
    fetchCatalog({
      apiUrl: 'https://api.github.test',
      token: 'secret',
      context: {baseRepositoryId: '1', sourceRepositoryId: '2', sourceRepositoryFullName: 'fork/example', sourceRepositoryPrivate: false, validatedCommitSha: 'e'.repeat(40)},
      catalogPath: '.azd/catalog.json',
      fetchImpl: async () => ({ok: false, status: 404, statusText: 'Not Found'}),
    }),
    (error) => error.operational === true && /commit is unavailable/.test(error.message),
  );
});
