import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { call, joinStreet, me, PDF, pioneerStreet, PNG, seat, setup, teardown, upload } from './helpers.js';

let a: string; let b: string; let c: string; let d: string; let e: string; let f: string; let g: string;
let ids: Record<string, string> = {};
let voice: Buffer;

beforeAll(async () => {
  process.env.LINK_PREVIEW_ALLOW_PRIVATE = '1';
  await setup();
  a = (await pioneerStreet('a@keys.test', '1 Maple Road')).token;
  b = await joinStreet('b@keys.test', '2 Maple Road', 'Bea', 'Bee');
  c = await joinStreet('c@keys.test', '3 Maple Road', 'Cal', 'Cee');
  d = await joinStreet('d@keys.test', '4 Maple Road', 'Dee', 'Dee');
  e = await joinStreet('e@keys.test', '5 Maple Road', 'Eve', 'Eee');
  f = await joinStreet('f@keys.test', '6 Maple Road', 'Fay', 'Eff');
  g = await joinStreet('g@keys.test', '7 Maple Road', 'Gus', 'Gee');
  for (const [k, t] of Object.entries({ a, b, c, d, e, f, g })) ids[k] = (await me(t)).id;
  mkdirSync('.test-storage/tmp', { recursive: true });
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', '-c:a', 'aac', '.test-storage/tmp/v.m4a']);
  voice = readFileSync('.test-storage/tmp/v.m4a');
});
afterAll(teardown);

const direct = async (t: string, other: string) => (await call('POST', '/chats/direct', { token: t, body: { userId: other } })).body.chat.id as string;
const sendText = (t: string, chat: string, text: string) => call('POST', `/chats/${chat}/messages`, { token: t, body: { text } });
const msgs = async (t: string, chat: string) => (await call('GET', `/chats/${chat}/messages`, { token: t })).body.messages;

describe('CHT-03 / CHT-04 direct chats and the 2-message limit', () => {
  let ab: string;
  it('A can send 2 messages; B sees a request; replying lifts the limit; receipts only after accept', async () => {
    expect((await call('GET', '/chats/people', { token: a })).body.people.map((p: any) => p.firstName)).toEqual(['Bea', 'Cal', 'Dee', 'Eve', 'Fay', 'Gus']);
    ab = await direct(a, ids.b);
    expect(await direct(a, ids.b)).toBe(ab);
    expect((await sendText(a, ab, 'Hi Bea')).body.notice).toBe('Your message request has been sent');
    expect((await sendText(a, ab, 'Are you free?')).body.notice).toMatch(/2-message limit/);
    const third = await sendText(a, ab, 'Hello?');
    expect(third.body.error).toMatchObject({ code: 'REQUEST_LIMIT', message: "You've reached your 2-message limit. You'll be able to send more messages once this user replies you." });
    const list = (await call('GET', '/chats', { token: b })).body.chats;
    expect(list[0]).toMatchObject({ id: ab, isRequest: true, unread: 2, name: 'Amy Duncan' });
    const info = (await call('GET', `/chats/${ab}`, { token: b })).body;
    expect(info.request.prompt).toBe("Do you want to let Amy Duncan message you? If you accept, they will also be able to see when you've read their messages.");
    await call('POST', `/chats/${ab}/read`, { token: b });
    // Delivered but not "Seen" until accepted.
    expect((await msgs(a, ab)).map((m: any) => m.status)).toEqual(['delivered', 'delivered']);
    await sendText(b, ab, 'Hi! Yes');
    expect((await sendText(a, ab, 'Great')).status).toBe(200);
    await call('POST', `/chats/${ab}/read`, { token: b });
    expect((await msgs(a, ab)).filter((m: any) => m.isMine).map((m: any) => m.status)).toEqual(['seen', 'seen', 'seen']);
  });
  it('CHT-04.4 deleting a request removes it from the recipient only; the sender stays limited', async () => {
    const ac = await direct(a, ids.c);
    await sendText(a, ac, 'one'); await sendText(a, ac, 'two');
    await call('POST', `/chats/${ac}/request/delete`, { token: c });
    expect((await call('GET', '/chats', { token: c })).body.chats.some((x: any) => x.id === ac)).toBe(false);
    expect((await call('GET', '/chats', { token: a })).body.chats.some((x: any) => x.id === ac)).toBe(true);
    expect((await sendText(a, ac, 'three')).body.error.code).toBe('REQUEST_LIMIT');
  });
  it('CHT-05.5 a blocked person sees Sent; their messages never arrive; the blocker cannot send', async () => {
    const dE = await direct(d, ids.e);
    await sendText(e, dE, 'hello'); // e replies first -> e is not requester; accept happens
    await call('POST', `/users/${ids.e}/block`, { token: d });
    const s = await sendText(e, dE, 'are you there');
    expect(s.body.message.status).toBe('sent');
    expect((await msgs(d, dE)).map((m: any) => m.text)).toEqual(['hello']);
    expect((await sendText(d, dE, 'x')).body.error.message).toBe('You blocked this user. Tap to unblock.');
    expect((await call('GET', '/chats', { token: d })).body.chats.find((x: any) => x.id === dE).blockedByMe).toBe(true);
    await call('DELETE', `/users/${ids.e}/block`, { token: d });
  });
  it('CHT-05.1 text limit 5,000 and link previews', async () => {
    const ab = await direct(a, ids.b);
    expect((await sendText(a, ab, 'x'.repeat(5001))).body.error.code).toBe('TOO_LONG');
  });
});

