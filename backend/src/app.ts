import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import multipart from '@fastify/multipart';
import { ZodError } from 'zod';
import { AppError } from './lib/errors.js';
import { loadUser } from './lib/auth.js';
import { MB } from './lib/rules.js';
import { authRoutes } from './modules/auth/routes.js';
import { onboardingRoutes } from './modules/onboarding/routes.js';
import { verificationRoutes } from './modules/verification/routes.js';
import { mediaRoutes } from './modules/media/routes.js';
import { reportRoutes } from './modules/reports/routes.js';
import { linkRoutes } from './modules/links/routes.js';
import { meRoutes } from './modules/me/routes.js';
import { profileRoutes } from './modules/profile/routes.js';
import { feedRoutes } from './modules/feed/routes.js';
import { pollRoutes } from './modules/feed/polls.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: process.env.NODE_ENV === 'test' ? false : { level: 'info' }, bodyLimit: 2 * MB });
  await app.register(cors, { origin: true });
  await app.register(multipart, { limits: { fileSize: 101 * MB, files: 1 } });
  // Clients send "content-type: application/json" on DELETE and bodiless POSTs; treat empty as {}.
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (_req, body, done) => {
    const text = String(body ?? '').trim();
    if (!text) return done(null, {});
    try {
      done(null, JSON.parse(text));
    } catch {
      done(Object.assign(new Error('Invalid JSON body'), { statusCode: 400 }), undefined);
    }
  });

  app.addHook('preHandler', async (req) => {
    req.authUser = await loadUser(req);
  });

  app.setErrorHandler((err: any, _req, reply) => {
    if (err instanceof AppError) {
      return reply.status(err.status).send({ error: { code: err.code, message: err.message, ...err.details } });
    }
    if (err instanceof ZodError) {
      const first = err.issues[0];
      return reply.status(400).send({ error: { code: 'VALIDATION', message: first?.message ?? 'Invalid input', field: first?.path.join('.') } });
    }
    if ((err as any).code === 'FST_REQ_FILE_TOO_LARGE') {
      return reply.status(413).send({ error: { code: 'FILE_TOO_LARGE', message: 'The file you selected is too large.' } });
    }
    if ((err as any).statusCode && (err as any).statusCode < 500) {
      return reply.status((err as any).statusCode).send({ error: { code: 'BAD_REQUEST', message: err.message } });
    }
    app.log.error(err);
    return reply.status(500).send({ error: { code: 'SERVER_ERROR', message: 'Something went wrong. Please try again.' } });
  });

  app.get('/health', async () => ({ ok: true }));
  await app.register(authRoutes);
  await app.register(meRoutes);
  await app.register(onboardingRoutes);
  await app.register(verificationRoutes);
  await app.register(mediaRoutes);
  await app.register(reportRoutes);
  await app.register(linkRoutes);
  await app.register(profileRoutes);
  await app.register(feedRoutes);
  await app.register(pollRoutes);
  return app;
}
