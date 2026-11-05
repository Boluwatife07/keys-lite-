import type { FastifyInstance } from 'fastify';
import { randomInt, randomUUID } from 'node:crypto';
import { z } from 'zod';
import { one, q } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { clock, DAY } from '../../lib/clock.js';
import { encrypt } from '../../lib/crypto.js';
import { badRequest, conflict, tooMany } from '../../lib/errors.js';
import { LIMITS } from '../../lib/rules.js';
import { addressCheck } from '../../services/addressCheck.js';
import { putObject } from '../../services/storage.js';
import { validateUpload } from '../media/validate.js';

const ACCEPTED_DOCS = ['Utility bill', 'Bank statement', 'Council tax letter', 'Tenancy agreement', 'Government-issued letter'];

async function home(userId: string) {
  const a = await one<{ line1: string; postcode: string; town: string; formatted: string }>(
    `select a.line1, a.postcode, a.town, a.formatted from users u join addresses a on a.id = u.home_address_id where u.id = $1`, [userId],
  );
  if (!a) throw badRequest('ADDRESS_REQUIRED', 'Please add your home address first.');
  return a;
}

function caseView(rc: any) {
  return {
    ref: rc.ref,
    status: rc.status,
    documentName: rc.document_name,
    submittedAt: rc.created_at,
    estimate: 'Est. 1-2 business days',
  };
}

export async function verificationRoutes(app: FastifyInstance) {
  // AVW-05.4: under review shows instead of the method screen.
  app.get('/verification', async (req) => {
    const u = requireUser(req);
    const st = (await one<{ s: string }>('select verification_status as s from users where id = $1', [u.id]))!.s;
    const rc = await one<any>(`select * from review_cases where user_id = $1 order by created_at desc limit 1`, [u.id]);
    const last = await one<any>(
      `select method, brand, last4, result from verification_attempts where user_id = $1 and result in ('pass','fail') order by created_at desc limit 1`, [u.id],
    );
    const a = await one<{ formatted: string }>(`select a.formatted from users u join addresses a on a.id = u.home_address_id where u.id = $1`, [u.id]);
    return {
      status: st,
      homeAddress: a?.formatted ?? null,
      reviewCase: st === 'under_review' && rc ? caseView(rc) : null,
      lastAttempt: last ?? null,
      acceptedDocuments: ACCEPTED_DOCS,
    };
  });

  // AVW-02 / AVW-03: zero-amount Stripe address check.
  app.post('/verification/check', async (req) => {
    const u = requireUser(req);
    const body = z.object({ method: z.enum(['card', 'apple_pay', 'google_pay']), paymentMethodId: z.string().min(1) }).parse(req.body);
    const st = (await one<{ s: string }>('select verification_status as s from users where id = $1', [u.id]))!.s;
    if (st === 'verified') throw conflict('ALREADY_VERIFIED', 'Your account is already verified.');
    if (st === 'under_review') throw conflict('UNDER_REVIEW', 'Your documents are under review.');
    const recent = await one<{ n: number }>(
      `select count(*)::int as n from verification_attempts where user_id = $1 and result in ('pass','fail','error') and created_at > $2`,
      [u.id, new Date(clock.now().getTime() - DAY)],
    );
    if ((recent?.n ?? 0) >= LIMITS.verifyAttemptsPerDay) throw tooMany('You have reached the number of attempts for today. Please try again tomorrow or contest this decision.');
    const h = await home(u.id);
    let result;
    try {
      result = await addressCheck.check({ method: body.method, paymentMethodId: body.paymentMethodId, home: h });
    } catch (e) {
      await q('insert into verification_attempts(user_id, method, result) values ($1,$2,$3)', [u.id, body.method, 'error']);
      throw e;
    }
    await q(
      'insert into verification_attempts(user_id, method, brand, last4, result, created_at) values ($1,$2,$3,$4,$5,$6)',
      [u.id, body.method, result.brand, result.last4, result.result, clock.now()],
    );
    if (result.result === 'pass') await q(`update users set verification_status = 'verified' where id = $1`, [u.id]);
    return { result: result.result, method: body.method, brand: result.brand, last4: result.last4, homeAddress: h.formatted };
  });

  // AVW-03.2: wallet sheet cancelled. Logged for the audit trail, no error.
  app.post('/verification/cancelled', async (req) => {
    const u = requireUser(req);
    const body = z.object({ method: z.enum(['card', 'apple_pay', 'google_pay']) }).parse(req.body);
    await q('insert into verification_attempts(user_id, method, result) values ($1,$2,$3)', [u.id, body.method, 'cancelled']);
    return { ok: true };
  });

  // AVW-05: contest with a supporting document. Encrypted at rest, admins only.
  app.post('/verification/contest', async (req) => {
    const u = requireUser(req);
    const st = (await one<{ s: string }>('select verification_status as s from users where id = $1', [u.id]))!.s;
    if (st !== 'unverified') throw conflict(st === 'verified' ? 'ALREADY_VERIFIED' : 'UNDER_REVIEW', st === 'verified' ? 'Your account is already verified.' : 'Your documents are under review.');
    const failed = await one(`select 1 from verification_attempts where user_id = $1 and result = 'fail'`, [u.id]);
    if (!failed) throw badRequest('NOTHING_TO_CONTEST', 'Try verifying with your card first.');
    const file = await req.file();
    if (!file) throw badRequest('FILE_REQUIRED', 'Upload a supporting document.');
    const buf = await file.toBuffer();
    const { mime } = await validateUpload('verificationDoc', buf, file.mimetype, file.filename);
    const key = `verification/${randomUUID()}.bin`;
    await putObject(key, encrypt(buf));
    const now = clock.now();
    const ref = `KYS-${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}-${String(randomInt(0, 10000)).padStart(4, '0')}`;
    const rc = await one<any>(
      `insert into review_cases(ref, user_id, document_key, document_name, document_mime, document_size, created_at)
       values ($1,$2,$3,$4,$5,$6,$7) returning *`,
      [ref, u.id, key, file.filename, mime, buf.length, now],
    );
    await q(`update users set verification_status = 'under_review' where id = $1`, [u.id]);
    return { status: 'under_review', reviewCase: caseView(rc) };
  });
}
