import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { q } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { badRequest } from '../../lib/errors.js';
import { REPORT_ITEM_TYPES, REPORT_REASONS } from '../../lib/rules.js';

// XFR-03 / BE-90.4: one report form everywhere, into one moderation queue.
// The reported person is never told.
export async function reportRoutes(app: FastifyInstance) {
  app.get('/reports/reasons', async () => ({ reasons: REPORT_REASONS, otherNeedsText: true }));

  app.post('/reports', async (req) => {
    const u = requireUser(req);
    const body = z.object({
      itemType: z.enum(REPORT_ITEM_TYPES),
      itemId: z.string().min(1),
      reason: z.enum(REPORT_REASONS),
      text: z.string().trim().max(500).optional(),
    }).parse(req.body);
    if (body.reason === 'Other' && !body.text) throw badRequest('REPORT_TEXT_REQUIRED', 'Tell us what is wrong', { field: 'text' });
    await q(
      'insert into reports(item_type, item_id, reporter_id, reason, text) values ($1,$2,$3,$4,$5)',
      [body.itemType, body.itemId, u.id, body.reason, body.text ?? null],
    );
    return { ok: true, message: 'Thanks for letting us know. Our team will review this report.' };
  });
}