describe('CHT-06 - CHT-08 media, voice, replies, reactions, delete, forward', () => {
  let ab: string;
  beforeAll(async () => { ab = await direct(a, ids.b); });
  it('photos, a document and a voice note; reply quotes "Voice message (m:ss)"', async () => {
    const p = (await upload('/media?kind=photo', a, { name: 'p.png', mime: 'image/png', data: PNG })).body.id;
    const photo = (await call('POST', `/chats/${ab}/messages`, { token: a, body: { mediaIds: [p] } })).body.message;
    expect(photo).toMatchObject({ kind: 'media', media: [expect.objectContaining({ kind: 'photo' })] });
    const doc = (await upload('/media?kind=document', a, { name: 'rota.pdf', mime: 'application/pdf', data: PDF })).body.id;
    expect((await call('POST', `/chats/${ab}/messages`, { token: a, body: { documentId: doc, mediaIds: [p] } })).body.error.code).toBe('ONE_KIND');
    expect((await call('POST', `/chats/${ab}/messages`, { token: a, body: { documentId: doc } })).body.message.document.name).toBe('rota.pdf');
    const v = await upload('/media?kind=audio', b, { name: 'v.m4a', mime: 'audio/mp4', data: voice });
    const vm = (await call('POST', `/chats/${ab}/messages`, { token: b, body: { voiceId: v.body.id } })).body.message;
    expect(vm.voice.label).toBe('0:02');
    const rep = (await call('POST', `/chats/${ab}/messages`, { token: a, body: { text: 'Lovely', replyToId: vm.id } })).body.message;
    expect(rep.replyTo).toMatchObject({ sender: 'Bea Bee', preview: 'Voice message (0:02)' });
  });
  it('CHT-08.6 one reaction each; same emoji removes, another replaces', async () => {
    const m = (await sendText(a, ab, 'React to me')).body.message;
    await call('POST', `/messages/${m.id}/react`, { token: b, body: { emoji: '👍' } });
    await call('POST', `/messages/${m.id}/react`, { token: b, body: { emoji: '❤️' } });
    let v = (await msgs(a, ab)).find((x: any) => x.id === m.id);
    expect(v.reactions).toEqual([{ emoji: '❤️', count: 1, mine: false }]);
    await call('POST', `/messages/${m.id}/react`, { token: b, body: { emoji: '❤️' } });
    v = (await msgs(a, ab)).find((x: any) => x.id === m.id);
    expect(v.reactions).toEqual([]);
  });
  it('CHT-08.5 delete for all (own only) and for me', async () => {
    const m = (await sendText(a, ab, 'oops')).body.message;
    expect((await call('DELETE', `/messages/${m.id}?scope=all`, { token: b })).body.error.code).toBe('NOT_SENDER');
    await call('DELETE', `/messages/${m.id}?scope=all`, { token: a });
    expect((await msgs(b, ab)).find((x: any) => x.id === m.id)).toMatchObject({ deleted: true, text: 'This message was deleted' });
    const n = (await sendText(a, ab, 'just for me')).body.message;
    await call('DELETE', `/messages/${n.id}?scope=me`, { token: b });
    expect((await msgs(b, ab)).some((x: any) => x.id === n.id)).toBe(false);
    expect((await msgs(a, ab)).some((x: any) => x.id === n.id)).toBe(true);
  });
  it('CHT-08.4 forward to up to 5, marked Forwarded, with an optional note', async () => {
    const m = (await sendText(a, ab, 'Bin day moved to Wednesday')).body.message;
    expect((await call('POST', '/messages/forward', { token: a, body: { messageIds: [m.id], userIds: [ids.c, ids.d, ids.e, ids.f, ids.g, ids.b] } })).body.error.code).toBe('TOO_MANY');
    const r = await call('POST', '/messages/forward', { token: a, body: { messageIds: [m.id], userIds: [ids.d], note: 'FYI' } });
    expect(r.body.ok).toBe(true);
    const ad = await direct(a, ids.d);
    const got = await msgs(d, ad);
    expect(got.map((x: any) => [x.text, x.forwarded])).toEqual([['Bin day moved to Wednesday', true], ['FYI', false]]);
  });
  it('CHT-09 search: global with filters and in-chat', async () => {
    const s = (await call('GET', '/chats/search?q=wednesday', { token: a })).body;
    expect(s.messages.length).toBeGreaterThan(0);
    expect((await call('GET', '/chats/search?type=documents', { token: a })).body.messages[0].document.name).toBe('rota.pdf');
    expect((await call('GET', '/chats/search?q=Bea', { token: a })).body.chats[0].name).toBe('Bea Bee');
    expect((await call('GET', `/chats/${ab}/search?q=lovely`, { token: b })).body.matches).toHaveLength(1);
    expect((await call('GET', '/chats/search?q=nothingmatches', { token: a })).body).toEqual({ chats: [], messages: [] });
  });
  it('CHT-18 shared media and documents by month', async () => {
    const r = (await call('GET', `/chats/${ab}/shared?tab=documents`, { token: b })).body;
    expect(r.groups[0].items[0].document.name).toBe('rota.pdf');
    expect(r.groups[0].label).toMatch(/^[A-Z][a-z]+ \d{4}$/);
  });
});

