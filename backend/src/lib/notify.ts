import { one, q } from '../db/pool.js';
import { clock } from './clock.js';
import { areBlocked, isMuted } from './people.js';

/** Notification types and the settings toggle that controls each. */
export const NOTIFICATION_TOGGLES: Record<string, string> = {
  post_like: 'likes',
  comment_like: 'likes',
  post_comment: 'comments',
  comment_reply: 'comments',
  mention: 'mentions',
  poll_closed: 'polls',
  proposal_created: 'committee',
  proposal_reminder: 'committee',
  proposal_result: 'committee',
  board_announcement: 'committee',
  tier_up: 'committee',
};

/** In-app toggles shown in Settings > Notification (Phase 1 features only). */
export const PREF_DEFAULTS: Record<string, boolean> = {
  likes: true,
  comments: true,
  mentions: true,
  polls: true,
  updates: true,
  committee: true,
  chat: true,
  events: true,
  clubs: true,
  // PRF-14.2: marketing email is opt-in (PECR), off by default.
  newsletter: false,
};

export async function prefs(userId: string) {
  const rows = await q<{ key: string; enabled: boolean }>('select key, enabled from notification_prefs where user_id = $1', [userId]);
  const out = { ...PREF_DEFAULTS };
  for (const r of rows) if (r.key in out) out[r.key] = r.enabled;
  return out;
}

/**
 * Stores an in-app notification and queues a push (Firebase in production;
 * recorded only for now). Never for your own actions, from someone you
 * muted or blocked (either way), or when the toggle is off (FED-19).
 */
export async function notify(userId: string, type: string, actorId: string | null, item: { type: string; id: string }, data: Record<string, unknown> = {}) {
  if (actorId && actorId === userId) return false;
  if (actorId && (await areBlocked(userId, actorId))) return false;
  if (actorId && (await isMuted(userId, actorId))) return false;
  const toggle = NOTIFICATION_TOGGLES[type];
  if (toggle && !(await prefs(userId))[toggle]) return false;
  const live = await one('select 1 from users where id = $1 and deactivated_at is null', [userId]);
  if (!live) return false;
  await q(
    'insert into notifications(user_id, type, actor_id, item_type, item_id, data, created_at) values ($1,$2,$3,$4,$5,$6,$7)',
    [userId, type, actorId, item.type, item.id, data, clock.now()],
  );
  return true;
}
