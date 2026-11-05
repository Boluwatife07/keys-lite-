import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { one } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { badRequest, notFound } from '../../lib/errors.js';
import { getObject, publicUrl, putObject } from '../../services/storage.js';
import { validateUpload } from './validate.js';

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'application/pdf': 'pdf', 'audio/mp4': 'm4a', 'audio/mpeg': 'mp3', 'audio/ogg': 'ogg', 'audio/webm': 'webm', 'audio/wav': 'wav', 'audio/aac': 'aac',
};

// BE-90.1: one upload endpoint for every feature.
export async function mediaRoutes(app: FastifyInstance) {
  app.post('/media', async (req) => {
    const u = requireUser(req);
    const { kind } = z.object({ kind: z.enum(['photo', 'video', 'document', 'audio']) }).parse(req.query);
    const file = await req.file();
    if (!file) throw badRequest('FILE_REQUIRED', 'Choose a file to upload.');
    const buf = await file.toBuffer();
    const { mime, duration } = await validateUpload(kind, buf, file.mimetype, file.filename);
    const id = randomUUID();
    const ext = EXT[mime] ?? (file.filename.split('.').pop() || 'bin');
    const key = `${kind}/${id}.${ext}`;
    await putObject(key, buf);
    const row = await one<any>(
      `insert into media(id, owner_id, kind, mime, size_bytes, duration_seconds, original_name, storage_key, url)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9) returning id, kind, mime, size_bytes, duration_seconds, original_name, url`,
      [id, u.id, kind, mime, buf.length, duration ?? null, file.filename, key, publicUrl(key)],
    );
    return { id: row.id, kind: row.kind, mime: row.mime, sizeBytes: row.size_bytes, durationSeconds: row.duration_seconds, name: row.original_name, url: row.url };
  });

  // Local-disk file serving. Production serves media from a CDN.
  app.get('/media/files/*', async (req, reply) => {
    const key = (req.params as any)['*'] as string;
    if (!/^(photo|video|document|audio)\/[0-9a-f-]+\.[a-z0-9]+$/.test(key)) throw notFound();
    const row = await one<{ mime: string }>('select mime from media where storage_key = $1', [key]);
    if (!row) throw notFound();
    return reply.type(row.mime).send(await getObject(key));
  });
}
