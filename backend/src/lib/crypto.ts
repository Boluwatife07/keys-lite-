import { createCipheriv, createDecipheriv, createHash, randomBytes, randomInt } from 'node:crypto';
import { config } from '../config.js';

export const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('base64url');
export const sixDigitCode = () => String(randomInt(0, 1_000_000)).padStart(6, '0');

// Community codes: 6 characters, no look-alike letters.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const communityCode = () =>
  Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(0, CODE_ALPHABET.length)]).join('');

// AES-256-GCM for verification documents at rest.
export function encrypt(buf: Buffer): Buffer {
  const key = Buffer.from(config.documentKeyHex, 'hex');
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const body = Buffer.concat([cipher.update(buf), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]);
}
export function decrypt(buf: Buffer): Buffer {
  const key = Buffer.from(config.documentKeyHex, 'hex');
  const decipher = createDecipheriv('aes-256-gcm', key, buf.subarray(0, 12));
  decipher.setAuthTag(buf.subarray(12, 28));
  return Buffer.concat([decipher.update(buf.subarray(28)), decipher.final()]);
}
