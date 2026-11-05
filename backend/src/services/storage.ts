import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, normalize } from 'node:path';
import { config } from '../config.js';

// Local disk storage. Replace with object storage + CDN for production.
function safePath(key: string) {
  const p = normalize(join(config.storageDir, key));
  if (!p.startsWith(normalize(config.storageDir))) throw new Error('bad storage key');
  return p;
}
export async function putObject(key: string, data: Buffer) {
  const p = safePath(key);
  await mkdir(dirname(p), { recursive: true });
  await writeFile(p, data);
}
export async function getObject(key: string) {
  return readFile(safePath(key));
}
export const publicUrl = (key: string) => `${config.publicMediaBase}/${key}`;
