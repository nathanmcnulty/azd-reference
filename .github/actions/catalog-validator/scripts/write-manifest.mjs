import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const actionRoot = path.resolve(scriptDirectory, '..');
const packageData = JSON.parse(await readFile(path.join(actionRoot, 'package.json'), 'utf8'));
const schemaPath = 'schema/catalog-metadata.schema.json';
const validatorPath = 'dist/index.js';

async function sha256(relativePath) {
  return createHash('sha256').update(await readFile(path.join(actionRoot, relativePath))).digest('hex');
}

const manifest = {
  contractVersion: '1.0',
  schemaVersion: '1.0.0',
  schemaPath,
  schemaSha256: await sha256(schemaPath),
  validatorVersion: packageData.version,
  validatorPath,
  validatorSha256: await sha256(validatorPath),
};

await writeFile(
  path.join(actionRoot, 'catalog-validator.manifest.json'),
  `${JSON.stringify(manifest, null, 2)}\n`,
  'utf8',
);
