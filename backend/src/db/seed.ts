// Demo data: one street (Maple Road) with a full committee, posts, a poll and proposals.
// Run after `npm run migrate`. Every account's password is Keys2026!
import { readFileSync } from 'node:fs';
import { buildApp } from '../app.js';
import { migrate } from './migrate.js';
import { one, pool } from './pool.js';

const PASSWORD = 'Keys2026!';
const IMG = new URL('../../../app/assets/images/', import.meta.url);
const A = { pledge: true, hasLeadership: false, qualified: 'I have lived here ten years and know most neighbours', aim: 'Cleaner, safer streets and more events' };

await migrate();
if (await one(`select 1 from users where email = 'amy@keys.test'`)) {
  console.log('Demo data is already there. Log in as amy@keys.test /', PASSWORD);
  process.exit(0);
}
const app = await buildApp();

async function call(method: string, url: string, token?: string, body?: unknown) {
  const r = await app.inject({ method: method as any, url, payload: body as any, headers: token ? { authorization: `Bearer ${token}` } : {} });
  const json = JSON.parse(r.body || '{}');
  if (r.statusCode >= 400) throw new Error(`${method} ${url}: ${r.body}`);
  return json;
}
async function upload(token: string, file: string, kind = 'photo') {
  const b = '----seed' + Math.random().toString(16).slice(2);
  const mime = file.endsWith('.jpg') ? 'image/jpeg' : 'image/png';
  const payload = Buffer.concat([
    Buffer.from(`--${b}\r\nContent-Disposition: form-data; name="file"; filename="${file}"\r\nContent-Type: ${mime}\r\n\r\n`),
    readFileSync(new URL(file, IMG)),
    Buffer.from(`\r\n--${b}--\r\n`),
  ]);
  const r = await app.inject({ method: 'POST', url: `/media?kind=${kind}`, payload, headers: { authorization: `Bearer ${token}`, 'content-type': `multipart/form-data; boundary=${b}` } });
  return JSON.parse(r.body).id as string;
}
async function resident(email: string, address: string, first: string, last: string, photo: string, opts: { pioneer?: boolean; verified?: boolean } = {}) {
  await call('POST', '/auth/email/start', undefined, { email });
  const code = (await one<{ code: string }>(`select data->>'code' as code from email_outbox where to_email = $1 order by id desc limit 1`, [email]))!.code;
  const { ticket } = await call('POST', '/auth/email/verify', undefined, { email, code });
  const { token } = await call('POST', '/auth/signup', undefined, { ticket, firstName: first, lastName: last, password: PASSWORD, confirmPassword: PASSWORD });
  const s = await call('GET', `/addresses/autocomplete?q=${encodeURIComponent(address)}`, token);
  const m = await call('POST', '/onboarding/address', token, { placeId: s.suggestions[0].placeId });
  if (opts.pioneer) await call('POST', '/onboarding/street', token);
  else await call('POST', '/onboarding/join', token, { communityId: m.match.communities[0].id });
  await call('POST', '/onboarding/home-type', token, { type: 'house' });
  await call('POST', '/onboarding/profile', token, { photoMediaId: await upload(token, photo), safetyAccepted: true });
  if (opts.verified !== false) await call('POST', '/verification/check', token, { method: 'card', paymentMethodId: 'pm_mock_pass_visa_4242' });
  await call('POST', '/onboarding/welcome-prompt/done', token);
  await call('POST', '/learning/done', token, { outcome: 'skipped' });
  return { token, id: (await call('GET', '/me', token)).id as string };
}

const amy = await resident('amy@keys.test', '1 Maple Road', 'Amy', 'Duncan', 'choose_resident.png', { pioneer: true });
await call('POST', '/board', amy.token, { ...A, role: 'Chair' });
const roles: [string, string, string, string][] = [
  ['ashley', 'Ashley', 'White', 'Vice Chair'], ['eric', 'Eric', 'Pires', 'Treasurer'], ['brianna', 'Brianna', 'Roy', 'Secretary'],
  ['ajani', 'Ajani', 'Kimathi', 'Projects Lead'], ['tobias', 'Tobias', 'Jurgen', 'Clubs Lead'], ['nadine', 'Nadine', 'Sahs', 'Events Lead'],
  ['omari', 'Omari', 'Norris', 'Communications Lead'],
];
const photos = ['choose_vendor.png', 'invite_neighbours.png', 'community_street.png', 'community_building.png', 'community_development.png', 'home_house.png', 'pioneer_star.png'];
const team: Record<string, { token: string; id: string }> = {};
for (const [i, [key, first, last, role]] of roles.entries()) {
  team[key] = await resident(`${key}@keys.test`, `${i + 2} Maple Road`, first, last, photos[i]);
  await call('POST', '/board/join', team[key].token, { ...A, role });
}
const ben = await resident('ben@keys.test', '20 Maple Road', 'Ben', 'Ade', 'community_live_street.png', { verified: false });
const paula = await resident('paula@keys.test', '21 Maple Road', 'Paula', 'Harris', 'verify_identification.png');

