import type { FastifyInstance } from 'fastify';
import { one } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { seatOf } from '../../lib/people.js';

// What the app needs at launch to route the user (ONB-26 resume) and to
// decide which first-run prompts to show (ONB-25, LRN-01).
export async function meRoutes(app: FastifyInstance) {
  app.get('/me', async (req) => {
    const u = requireUser(req);
    const r = await one<any>(
      `select u.id, u.email, u.first_name, u.last_name, u.onboarding_step, u.verification_status, u.photo_url, u.bio,
              u.password_hash is not null as has_password, u.learning_done_at, u.welcome_prompt_done_at, u.created_at,
              a.line1, a.formatted, a.postcode, s.name as street_name,
              c.id as community_id, c.name as community_name, c.type as community_type, c.code as community_code,
              m.level, b.name as building_name
         from users u
         left join addresses a on a.id = u.home_address_id
         left join streets s on s.id = a.street_id
         left join memberships m on m.user_id = u.id
         left join communities c on c.id = m.community_id
         left join communities b on b.id = m.building_id
        where u.id = $1`,
      [u.id],
    );
    const done = r.onboarding_step === 'complete';
    const seat = await seatOf(u.id);
    return {
      id: r.id,
      email: r.email,
      firstName: r.first_name,
      lastName: r.last_name,
      onboardingStep: r.onboarding_step,
      verificationStatus: r.verification_status,
      photoUrl: r.photo_url,
      bio: r.bio,
      hasPassword: r.has_password,
      joinedAt: r.created_at,
      address: r.line1 ? { line1: r.line1, formatted: r.formatted, postcode: r.postcode, street: r.street_name } : null,
      community: r.community_id
        ? { id: r.community_id, name: r.community_name, type: r.community_type, code: r.community_code, level: r.level, building: r.building_name }
        : null,
      showWelcomePrompt: done && !r.welcome_prompt_done_at,
      showLearning: done && !r.learning_done_at,
      boardRole: seat?.role ?? null,
      isCommittee: !!seat && seat.kind !== 'champion',
    };
  });
}
