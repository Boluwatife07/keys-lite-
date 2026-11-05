import { execFile } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { badRequest } from '../../lib/errors.js';
import { MEDIA } from '../../lib/rules.js';

const run = promisify(execFile);

// Detect the real type from the file's first bytes; never trust the name.
export function sniff(buf: Buffer): string | undefined {
  const h = buf.subarray(0, 12);
  if (h[0] === 0xff && h[1] === 0xd8 && h[2] === 0xff) return 'image/jpeg';
  if (h.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (h.subarray(0, 5).toString() === '%PDF-') return 'application/pdf';
  if (h.subarray(4, 8).toString() === 'ftyp') return h.subarray(8, 10).toString() === 'qt' ? 'video/quicktime' : 'video/mp4';
  if (h[0] === 0x50 && h[1] === 0x4b) return 'application/zip'; // docx/xlsx/pptx
  if (h[0] === 0xd0 && h[1] === 0xcf) return 'application/x-ole'; // doc/xls/ppt
  return undefined;
}

export async function videoSeconds(buf: Buffer): Promise<number> {
  const dir = await mkdtemp(join(tmpdir(), 'keys-'));
  const f = join(dir, 'v');
  try {
    await writeFile(f, buf);
    const { stdout } = await run('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]);
    const n = Number(stdout.trim());
    if (!Number.isFinite(n)) throw new Error('no duration');
    return n;
  } catch {
    throw badRequest('VIDEO_UNREADABLE', 'We could not read this video. Please choose a different file.');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

export type Kind = 'photo' | 'video' | 'document' | 'audio' | 'verificationDoc';

function sniffAudio(buf: Buffer): string | undefined {
  const h = buf.subarray(0, 12);
  if (h.subarray(4, 8).toString() === 'ftyp') return 'audio/mp4';
  if (h.subarray(0, 3).toString() === 'ID3' || (h[0] === 0xff && (h[1] & 0xe0) === 0xe0)) return 'audio/mpeg';
  if (h.subarray(0, 4).toString() === 'OggS') return 'audio/ogg';
  if (h[0] === 0x1a && h[1] === 0x45 && h[2] === 0xdf && h[3] === 0xa3) return 'audio/webm';
  if (h.subarray(0, 4).toString() === 'RIFF' && h.subarray(8, 12).toString() === 'WAVE') return 'audio/wav';
  return undefined;
}

// XFR-01.4: the server re-checks type, size and video length.
export async function validateUpload(kind: Kind, buf: Buffer, declaredMime: string, filename: string) {
  const rule = MEDIA[kind];
  const sniffed = sniff(buf);
  let mime: string;
  if (kind === 'document') {
    const okByName = /\.(pdf|docx?|xlsx?|pptx?|txt)$/i.test(filename);
    const okBytes = sniffed === 'application/pdf' || sniffed === 'application/zip' || sniffed === 'application/x-ole' || declaredMime === 'text/plain';
    if (!okByName || !okBytes) throw badRequest('FILE_TYPE', 'This file type is not supported.');
    mime = sniffed === 'application/pdf' ? 'application/pdf' : declaredMime;
  } else if (kind === 'audio') {
    const a = sniffAudio(buf);
    if (!a) throw badRequest('FILE_TYPE', 'This voice note could not be read.');
    mime = a;
  } else {
    if (!sniffed || !(rule.mimes as readonly string[]).includes(sniffed)) {
      throw badRequest('FILE_TYPE', kind === 'photo' ? 'Please choose a JPG or PNG image.' : kind === 'video' ? 'Please choose an MP4 or MOV video.' : 'Please upload a PDF, JPG or PNG file.');
    }
    mime = sniffed;
  }
  if (buf.length > rule.maxBytes) throw badRequest('FILE_TOO_LARGE', rule.tooLarge);
  let duration: number | undefined;
  if (kind === 'video') {
    duration = await videoSeconds(buf);
    if (duration > MEDIA.video.maxSeconds + 0.5) throw badRequest('VIDEO_TOO_LONG', MEDIA.video.tooLong);
  }
  if (kind === 'audio') {
    duration = await videoSeconds(buf);
    if (duration > MEDIA.audio.maxSeconds) throw badRequest('AUDIO_TOO_LONG', 'Voice notes can be up to 10 minutes long.');
  }
  return { mime, duration };
}