describe('CHT-02 / CHT-10 chat controls', () => {
  it('pin max 3, mute, delete for me (comes back on a new message), clear', async () => {
    const chats = [await direct(a, ids.b), await direct(a, ids.c), await direct(a, ids.d), await direct(a, ids.e)];
    for (const x of chats.slice(0, 3)) await call('POST', `/chats/${x}/pin`, { token: a });
    expect((await call('POST', `/chats/${chats[3]}/pin`, { token: a })).body.error.message).toBe('You can only pin 3 chats');
    const list = (await call('GET', '/chats', { token: a })).body.chats;
    expect(list.slice(0, 3).every((x: any) => x.pinned)).toBe(true);
    await call('PUT', `/chats/${chats[0]}/mute`, { token: a, body: { duration: '24h' } });
    expect((await call('GET', '/chats', { token: a })).body.chats.find((x: any) => x.id === chats[0]).muted).toBe(true);
    expect((await call('POST', `/chats/${chats[0]}/hide`, { token: b })).body.message).toBe('Chat deleted');
    expect((await call('GET', '/chats', { token: b })).body.chats.some((x: any) => x.id === chats[0])).toBe(false);
    await sendText(a, chats[0], 'new one');
    expect((await call('GET', '/chats', { token: b })).body.chats.some((x: any) => x.id === chats[0])).toBe(true);
    expect((await msgs(b, chats[0])).map((m: any) => m.text)).toEqual(['new one']);
    await call('POST', `/chats/${chats[0]}/clear`, { token: b });
    expect(await msgs(b, chats[0])).toEqual([]);
  });
});

