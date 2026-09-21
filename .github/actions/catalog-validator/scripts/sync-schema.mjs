import {copyFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const actionRoot = path.resolve(scriptDirectory, '..');
const repositoryRoot = path.resolve(actionRoot, '..', '..', '..');
const source = path.join(repositoryRoot, 'schemas', 'catalog-metadata.schema.json');
const targetDirectory = path.join(actionRoot, 'schema');
const target = path.join(targetDirectory, 'catalog-metadata.schema.json');

await mkdir(targetDirectory, {recursive: true});
await copyFile(source, target);
