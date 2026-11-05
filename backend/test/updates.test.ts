import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { q } from '../src/db/pool.js';
import { call, joinStreet, me, PDF, pioneerStreet, placeId, PNG, seat, setup, signUp, teardown, upload, verify, finishProfile } from './helpers.js';

let chair: string; let house: string; let flat: string; let other: string;
let buildingId: string; let streetId: string; let flatId: string;

async function flatResident(email: string, address: string) {
  const t = await signUp(email, 'Fla', 'Tee');
  const r = await call('POST', '/onboarding/address', { token: t, body: { placeId: await placeId(t, address) } });
  await call('POST', '/onboarding/join', { token: t, body: { communityId: r.body.match.communities[0].id } });
  const h = await call('POST', '/onboarding/home-type', { token: t, body: { type: 'building' } });
  if (h.body.buildings.length) await call('POST', `/onboarding/building/${h.body.buildings[0].id}/join`, { token: t });
  else await call('POST', '/onboarding/building', { token: t, body: { name: 'Linden House' } });
  await finishProfile(t);
  return t;
}
const notes = async (t: string) => (await call('GET', '/notifications', { token: t })).body.notifications;

beforeAll(async () => {
  await setup();
  chair = (await pioneerStreet('chair@keys.test', '1 Maple Road')).token;
  await verify(chair);
  await seat(chair, 'Chair');
  house = await joinStreet('house@keys.test', '2 Maple Road', 'Hou', 'Se');
  flat = await flatResident('flat@keys.test', 'Flat 1, 30 Maple Road');
  other = await joinStreet('other@keys.test', '3 Maple Road', 'Oth', 'Er');
  flatId = (await me(flat)).id;
  const opts = (await call('GET', '/updates/audience-options', { token: chair })).body;
  buildingId = opts.buildings[0].id;
  streetId = opts.streets[0].id;
});
afterAll(teardown);

describe('UPD-02 create (committee only)', () => {
  it('rejects residents and invalid forms', async () => {
    expect((await call('POST', '/updates', { token: house, body: { title: 'x', details: 'y' } })).body.error.code).toBe('COMMITTEE_ONLY');
    expect((await call('POST', '/updates', { token: chair, body: { title: 'x'.repeat(101), details: 'y' } })).status).toBe(400);
    expect((await call('POST', '/updates', { token: chair, body: { title: 'x', details: 'y'.repeat(701) } })).status).toBe(400);
    expect((await call('POST', '/updates', { token: chair, body: { title: 'x', details: 'y', audience: 'sub' } })).body.error.code).toBe('AUDIENCE_REQUIRED');
    const opts = (await call('GET', '/updates/audience-options?q=Lin', { token: chair })).body;
    expect(opts.buildings.map((b: any) => b.name)).toEqual(['Linden House']);
    expect(opts.streets).toEqual([]);
  });
});

let lift: string;
describe('UPD-03 / UPD-04 audience and notifications', () => {
  it('a building-only update is seen and notified only there (committee still sees it)', async () => {
    const img = (await upload('/media?kind=photo', chair, { name: 'a.png', mime: 'image/png', data: PNG })).body.id;
    const doc = (await upload('/media?kind=document', chair, { name: 'notice.pdf', mime: 'application/pdf', data: PDF })).body.id;
    const r = await call('POST', '/updates', { token: chair, body: { title: 'Lift out of service', details: 'The lift is being repaired until Friday.', imageIds: [img], documentId: doc, audience: 'sub', buildingIds: [buildingId], groupChat: true } });
    expect(r.body.message).toBe('Your update is now live.');
    expect(r.body.update).toMatchObject({ locations: 'Linden House', images: [expect.any(String)] });
    lift = r.body.update.id;
    expect((await call('GET', '/updates', { token: flat })).body.updates.map((u: any) => u.title)).toEqual(['Lift out of service']);
    expect((await call('GET', '/updates', { token: house })).body.updates).toEqual([]);
    expect((await call('GET', `/updates/${lift}`, { token: house })).status).toBe(404);
    expect((await call('GET', '/updates', { token: chair })).body.updates).toHaveLength(1);
    expect((await notes(flat)).filter((n: any) => n.type === 'update_new')).toHaveLength(1);
    expect((await notes(house)).filter((n: any) => n.type === 'update_new')).toHaveLength(0);
  });
  it('locations label shortens long lists', async () => {
    const r = await call('POST', '/updates', { token: chair, body: { title: 'Bins', details: 'Bins day moved', audience: 'sub', streetIds: [streetId], buildingIds: [buildingId] } });
    expect(r.body.update.locations).toBe('Maple Road, Linden House');
    expect((await call('GET', '/updates', { token: house })).body.updates.map((u: any) => u.title)).toEqual(['Bins']);
  });
});

