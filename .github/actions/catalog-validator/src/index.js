'use strict';

const fs = require('node:fs');
const path = require('node:path');
const core = require('@actions/core');
const {
  assertCatalogPath,
  fetchCatalog,
  parseAndValidateCatalog,
  resolveEventContext,
  sha256File,
} = require('./catalog');

const EXPECTED_WORKFLOW_REPOSITORY = 'nathanmcnulty/azd-reference';
const EXPECTED_WORKFLOW_PATH = '.github/workflows/catalog-metadata.yml';
const FULL_SHA = /^[0-9a-f]{40}$/i;
const MAX_DIAGNOSTIC_LENGTH = 1024;

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function verifyPackage(actionRoot) {
  const manifestPath = path.join(actionRoot, 'catalog-validator.manifest.json');
  const manifest = readJson(manifestPath);
  const schemaPath = path.join(actionRoot, manifest.schemaPath);
  const validatorPath = path.join(actionRoot, manifest.validatorPath);
  if (sha256File(schemaPath) !== manifest.schemaSha256) {
    throw new Error('The bundled catalog schema does not match its release manifest.');
  }
  if (sha256File(validatorPath) !== manifest.validatorSha256) {
    throw new Error('The bundled validator does not match its release manifest.');
  }
  return {manifest, schemaPath};
}

function readEventPayload() {
  const eventPath = process.env.GITHUB_EVENT_PATH;
  if (!eventPath) throw new Error('GITHUB_EVENT_PATH is not available.');
  return readJson(eventPath);
}

function assertWorkflowIdentity() {
  const repository = core.getInput('workflow-repository', {required: true});
  const filePath = core.getInput('workflow-file-path', {required: true});
  const sha = core.getInput('workflow-sha', {required: true});
  if (repository !== EXPECTED_WORKFLOW_REPOSITORY) {
    throw new Error(`Unexpected reusable workflow repository: ${repository}`);
  }
  if (filePath !== EXPECTED_WORKFLOW_PATH) {
    throw new Error(`Unexpected reusable workflow path: ${filePath}`);
  }
  if (!FULL_SHA.test(sha)) {
    throw new Error('The reusable workflow must run from a full 40-character commit SHA.');
  }
  return {workflowRepository: repository, workflowPath: filePath, workflowSha: sha};
}

function annotateIssues(catalogPath, errors) {
  for (const issue of errors.slice(0, 50)) {
    const properties = {title: issue.code, file: catalogPath};
    if (issue.line) {
      properties.startLine = issue.line;
      properties.endLine = issue.line;
      properties.startColumn = issue.column || 1;
      properties.endColumn = issue.column || 1;
    }
    core.error(issue.message, properties);
  }
}

function boundIssues(issues) {
  return issues.slice(0, 100).map((issue) => ({
    ...issue,
    message: String(issue.message || '').slice(0, MAX_DIAGNOSTIC_LENGTH),
    path: String(issue.path || '').slice(0, 512),
  }));
}

async function writeSummary(result) {
  const rows = [
    [{data: 'Outcome', header: true}, result.outcome],
    [{data: 'Catalog', header: true}, result.catalogPath],
    [{data: 'Commit', header: true}, result.validatedCommitSha],
    [{data: 'Schema', header: true}, `${result.schemaVersion} (${result.schemaSha256})`],
    [{data: 'Validator', header: true}, `${result.validatorVersion} (${result.workflowSha})`],
  ];
  core.summary.addHeading('azd catalog metadata').addTable(rows);
  if (result.errors.length) {
    core.summary.addHeading('Errors', 2).addList(result.errors.map((issue) => issue.message));
  }
  if (result.notices.length) {
    core.summary.addHeading('Notices', 2).addList(result.notices.map((issue) => issue.message));
  }
  await core.summary.write();
}

async function run() {
  const started = Date.now();
  const result = {
    contractVersion: '1.0',
    eventKind: null,
    baseRepositoryId: null,
    sourceRepositoryId: null,
    sourceRepositoryFullName: null,
    validatedCommitSha: null,
    catalogPath: null,
    catalogBlobSha: null,
    workflowRepository: null,
    workflowPath: null,
    workflowSha: null,
    schemaVersion: null,
    schemaSha256: null,
    validatorVersion: null,
    validatorSha256: null,
    outcome: 'operational_error',
    errors: [],
    notices: [],
    durationMs: 0,
  };
  try {
    const actionRoot = path.resolve(__dirname, '..');
    const {manifest, schemaPath} = verifyPackage(actionRoot);
    Object.assign(result, {
      contractVersion: manifest.contractVersion,
      schemaVersion: manifest.schemaVersion,
      schemaSha256: manifest.schemaSha256,
      validatorVersion: manifest.validatorVersion,
      validatorSha256: manifest.validatorSha256,
    });
    const workflowIdentity = assertWorkflowIdentity();
    Object.assign(result, workflowIdentity);
    const catalogPath = assertCatalogPath(core.getInput('catalog-path') || '.azd/catalog.json');
    result.catalogPath = catalogPath;
    const token = core.getInput('github-token', {required: true});
    core.setSecret(token);
    const payload = readEventPayload();
    const context = resolveEventContext(payload, process.env.GITHUB_EVENT_NAME, process.env);
    Object.assign(result, context);
    const catalog = await fetchCatalog({
      apiUrl: process.env.GITHUB_API_URL || 'https://api.github.com',
      token,
      context,
      catalogPath,
    });

    let validation;
    if (catalog.missing) {
      validation = {
        valid: false,
        errors: [{code: 'catalogMissing', message: `Enrolled catalog file is missing: ${catalogPath}`, path: '', line: 1, column: 1}],
        notices: [],
      };
    }
    else {
      validation = parseAndValidateCatalog(catalog.text, readJson(schemaPath));
    }
    validation.errors = boundIssues(validation.errors);
    validation.notices = boundIssues(validation.notices);

    Object.assign(result, {
      catalogBlobSha: catalog.blobSha || null,
      outcome: validation.valid ? 'valid' : 'invalid',
      errors: validation.errors,
      notices: validation.notices,
      durationMs: Date.now() - started,
    });

    core.setOutput('result-json', JSON.stringify(result));
    await writeSummary(result);
    if (!validation.valid) {
      annotateIssues(catalogPath, validation.errors);
      core.setFailed(`Catalog validation failed with ${validation.errors.length} error(s).`);
    }
  }
  catch (error) {
    result.outcome = 'operational_error';
    result.errors = [{code: 'operationalError', message: error.message}];
    result.durationMs = Date.now() - started;
    core.setOutput('result-json', JSON.stringify(result));
    core.setFailed(`Catalog validator operational error: ${error.message}`);
  }
}

run();
