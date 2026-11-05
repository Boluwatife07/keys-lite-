import { one, q, tx } from '../../db/pool.js';
import { clock } from '../../lib/clock.js';
import { sendEmail } from '../../services/email.js';

// Manual review outcome (AVW-06). Called by the Admin Panel once it exists;
// no HTTP route in Phase 1 (decision: proceed without Admin Panel review).
export async function decideReviewCase(caseId: string, approve: boolean, adminId: string) {
  const res = await tx(async (c) => {
    const rc = await one<any>(
      `update review_cases set status = $2, decided_by = $3, decided_at = $4 where id = $1 and status = 'under_review' returning *`,
      [caseId, approve ? 'approved' : 'rejected', adminId, clock.now()], c,
    );
    if (!rc) return undefined;
    await q('update users set verification_status = $2 where id = $1', [rc.user_id, approve ? 'verified' : 'unverified'], c);
    return rc;
  });
  if (!res) return false;
  const u = (await one<{ email: string; first_name: string }>('select email, first_name from users where id = $1', [res.user_id]))!;
  await sendEmail(u.email, approve ? 'verification_approved' : 'verification_rejected', { firstName: u.first_name, ref: res.ref });
  return true;
}