describe('UPD-05 / UPD-06 / UPD-07 detail and additional updates', () => {
  it('detail, document download (verified only), follow-ups by committee, unseen count', async () => {
    const d = (await call('GET', `/updates/${lift}`, { token: flat })).body.update;
    expect(d).toMatchObject({ document: { name: 'notice.pdf', downloads: 0 }, additional: [], canAddAdditional: false, chat: { joined: false } });
    expect((await call('POST', `/updates/${lift}/document/download`, { token: flat })).body.error.code).toBe('VERIFICATION_REQUIRED');
    await verify(flat);
    expect((await call('POST', `/updates/${lift}/document/download`, { token: flat })).body.name).toBe('notice.pdf');
    expect((await call('POST', `/updates/${lift}/additional`, { token: flat, body: { text: 'hi' } })).body.error.code).toBe('COMMITTEE_ONLY');
    const a = (await call('POST', `/updates/${lift}/additional`, { token: chair, body: { text: 'Engineer arriving at 10am' } })).body.additional;
    const find = async () => (await call('GET', '/updates', { token: flat })).body.updates.find((x: any) => x.id === lift);
    expect(await find()).toMatchObject({ additionalCount: 1, newAdditional: 1 });
    expect((await notes(flat)).filter((n: any) => n.type === 'update_additional')).toHaveLength(1);
    await call('GET', `/updates/${lift}`, { token: flat });
    expect((await find()).newAdditional).toBe(0);
    expect((await call('PATCH', `/additional-updates/${a.id}`, { token: chair, body: { text: 'Engineer arriving at 11am' } })).body.additional.editedAt).toBeTruthy();
    expect((await call('DELETE', `/additional-updates/${a.id}`, { token: chair })).body.message).toBe('Additional update deleted.');
    const after = (await call('GET', `/updates/${lift}`, { token: flat })).body.update.additional;
    expect(after[0]).toMatchObject({ deleted: true, text: 'Additional update is no longer available.' });
  });
});

describe('UPD-08 / UPD-09 / UPD-10 pin, mute, delete for me', () => {
  it('pins up to 3 on top; mute stops notifications; hide removes it for me only', async () => {
    const ids = [];
    for (const t of ['A', 'B', 'C', 'D']) ids.push((await call('POST', '/updates', { token: chair, body: { title: `Note ${t}`, details: 'x' } })).body.update.id);
    for (const id of ids.slice(0, 3)) await call('POST', `/updates/${id}/pin`, { token: house });
    expect((await call('POST', `/updates/${ids[3]}/pin`, { token: house })).body.error.message).toBe('You can only pin 3 updates');
    const list = (await call('GET', '/updates', { token: house })).body.updates;
    expect(list.slice(0, 3).every((u: any) => u.pinned)).toBe(true);
    await call('PUT', `/updates/${ids[0]}/mute`, { token: house, body: { duration: '1w' } });
    await call('POST', `/updates/${ids[0]}/additional`, { token: chair, body: { text: 'More' } });
    await call('POST', `/updates/${ids[1]}/additional`, { token: chair, body: { text: 'More' } });
    const n = (await notes(house)).filter((x: any) => x.type === 'update_additional').map((x: any) => x.itemId);
    expect(n).toEqual([ids[1]]);
    expect((await call('POST', `/updates/${ids[3]}/hide`, { token: house })).body.message).toBe('Update deleted.');
    expect((await call('GET', '/updates', { token: house })).body.updates.some((u: any) => u.id === ids[3])).toBe(false);
    expect((await call('GET', '/updates', { token: other })).body.updates.some((u: any) => u.id === ids[3])).toBe(true);
  });
});

describe('UCH update group chat', () => {
  it('committee added, creator admin; audience residents join; others cannot; no invite link', async () => {
    const d = (await call('GET', `/updates/${lift}`, { token: flat })).body.update;
    const chatId = d.chat.id;
    const c = (await call('GET', `/chats/${chatId}`, { token: chair })).body;
    expect(c).toMatchObject({ type: 'update', name: 'Lift out of service', myRole: 'admin' });
    expect((await call('POST', `/updates/${lift}/chat/join`, { token: house })).status).toBe(404); // not in audience, cannot even see the update
    expect((await call('POST', `/updates/${lift}/chat/join`, { token: flat })).body.chatId).toBe(chatId);
    const msgs = (await call('GET', `/chats/${chatId}/messages`, { token: flat })).body.messages;
    expect(msgs.at(-1)).toMatchObject({ kind: 'system', system: { type: 'joined', actorId: flatId } });
    expect((await call('POST', `/chats/${chatId}/messages`, { token: flat, body: { text: 'Thanks for the heads up' } })).status).toBe(200);
    expect((await call('POST', `/chats/${chatId}/invite-link`, { token: chair })).body.error.code).toBe('NO_LINK');
    expect((await call('PATCH', `/chats/${chatId}`, { token: chair, body: { name: 'New name' } })).body.error.code).toBe('NAME_LOCKED');
    // UPD-11.4: chat cannot be switched off
    expect((await call('PATCH', `/updates/${lift}`, { token: chair, body: { title: 'Lift out of service', details: 'x', audience: 'sub', buildingIds: [buildingId], groupChat: false } })).body.error.code).toBe('CHAT_LOCKED');
  });
  it('UPD-11.3 turning the chat on by editing creates it', async () => {
    const r = await call('POST', '/updates', { token: chair, body: { title: 'Parking', details: 'New rules' } });
    expect(r.body.chatId).toBeNull();
    const e = await call('PATCH', `/updates/${r.body.update.id}`, { token: chair, body: { title: 'Parking', details: 'New rules', groupChat: true } });
    expect(e.body.message).toBe('Changes saved to update.');
    expect(e.body.update.chatId).toBeTruthy();
  });
});