describe('CHT-11 - CHT-17 groups', () => {
  let gid: string;
  it('create with system message; admins-only messages; settings system message', async () => {
    const r = await call('POST', '/chats/groups', { token: a, body: { name: 'Gardening', memberIds: [ids.b, ids.c] } });
    gid = r.body.chat.id;
    expect((await msgs(b, gid))[0]).toMatchObject({ kind: 'system', text: 'Amy Duncan created this group' });
    await call('PUT', `/chats/${gid}/settings`, { token: a, body: { membersCanMessage: false } });
    expect((await sendText(b, gid, 'hi')).body.error.message).toBe('Only admins can send messages in this group.');
    expect((await msgs(b, gid)).at(-1).text).toBe("Amy Duncan changed this group's settings to allow only admins to send messages");
    expect((await call('PUT', `/chats/${gid}/settings`, { token: b, body: { membersCanMessage: true } })).body.error.code).toBe('ADMIN_ONLY');
    await call('PUT', `/chats/${gid}/settings`, { token: a, body: { membersCanMessage: true } });
  });
  it('name (100), description (400), add members, invite permissions, approval', async () => {
    expect((await call('PATCH', `/chats/${gid}`, { token: a, body: { name: 'x'.repeat(101) } })).status).toBe(400);
    expect((await call('PATCH', `/chats/${gid}`, { token: a, body: { description: 'Weekend gardening' } })).body.message).toBe('Group description updated.');
    await call('PUT', `/chats/${gid}/settings`, { token: a, body: { membersCanInvite: false } });
    expect((await call('POST', `/chats/${gid}/members`, { token: b, body: { userIds: [ids.d] } })).body.error.message).toBe('Only admins can add others to this group');
    await call('PUT', `/chats/${gid}/settings`, { token: a, body: { membersCanInvite: true, approvalRequired: true } });
    expect((await call('POST', `/chats/${gid}/members`, { token: b, body: { userIds: [ids.d] } })).body).toMatchObject({ pending: 1, message: 'Members pending approval' });
    expect((await call('GET', `/chats/${gid}/requests`, { token: a })).body.requests).toHaveLength(1);
    // CHT-12.2: turning approval off approves everyone waiting.
    expect((await call('PUT', `/chats/${gid}/settings`, { token: a, body: { approvalRequired: false } })).body.approved).toBe(1);
    expect((await call('GET', `/chats/${gid}/members`, { token: a })).body.members).toHaveLength(4);
  });
  it('CHT-14.4 / 14.5 invite link: join directly, or request when approval is on', async () => {
    const link = (await call('POST', `/chats/${gid}/invite-link`, { token: a })).body;
    expect(link.message).toBe('Group link copied.');
    expect((await call('POST', `/chats/join/${link.code}`, { token: e })).body.state).toBe('member');
    expect((await msgs(e, gid)).at(-1).text).toBe("Eve Eee joined via this group's link");
    await call('PUT', `/chats/${gid}/settings`, { token: a, body: { approvalRequired: true } });
    expect((await call('GET', `/chats/join/${link.code}`, { token: f })).body).toMatchObject({ state: 'can_join', message: 'This group require admin permission to join' });
    expect((await call('POST', `/chats/join/${link.code}`, { token: f })).body).toMatchObject({ state: 'awaiting', message: 'Awaiting admin approval' });
    expect((await msgs(a, gid)).at(-1).text).toBe('Fay Eff requested to join');
    await call('POST', `/chats/${gid}/requests/${ids.f}/approve`, { token: a });
    expect((await call('GET', `/chats/join/${link.code}`, { token: f })).body.state).toBe('member');
  });
  it('CHT-15 admins, creator protection, removal and past members (admins only)', async () => {
    await call('POST', `/chats/${gid}/admins/${ids.b}`, { token: a });
    expect((await call('DELETE', `/chats/${gid}/members/${ids.a}`, { token: b })).body.error.message).toBe("You can't remove Amy Duncan as admin because they created this group chat");
    expect((await call('DELETE', `/chats/${gid}/admins/${ids.a}`, { token: b })).body.error.message).toBe("You can't dismiss Amy Duncan as admin because they created this group chat");
    expect((await call('DELETE', `/chats/${gid}/members/${ids.c}`, { token: b })).body.message).toBe('Member removed');
    expect((await sendText(c, gid, 'hi')).body.error.message).toBe('You cannot send messages to this group because you are no longer a member');
    expect((await call('GET', `/chats/${gid}/members`, { token: a })).body.pastMembers[0]).toMatchObject({ reason: 'removed' });
    expect((await call('GET', `/chats/${gid}/members`, { token: e })).body.pastMembers).toBeNull();
  });
  it('CHT-16 the only admin must assign a new admin before leaving', async () => {
    const r = await call('POST', '/chats/groups', { token: g, body: { name: 'Book club', memberIds: [ids.d] } });
    expect((await call('POST', `/chats/${r.body.chat.id}/exit`, { token: g })).body.error.message).toBe('You are the only admin in this group, assign a new admin before leaving.');
    expect((await call('POST', `/chats/${r.body.chat.id}/exit`, { token: g, body: { newAdminId: ids.d } })).body.message).toBe('You are no longer a member of this group');
    expect((await call('GET', `/chats/${r.body.chat.id}`, { token: d })).body.myRole).toBe('admin');
  });
  it('committee-only groups take committee members only', async () => {
    await seat(a, 'Chair');
    expect((await call('POST', '/chats/groups', { token: b, body: { name: 'Board', memberIds: [ids.c], committeeOnly: true } })).body.error.code).toBe('COMMITTEE_ONLY');
    const r = await call('POST', '/chats/groups', { token: a, body: { name: 'Board', memberIds: [ids.b], committeeOnly: true } });
    expect(r.body.error.code).toBe('NO_MEMBERS');
    expect((await call('GET', '/chats/people?committeeOnly=1', { token: b })).body.people.map((p: any) => p.firstName)).toEqual(['Amy']);
  });
});

it('CHT-01 tabs filter the list', async () => {
  const groups = (await call('GET', '/chats?tab=groups', { token: a })).body.chats;
  expect(groups.every((x: any) => x.type !== 'direct')).toBe(true);
  const primary = (await call('GET', '/chats?tab=primary', { token: a })).body.chats;
  expect(primary.every((x: any) => x.type === 'direct')).toBe(true);
  expect((await call('GET', '/chats?tab=events', { token: a })).body.chats).toEqual([]);
});
