'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const {TextDecoder} = require('node:util');
const Ajv2020 = require('ajv/dist/2020').default;
const {
  findNodeAtLocation,
  parseTree,
  printParseErrorCode,
  visit,
} = require('jsonc-parser');

const MAX_CATALOG_BYTES = 32 * 1024;
const MAX_JSON_DEPTH = 16;
const MAX_ISSUES = 100;
const SHA_PATTERN = /^[0-9a-f]{40}$/i;
const REPOSITORY_PATTERN = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

function sha256Buffer(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function assertCatalogPath(value) {
  if (typeof value !== 'string' || value.length === 0 || value.includes('\\') || value.includes('\0')) {
    throw new Error('catalog-path must be a non-empty repository-relative path using forward slashes.');
  }
  if (path.posix.isAbsolute(value)) {
    throw new Error('catalog-path must be repository-relative.');
  }
  const segments = value.split('/');
  if (segments.some((segment) => segment.length === 0 || segment === '.' || segment === '..')) {
    throw new Error('catalog-path must not contain empty, current-directory, or parent-directory segments.');
  }
  const normalized = path.posix.normalize(value);
  if (normalized !== value || normalized.startsWith('../')) {
    throw new Error('catalog-path must be normalized and remain within the repository.');
  }
  return normalized;
}

function lineColumnAt(text, offset) {
  const before = text.slice(0, Math.max(0, offset));
  const lines = before.split(/\r\n|\r|\n/);
  return {line: lines.length, column: lines[lines.length - 1].length + 1};
}

function findDuplicateProperties(text) {
  const objectStack = [];
  const duplicates = [];
  visit(text, {
    onObjectBegin: () => objectStack.push(new Set()),
    onObjectProperty: (name, offset) => {
      const current = objectStack[objectStack.length - 1];
      if (!current) return;
      if (current.has(name)) {
        const position = lineColumnAt(text, offset);
        duplicates.push({
          code: 'duplicateProperty',
          message: `Duplicate property "${name}" is not allowed.`,
          path: '',
          ...position,
        });
      }
      current.add(name);
    },
    onObjectEnd: () => objectStack.pop(),
  }, {allowTrailingComma: false, disallowComments: true});
  return duplicates;
}

function jsonPointerSegments(instancePath) {
  if (!instancePath) return [];
  return instancePath.slice(1).split('/').map((segment) =>
    segment.replace(/~1/g, '/').replace(/~0/g, '~')
  );
}

function depthOf(node) {
  if (node === null || typeof node !== 'object') return 1;
  const values = Array.isArray(node) ? node : Object.values(node);
  if (values.length === 0) return 1;
  return 1 + Math.max(...values.map(depthOf));
}

function compileSchema(schema) {
  const ajv = new Ajv2020({allErrors: true, strict: true, validateSchema: true});
  return ajv.compile(schema);
}

function parseAndValidateCatalog(text, schema) {
  const syntaxErrors = [];
  const tree = parseTree(text, syntaxErrors, {allowTrailingComma: false, disallowComments: true});
  if (syntaxErrors.length > 0 || !tree) {
    const issues = syntaxErrors.slice(0, MAX_ISSUES).map((error) => ({
      code: 'invalidJson',
      message: `Invalid JSON: ${printParseErrorCode(error.error)}.`,
      path: '',
      ...lineColumnAt(text, error.offset),
    }));
    if (issues.length === 0) {
      issues.push({code: 'invalidJson', message: 'The catalog must contain one JSON value.', path: '', line: 1, column: 1});
    }
    return {valid: false, errors: issues, notices: []};
  }

  const duplicateIssues = findDuplicateProperties(text);
  if (duplicateIssues.length > 0) {
    return {valid: false, errors: duplicateIssues.slice(0, MAX_ISSUES), notices: []};
  }

  let value;
  try {
    value = JSON.parse(text);
  }
  catch (error) {
    return {
      valid: false,
      errors: [{code: 'invalidJson', message: `Invalid JSON: ${error.message}`, path: '', line: 1, column: 1}],
      notices: [],
    };
  }

  if (depthOf(value) > MAX_JSON_DEPTH) {
    return {
      valid: false,
      errors: [{code: 'maxDepth', message: `JSON depth exceeds ${MAX_JSON_DEPTH}.`, path: '', line: 1, column: 1}],
      notices: [],
    };
  }

  const validate = compileSchema(schema);
  if (validate(value)) return {valid: true, errors: [], notices: []};

  const issues = validate.errors.slice(0, MAX_ISSUES).map((error) => {
    const segments = jsonPointerSegments(error.instancePath);
    if (error.keyword === 'additionalProperties' && error.params.additionalProperty) {
      segments.push(error.params.additionalProperty);
    }
    const node = findNodeAtLocation(tree, segments) || tree;
    return {
      code: `schema.${error.keyword}`,
      message: `${error.instancePath || '/'} ${error.message}`,
      path: error.instancePath || '',
      ...lineColumnAt(text, node.offset),
    };
  });
  return {valid: false, errors: issues, notices: []};
}

function resolveEventContext(payload, eventName, environment) {
  const repository = payload.repository || {};
  const baseRepositoryId = String(repository.id || environment.GITHUB_REPOSITORY_ID || '');
  if (!baseRepositoryId) throw new Error('The event does not identify the base repository ID.');

  if (eventName === 'pull_request') {
    const head = payload.pull_request?.head;
    if (!head?.repo?.id || !head?.repo?.full_name || !head?.sha) {
      throw new Error('The pull request event does not contain an accessible head repository and commit.');
    }
    return {
      eventKind: eventName,
      baseRepositoryId,
      sourceRepositoryId: String(head.repo.id),
      sourceRepositoryFullName: String(head.repo.full_name),
      sourceRepositoryPrivate: Boolean(head.repo.private),
      validatedCommitSha: String(head.sha),
    };
  }

  if (eventName === 'push' || eventName === 'workflow_dispatch') {
    const fullName = String(repository.full_name || environment.GITHUB_REPOSITORY || '');
    const sha = String(environment.GITHUB_SHA || payload.after || '');
    if (!fullName || !sha) throw new Error(`${eventName} does not identify the repository and commit.`);
    return {
      eventKind: eventName,
      baseRepositoryId,
      sourceRepositoryId: baseRepositoryId,
      sourceRepositoryFullName: fullName,
      sourceRepositoryPrivate: Boolean(repository.private),
      validatedCommitSha: sha,
    };
  }

  throw new Error(`Unsupported event: ${eventName}`);
}

function assertEventContext(context) {
  if (!REPOSITORY_PATTERN.test(context.sourceRepositoryFullName)) {
    throw new Error('The source repository name is invalid.');
  }
  if (!SHA_PATTERN.test(context.validatedCommitSha)) {
    throw new Error('The validated commit must be a full 40-character SHA.');
  }
}

function isLfsPointer(buffer) {
  return buffer.subarray(0, 128).toString('utf8').startsWith('version https://git-lfs.github.com/spec/v1');
}

async function fetchCatalog({apiUrl, token, context, catalogPath, fetchImpl = fetch}) {
  assertEventContext(context);
  const encodedPath = catalogPath.split('/').map(encodeURIComponent).join('/');
  const encodedRef = encodeURIComponent(context.validatedCommitSha);
  const url = `${apiUrl}/repos/${context.sourceRepositoryFullName}/contents/${encodedPath}?ref=${encodedRef}`;
  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'azd-catalog-validator',
    'X-GitHub-Api-Version': '2026-03-10',
  };
  const isExternalPublicFork = context.sourceRepositoryId !== context.baseRepositoryId &&
    context.sourceRepositoryPrivate === false;
  if (!isExternalPublicFork) headers.Authorization = `Bearer ${token}`;

  const commitUrl = `${apiUrl}/repos/${context.sourceRepositoryFullName}/git/commits/${encodedRef}`;
  const commitResponse = await fetchImpl(commitUrl, {headers});
  if (!commitResponse.ok) {
    const error = new Error(`The source repository commit is unavailable (${commitResponse.status} ${commitResponse.statusText}).`);
    error.operational = true;
    throw error;
  }

  const response = await fetchImpl(url, {headers});

  if (response.status === 404) {
    return {missing: true};
  }
  if (!response.ok) {
    const error = new Error(`GitHub Contents API returned ${response.status} ${response.statusText}.`);
    error.operational = true;
    throw error;
  }

  const item = await response.json();
  if (item.type !== 'file' || item.target || item.submodule_git_url) {
    throw new Error('The catalog path must resolve to an ordinary repository blob, not a symlink or submodule.');
  }
  if (item.size > MAX_CATALOG_BYTES) {
    throw new Error(`The catalog exceeds the ${MAX_CATALOG_BYTES}-byte limit.`);
  }
  if (item.encoding !== 'base64' || typeof item.content !== 'string') {
    const error = new Error('GitHub did not return inline base64 catalog content.');
    error.operational = true;
    throw error;
  }

  const buffer = Buffer.from(item.content.replace(/\s/g, ''), 'base64');
  if (buffer.length > MAX_CATALOG_BYTES) {
    throw new Error(`The catalog exceeds the ${MAX_CATALOG_BYTES}-byte limit.`);
  }
  if (isLfsPointer(buffer)) {
    throw new Error('Git LFS pointers are not supported for catalog metadata.');
  }

  let text;
  try {
    text = new TextDecoder('utf-8', {fatal: true}).decode(buffer);
  }
  catch {
    throw new Error('The catalog must be valid UTF-8.');
  }
  return {missing: false, blobSha: String(item.sha || ''), buffer, text};
}

module.exports = {
  MAX_CATALOG_BYTES,
  MAX_ISSUES,
  assertCatalogPath,
  assertEventContext,
  fetchCatalog,
  isLfsPointer,
  parseAndValidateCatalog,
  resolveEventContext,
  sha256Buffer,
  sha256File,
};
