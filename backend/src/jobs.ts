import { q } from './db/pool.js';
import { clock, DAY, HOUR } from './lib/clock.js';
import { LIMITS } from './lib/rules.js';
import { closeDuePolls } from './modules/feed/polls.js';

// PRF-18: accounts deactivated more than 30 days ago are deleted for good.
export async function purgeDeletedAccounts() {
  const cutoff = new Date(clock.now().getTime() - LIMITS.deactivationWindowDays * DAY);
  await q('delete from memberships where user_id in (select id from users where deactivated_at <= $1)', [cutoff]);
  await q('delete from users where deactivated_at <= $1', [cutoff]);
}

export function startJobs() {
  setInterval(() => { purgeDeletedAccounts().catch(console.error); }, HOUR);
  setInterval(() => { closeDuePolls().catch(console.error); }, 60_000);
}