await call('POST', '/posts', team.ashley.token, {
  text: 'Hey everyone, what is your go-to spot nearby for coffee? Looking for good local gems and somewhere to work from on Fridays.',
  photoIds: [await upload(team.ashley.token, 'carousel_1.jpg'), await upload(team.ashley.token, 'carousel_2.jpg'), await upload(team.ashley.token, 'carousel_3.jpg')],
});
const thanks = (await call('POST', '/posts', ben.token, { text: 'Thanks @Ashley White for organising the street clean up!', mentionIds: [team.ashley.id] })).post;
const c = (await call('POST', `/posts/${thanks.id}/comments`, amy.token, { text: 'Great job everyone' })).comment;
await call('POST', `/posts/${thanks.id}/comments`, team.ashley.token, { text: 'Happy to help again next month', parentId: c.id });
await call('POST', `/posts/${thanks.id}/like`, amy.token);
const poll = (await call('POST', '/polls', amy.token, {
  question: 'Which project would improve Maple Road most?',
  promise: 'Your votes decide which project the committee takes forward first.',
  options: [{ text: 'Community e-bikes' }, { text: 'Greener garden' }, { text: 'Recycling bins' }],
  duration: '7d',
})).post;
await call('POST', `/polls/${poll.id}/vote`, team.eric.token, { optionIds: [poll.poll.options[0].id] });

const manage = await call('GET', '/board/manage', amy.token);
await call('POST', `/board/seats/${manage.championSeats[0].id}/activate`, amy.token);
await call('POST', '/board/join', paula.token, { ...A, seatId: manage.championSeats[0].id });
await call('POST', '/board/proposals', team.ashley.token, { type: 'remove', subjectId: team.nadine.id, reason: 'Nadine has not joined any committee activity for months.' });

// Updates (UPD) with an update group chat, and chats (CHT).
const closure = (await call('POST', '/updates', amy.token, {
  title: 'Temporary road closure for maintenance',
  details: 'Attention residents! The council will be carrying out road maintenance on Maple Road. Expect temporary lane closures and noise during this period. Please plan accordingly. We appreciate your patience!',
  imageIds: [await upload(amy.token, 'carousel_4.jpg'), await upload(amy.token, 'community_live_street.png')],
  groupChat: true,
})).update;
await call('POST', `/updates/${closure.id}/additional`, team.eric.token, { text: 'Update: works now finish on Friday at 6pm.' });
await call('POST', `/chats/${closure.chatId}/messages`, team.eric.token, { text: 'Will bin collection still happen this week?' });
await call('POST', '/updates', team.omari.token, { title: 'Water supply interruption on Thursday', details: 'Due to pipe repairs, water will be off from midnight until 6am. Kindly store enough water.' });
const direct = (await call('POST', '/chats/direct', team.ashley.token, { userId: amy.id })).chat;
await call('POST', `/chats/${direct.id}/messages`, team.ashley.token, { text: 'Hey Amy! Are we still on for the committee meeting?' });
await call('POST', `/chats/${direct.id}/messages`, amy.token, { text: 'Yes, 7pm at the community hall.' });
await call('POST', `/chats/${direct.id}/messages`, team.ashley.token, { text: 'Perfect, see you there 👍' });
await call('POST', '/chats/direct', ben.token, { userId: amy.id }).then((r) => call('POST', `/chats/${r.chat.id}/messages`, ben.token, { text: 'Hi Amy, could I borrow your ladder this weekend?' }));
const group = (await call('POST', '/chats/groups', amy.token, { name: 'Maple Road Gardeners', memberIds: [team.ashley.id, team.brianna.id, paula.id] })).chat;
await call('PATCH', `/chats/${group.id}`, amy.token, { description: 'Swap seeds, plan the greener garden and share tips.' });
await call('POST', `/chats/${group.id}/messages`, team.brianna.token, { text: 'Morning everyone! The tomatoes are finally ripe 🍅' });
await call('POST', `/chats/${group.id}/messages`, paula.token, { text: 'Lovely! Anyone have spare compost?' });

await app.close();
await pool.end();
console.log(`
Demo data ready (password for every account: ${PASSWORD})
  amy@keys.test      Chair, verified        - sees Proposals, can vote, manage seats, create polls
  ashley@keys.test   Vice Chair             - other committee roles: eric, brianna, ajani, tobias, nadine, omari
  ben@keys.test      resident, unverified   - try voting on the poll or joining the board to see the verify sheet
  paula@keys.test    applied to be a Champion
  Updates and chats: amy has two updates (one with a group chat), a direct chat with ashley,
  a message request from ben and the "Maple Road Gardeners" group.
To try sign-up from scratch use any new email; codes are printed in the email_outbox table (mock email).
Test addresses: e.g. "5 Cedar Close" (no community yet), "4 Elm Street" (connected streets), "3 Oak Avenue".
`);