describe('UPD-12 / UPD-13 / UPD-14 resolve, delete, resolved search', () => {
  it('resolve makes the chat read-only and moves the update to Resolved; search by title', async () => {
    expect((await call('POST', `/updates/${lift}/resolve`, { token: flat })).body.error.code).toBe('NOT_ALLOWED');
    expect((await call('POST', `/updates/${lift}/resolve`, { token: chair })).body.message).toBe('Update has been resolved');
    const d = (await call('GET', `/updates/${lift}`, { token: flat })).body.update;
    expect(d).toMatchObject({ status: 'resolved', canAddAdditional: false });
    expect((await call('POST', `/chats/${d.chat.id}/messages`, { token: flat, body: { text: 'still?' } })).body.error.code).toBe('READ_ONLY');
    expect((await call('GET', '/updates', { token: flat })).body.hasResolved).toBe(true);
    expect((await call('GET', '/updates/resolved?q=lift', { token: flat })).body.updates.map((u: any) => u.title)).toEqual(['Lift out of service']);
    expect((await call('GET', '/updates/resolved?q=zzz', { token: flat })).body.updates).toEqual([]);
  });
  it('the Chair can resolve any update; the creator deletes for everyone', async () => {
    const t = await joinStreet('sec@keys.test', '9 Maple Road', 'Sec', 'Re');
    await verify(t);
    await seat(t, 'Secretary');
    const r = (await call('POST', '/updates', { token: t, body: { title: 'Gate code', details: 'Changed' } })).body.update;
    expect((await call('POST', `/updates/${r.id}/resolve`, { token: chair })).status).toBe(200);
    const r2 = (await call('POST', '/updates', { token: t, body: { title: 'Typo', details: 'x' } })).body.update;
    expect((await call('DELETE', `/updates/${r2.id}`, { token: chair })).body.error.code).toBe('NOT_AUTHOR');
    expect((await call('DELETE', `/updates/${r2.id}`, { token: t })).body.message).toBe('Your update has been deleted.');
    expect((await call('GET', `/updates/${r2.id}`, { token: house })).body.error).toMatchObject({ code: 'POST_DELETED', title: 'Post unavailable' });
    await q(`update updates set status = 'removed' where id = $1`, [r.id]);
    expect((await call('GET', `/updates/${r.id}`, { token: house })).body.error.message).toBe('This post has been removed for violating Keys Guidelines');
  });
});

describe('UPD-01.2 unseen state and edit data', () => {
  it('a new update is unseen until opened; new additional updates make it unseen again', async () => {
    const r = await call('POST', '/updates', { token: chair, body: { title: 'Bin day moved', details: 'Collection moves to Thursday.' } });
    const id = r.body.update.id;
    const card = async () => (await call('GET', '/updates', { token: house })).body.updates.find((u: any) => u.id === id);
    expect((await card()).seen).toBe(false);
    await call('GET', `/updates/${id}`, { token: house });
    expect((await card()).seen).toBe(true);
    await call('POST', `/updates/${id}/additional`, { token: chair, body: { text: 'And again next week.' } });
    expect(await card()).toMatchObject({ seen: false, newAdditional: 1 });
    expect(r.body.update).toMatchObject({ imageMedia: [], documentId: null });
  });

  it('/me says whether the resident is on the committee', async () => {
    expect(await me(chair)).toMatchObject({ boardRole: 'Chair', isCommittee: true });
    expect(await me(house)).toMatchObject({ boardRole: null, isCommittee: false });
  });
});

describe('UPD-01.2 the author', () => {
  it('has read their own update and follow-ups', async () => {
    const id = (await call('POST', '/updates', { token: chair, body: { title: 'Parking bay works', details: 'Bays 1-4 closed.' } })).body.update.id;
    await call('POST', `/updates/${id}/additional`, { token: chair, body: { text: 'Now bays 1-6.' } });
    const card = (await call('GET', '/updates', { token: chair })).body.updates.find((u: any) => u.id === id);
    expect(card).toMatchObject({ seen: true, newAdditional: 0 });
  });
});
