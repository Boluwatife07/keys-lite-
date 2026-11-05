import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../../config.js';
import { one, q, tx } from '../../db/pool.js';
import { requireUser } from '../../lib/auth.js';
import { clock } from '../../lib/clock.js';
import { AppError, badRequest, conflict, forbidden } from '../../lib/errors.js';
import { LIMITS } from '../../lib/rules.js';
import { recordMilestones } from '../board/milestones.js';
import { normalise, places, streetKey } from '../../services/places.js';
import {
  card, communitiesForStreet, counts, createCommunity, haversineSql, saveAddress, upsertStreet, type CommunityRow,
  countsVisible,
} from './communities.js';

const INVALID_CODE = 'Invalid community code. Please check and try again.';
const ADDRESS_NOT_FOUND = 'Address not found. Please use a valid address.';

export const DEFAULT_BIO = "Hi neighbours! I've just joined Keys and I'm looking forward to getting to know our community.";
export const INVITE_MESSAGE = "Hey! I'm using the Keys app to stay connected to our community. Download it and join us!";

interface Ctx {
  userId: string;
  step: string;
  street: { id: string; name: string; town: string; lat: number; lng: number };
  premise: string;
  line1: string;
}

async function ctx(userId: string): Promise<Ctx> {
  const r = await one<any>(
    `select u.onboarding_step as step, a.premise, a.line1, s.id as sid, s.name, s.town, s.lat, s.lng
       from users u join addresses a on a.id = u.home_address_id join streets s on s.id = a.street_id
      where u.id = $1`,
    [userId],
  );
  if (!r) throw badRequest('ADDRESS_REQUIRED', 'Please add your home address first.');
  return { userId, step: r.step, premise: r.premise, line1: r.line1, street: { id: r.sid, name: r.name, town: r.town, lat: r.lat, lng: r.lng } };
}

function assertOnboarding(c: Ctx) {
  if (c.step === 'complete') throw forbidden('ONBOARDING_DONE', 'You have already joined a community.');
}

// Runs matching for the saved address and an optional community code (ONB-12, ONB-13).
async function match(c: Ctx, code?: string) {
  if (code) {
    const coded = await one<CommunityRow>('select * from communities where code = $1', [code.trim().toUpperCase()]);
    if (!coded) throw badRequest('INVALID_COMMUNITY_CODE', INVALID_CODE, { field: 'communityCode' });
    const covering = await communitiesForStreet(c.street.id);
    if (coded.type === 'building') {
      if (coded.anchor_street_id !== c.street.id) return { kind: 'code_ineligible' as const, codedName: coded.name, communities: [await card(coded)] };
      const parent = (await one<CommunityRow>('select * from communities where id = $1', [coded.parent_id]))!;
      if (coded.building_premise && coded.building_premise === c.premise) {
        return { kind: 'code_match' as const, communities: [await card(coded)] };
      }
      // ONB-12.5: same street, different building -> offer the parent community.
      return { kind: 'code_parent' as const, communities: [await card(parent)], codedName: coded.name };
    }
    if (covering.some((x) => x.id === coded.id)) return { kind: 'code_match' as const, communities: [await card(coded)] };
    return { kind: 'code_ineligible' as const, codedName: coded.name, communities: [await card(coded)] };
  }
  const covering = await communitiesForStreet(c.street.id);
  if (covering.length === 0) return { kind: 'none' as const, communities: [] };
  const cards = await Promise.all(covering.map((x) => card(x)));
  return { kind: covering.length === 1 ? ('single' as const) : ('multiple' as const), communities: cards };
}

/** After home type: the profile step, unless the resident already has one (moving home, PRF-11). */
async function afterHome(userId: string, db?: any) {
  const r = await one<{ photo_url: string | null; safety_ack_at: Date | null }>('select photo_url, safety_ack_at from users where id = $1', [userId], db);
  return r?.photo_url && r.safety_ack_at ? 'complete' : 'profile';
}

async function setStep(userId: string, step: string, db?: any) {
  await q('update users set onboarding_step = $2 where id = $1', [userId, step], db);
}

async function joinTopLevel(userId: string, communityId: string, db: any) {
  await q(
    `insert into memberships(user_id, community_id, level, building_id, joined_at) values ($1,$2,null,null,$3)
     on conflict (user_id) do update set community_id = excluded.community_id, level = null, building_id = null, joined_at = excluded.joined_at`,
    [userId, communityId, clock.now()], db,
  );
  await recordMilestones(communityId, db);
}

async function membership(userId: string) {
  const m = await one<any>(
    `select m.*, c.name, c.type, c.created_by from memberships m join communities c on c.id = m.community_id where m.user_id = $1`,
    [userId],
  );
  if (!m) throw badRequest('COMMUNITY_REQUIRED', 'Please choose your community first.');
  return m;
}

export async function onboardingRoutes(app: FastifyInstance) {
  // ONB-11.1: suggestions from the address provider.
  app.get('/addresses/autocomplete', async (req) => {
    requireUser(req);
    const { q: input, session } = z.object({ q: z.string().trim().min(1), session: z.string().optional() }).parse(req.query);
    return { suggestions: await places.autocomplete(input, session) };
  });

  // ONB-06 (new social account): confirm legal name.
  app.post('/onboarding/account', async (req) => {
    const u = requireUser(req);
    const body = z.object({ firstName: z.string().trim(), lastName: z.string().trim() }).parse(req.body);
    if (!body.firstName) throw badRequest('FIRST_NAME_REQUIRED', 'Add a first name', { field: 'firstName' });
    if (!body.lastName) throw badRequest('LAST_NAME_REQUIRED', 'Add a last name', { field: 'lastName' });
    if (u.onboarding_step !== 'account') throw forbidden('STEP_DONE', 'Your name is already set.');
    await q(`update users set first_name = $2, last_name = $3, onboarding_step = 'address' where id = $1`, [u.id, body.firstName, body.lastName]);
    return { onboardingStep: 'address' };
  });

  // ONB-11.2 - ONB-11.4, ONB-12: save the address and run matching.
  app.post('/onboarding/address', async (req) => {
    const u = requireUser(req);
    const body = z.object({
      placeId: z.string().min(1),
      sessionToken: z.string().optional(),
      communityCode: z.string().trim().optional().transform((v) => (v ? v : undefined)),
    }).parse(req.body);
    const step = (await one<{ s: string }>('select onboarding_step as s from users where id = $1', [u.id]))!.s;
    if (step === 'complete') throw forbidden('ONBOARDING_DONE', 'Use Change home address in Settings.');
    if (step === 'account') throw badRequest('NAME_REQUIRED', 'Please add your name first.');
    const resolved = await places.resolve(body.placeId, body.sessionToken);
    if (!resolved) throw badRequest('ADDRESS_NOT_FOUND', ADDRESS_NOT_FOUND, { field: 'address' });
    // Validate the code before saving so the user can clear it and carry on (ONB-12.2).
    if (body.communityCode && !(await one('select 1 from communities where code = $1', [body.communityCode.toUpperCase()]))) {
      throw badRequest('INVALID_COMMUNITY_CODE', INVALID_CODE, { field: 'communityCode' });
    }
    await tx(async (c) => {
      const { addressId } = await saveAddress(resolved, c);
      await q(`update users set home_address_id = $2, onboarding_step = 'community' where id = $1`, [u.id, addressId], c);
      await q('delete from memberships where user_id = $1', [u.id], c);
    });
    const c = await ctx(u.id);
    return { address: { line1: resolved.line1, formatted: resolved.formatted, street: resolved.streetName }, match: await match(c, body.communityCode) };
  });

  // Re-run matching (resume, or "Proceed with my address").
  app.post('/onboarding/match', async (req) => {
    const u = requireUser(req);
    const body = z.object({ communityCode: z.string().trim().optional() }).parse(req.body ?? {});
    const c = await ctx(u.id);
    assertOnboarding(c);
    return { match: await match(c, body.communityCode || undefined) };
  });

  // Join an existing community from a match screen.
  app.post('/onboarding/join', async (req) => {
    const u = requireUser(req);
    const { communityId } = z.object({ communityId: z.string().uuid() }).parse(req.body);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const target = await one<CommunityRow>('select * from communities where id = $1', [communityId]);
    if (!target) throw badRequest('NOT_ELIGIBLE', "You're not eligible for this community");
    const covering = await communitiesForStreet(c.street.id);
    if (target.type === 'building') {
      // Joining a building straight from its code: the building's house number must match.
      if (target.anchor_street_id !== c.street.id || target.building_premise !== c.premise || !covering.some((x) => x.id === target.parent_id)) {
        throw badRequest('NOT_ELIGIBLE', "You're not eligible for this community");
      }
      await tx(async (db) => {
        await joinTopLevel(u.id, target.parent_id!, db);
        await q(`update memberships set level = 'building', building_id = $2 where user_id = $1`, [u.id, target.id], db);
        await setStep(u.id, await afterHome(u.id, db), db);
      });
      const parent = (await one<{ name: string }>('select name from communities where id = $1', [target.parent_id]))!;
      return { onboardingStep: await afterHome(u.id), screen: 'welcome', name: parent.name };
    }
    if (!covering.some((x) => x.id === target.id)) throw badRequest('NOT_ELIGIBLE', "You're not eligible for this community");
    await tx(async (db) => {
      await joinTopLevel(u.id, target.id, db);
      await setStep(u.id, 'home_type', db);
    });
    return { onboardingStep: 'home_type', community: await card(target) };
  });

  // ONB-15: pioneer a street. One street community per street; a race loses cleanly.
  app.post('/onboarding/street', async (req) => {
    const u = requireUser(req);
    const c = await ctx(u.id);
    assertOnboarding(c);
    try {
      const created = await tx(async (db) => {
        const com = await createCommunity(db, {
          type: 'street', name: c.street.name, anchorStreetId: c.street.id, lat: c.street.lat, lng: c.street.lng, createdBy: u.id,
        });
        await q('insert into street_links(street_id, community_id) values ($1,$2)', [c.street.id, com.id], db);
        await joinTopLevel(u.id, com.id, db);
        await setStep(u.id, 'home_type', db);
        return com;
      });
      return { onboardingStep: 'home_type', community: await card(created) };
    } catch (e: any) {
      if (e.code !== '23505') throw e;
      const existing = (await one<CommunityRow>(`select * from communities where type = 'street' and anchor_street_id = $1`, [c.street.id]))!;
      throw conflict('STREET_COMMUNITY_EXISTS', `${existing.name} is already on Keys. Join your neighbours there.`, {
        community: await card(existing),
      });
    }
  });

  // ONB-18.2 / ONB-19.1: similar development names within 10 km (case insensitive).
  app.post('/onboarding/development/check', async (req) => {
    const u = requireUser(req);
    const { name } = z.object({ name: z.string().trim().min(1, 'Add a development name').max(60) }).parse(req.body);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const rows = await q<CommunityRow & { km: number }>(
      `select * from (
         select c.*, ${haversineSql('$2', '$3')} as km from communities c
          where c.type = 'development'
            and (similarity(lower(c.name), lower($1)) > 0.35 or lower(c.name) like '%' || lower($1) || '%' or lower($1) like '%' || lower(c.name) || '%')
       ) x where km <= $4 order by km`,
      [name, c.street.lat, c.street.lng, LIMITS.devNameRadiusKm],
    );
    const similar = await Promise.all(
      rows.map(async (r) => ({ ...(await card(r)), distanceKm: Math.round(r.km * 10) / 10 })),
    );
    return { similar };
  });

  // ONB-20.1: only streets directly connected to the user's street.
  app.get('/onboarding/development/connected-streets', async (req) => {
    const u = requireUser(req);
    const c = await ctx(u.id);
    const list = await places.connectedStreets(c.street);
    const out = [];
    for (const s of list) {
      const existing = await one<{ id: string }>(
        `select c.id from streets st join communities c on c.anchor_street_id = st.id and c.type = 'street' where st.street_key = $1`,
        [streetKey(s.name, s.town)],
      );
      out.push({ key: streetKey(s.name, s.town), name: s.name, town: s.town, hasStreetCommunity: !!existing });
    }
    return { yourStreet: { name: c.street.name, town: c.street.town }, streets: out, max: LIMITS.devStreetsMax };
  });

  // ONB-18, ONB-20: create the development with up to 5 connected streets.
  app.post('/onboarding/development', async (req) => {
    const u = requireUser(req);
    const body = z.object({
      name: z.string().trim().min(1, 'Add a development name').max(60),
      streetKeys: z.array(z.string()).default([]),
    }).parse(req.body);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const keys = [...new Set(body.streetKeys)].filter((k) => k !== streetKey(c.street.name, c.street.town));
    if (keys.length > LIMITS.devStreetsMax) throw badRequest('TOO_MANY_STREETS', 'Maximum of 5 streets can be linked');
    const connected = await places.connectedStreets(c.street);
    const chosen = keys.map((k) => connected.find((s) => streetKey(s.name, s.town) === k));
    if (chosen.some((s) => !s)) throw badRequest('STREET_NOT_CONNECTED', 'Only streets directly connected to your street can be added.');
    const created = await tx(async (db) => {
      const com = await createCommunity(db, { type: 'development', name: body.name, lat: c.street.lat, lng: c.street.lng, createdBy: u.id });
      await q('insert into street_links(street_id, community_id) values ($1,$2)', [c.street.id, com.id], db);
      for (const s of chosen) {
        const st = await upsertStreet(s!, db);
        // ONB-20.4: streets with their own community stay linked to it as well.
        await q('insert into street_links(street_id, community_id) values ($1,$2) on conflict do nothing', [st.id, com.id], db);
      }
      await joinTopLevel(u.id, com.id, db);
      await setStep(u.id, 'home_type', db);
      return com;
    });
    return { onboardingStep: 'home_type', community: await card(created) };
  });

  // ONB-19.2: preview before adding your street to an existing development.
  app.get('/onboarding/development/:id/join-preview', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const c = await ctx(u.id);
    const dev = await one<CommunityRow>(`select * from communities where id = $1 and type = 'development'`, [id]);
    if (!dev) throw badRequest('NOT_FOUND', 'Development not found.');
    const streets = await q<{ name: string }>(
      `select s.name from street_links l join streets s on s.id = l.street_id where l.community_id = $1 order by l.created_at`, [id],
    );
    return { development: await card(dev), yourStreet: c.street.name, streets: streets.map((s) => s.name) };
  });

  // ONB-19.3: join adds the user's street immediately, no vote.
  app.post('/onboarding/development/:id/join', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const dev = await one<CommunityRow & { km: number }>(
      `select c.*, ${haversineSql('$2', '$3')} as km from communities c where c.id = $1 and c.type = 'development'`,
      [id, c.street.lat, c.street.lng],
    );
    if (!dev || dev.km > LIMITS.devNameRadiusKm) throw badRequest('NOT_ELIGIBLE', "You're not eligible for this community");
    await tx(async (db) => {
      await q('insert into street_links(street_id, community_id) values ($1,$2) on conflict do nothing', [c.street.id, id], db);
      await joinTopLevel(u.id, id, db);
      await setStep(u.id, 'home_type', db);
    });
    return { onboardingStep: 'home_type', community: await card(dev) };
  });

  // ONB-16: house or building.
  const HOUSE = ['Bungalow', 'Detached house', 'Semi detached', 'Townhouse'];
  const BUILDING = ['Apartment', 'Maisonette', 'Duplex', 'Loft', 'High rise'];
  app.post('/onboarding/home-type', async (req) => {
    const u = requireUser(req);
    const body = z.object({ type: z.enum(['house', 'building']), subtype: z.string().optional() }).parse(req.body);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const m = await membership(u.id);
    const allowed = body.type === 'house' ? HOUSE : BUILDING;
    if (body.subtype && !allowed.includes(body.subtype)) throw badRequest('VALIDATION', 'Choose a home type from the list.');
    if (body.type === 'house') {
      await q(`update memberships set level = 'house', building_id = null, home_subtype = $2 where user_id = $1`, [u.id, body.subtype ?? null]);
      const next = await afterHome(u.id);
      await setStep(u.id, next);
      return { onboardingStep: next, screen: m.created_by === u.id ? 'live' : 'welcome', name: m.name };
    }
    await q(`update memberships set home_subtype = $2 where user_id = $1`, [u.id, body.subtype ?? null]);
    return { onboardingStep: 'home_type', next: 'building', buildings: await buildingsOnStreet(c.street.id, m.community_id) };
  });

  async function buildingsOnStreet(streetId: string, communityId: string) {
    const rows = await q<CommunityRow>(
      `select * from communities where type = 'building' and anchor_street_id = $1 and parent_id = $2 order by name`,
      [streetId, communityId],
    );
    return Promise.all(rows.map(async (b) => {
      const n = (await counts(b.id)).residents;
      return { id: b.id, name: b.name, residents: countsVisible(n) ? n : undefined };
    }));
  }

  // ONB-17.4
  app.get('/onboarding/buildings', async (req) => {
    const u = requireUser(req);
    const c = await ctx(u.id);
    const m = await membership(u.id);
    return { buildings: await buildingsOnStreet(c.street.id, m.community_id) };
  });

  // ONB-17.1 - ONB-17.3
  app.post('/onboarding/building', async (req) => {
    const u = requireUser(req);
    const { name } = z.object({ name: z.string().trim().min(1, 'Add a building name').max(60) }).parse(req.body);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const m = await membership(u.id);
    const addr = await one<{ lat: number; lng: number }>('select a.lat, a.lng from users u join addresses a on a.id = u.home_address_id where u.id = $1', [u.id]);
    try {
      const b = await tx(async (db) => {
        const com = await createCommunity(db, {
          type: 'building', name, parentId: m.community_id, anchorStreetId: c.street.id, premise: c.premise, lat: addr!.lat, lng: addr!.lng, createdBy: u.id,
        });
        await q(`update memberships set level = 'building', building_id = $2 where user_id = $1`, [u.id, com.id], db);
        await setStep(u.id, await afterHome(u.id, db), db);
        return com;
      });
      return { onboardingStep: await afterHome(u.id), screen: 'live', name: b.name };
    } catch (e: any) {
      if (e.code === '23505') throw conflict('BUILDING_EXISTS', `"${name}" already exists on this street. Choose a different name.`, { field: 'name' });
      throw e;
    }
  });

  app.post('/onboarding/building/:id/join', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const c = await ctx(u.id);
    assertOnboarding(c);
    const m = await membership(u.id);
    const b = await one<CommunityRow>(`select * from communities where id = $1 and type = 'building'`, [id]);
    if (!b || b.anchor_street_id !== c.street.id || b.parent_id !== m.community_id) throw badRequest('NOT_ELIGIBLE', "You're not eligible for this building");
    await q(`update memberships set level = 'building', building_id = $2 where user_id = $1`, [u.id, id]);
    const next = await afterHome(u.id);
    await setStep(u.id, next);
    return { onboardingStep: next, screen: 'welcome', name: m.name };
  });

  // ONB-22: photo required (JPG/PNG <= 15 MB, already validated by /media), bio <= 160, safety ack.
  app.post('/onboarding/profile', async (req) => {
    const u = requireUser(req);
    const body = z.object({
      photoMediaId: z.string().uuid({ message: 'Add a profile picture' }),
      bio: z.string().max(LIMITS.bio, `Bio can be up to ${LIMITS.bio} characters`).optional(),
      safetyAccepted: z.literal(true, { message: 'Please confirm you have read the Keys safety guidelines' }),
    }).parse(req.body);
    const step = (await one<{ s: string }>('select onboarding_step as s from users where id = $1', [u.id]))!.s;
    if (step !== 'profile') throw badRequest('STEP_ORDER', 'Please finish the earlier steps first.');
    const photo = await one<{ url: string }>(`select url from media where id = $1 and owner_id = $2 and kind = 'photo'`, [body.photoMediaId, u.id]);
    if (!photo) throw badRequest('PHOTO_REQUIRED', 'Add a profile picture');
    await q(
      `update users set photo_url = $2, bio = $3, safety_ack_at = $4, onboarding_step = 'complete' where id = $1`,
      [u.id, photo.url, (body.bio ?? DEFAULT_BIO).trim(), clock.now()],
    );
    return { onboardingStep: 'complete' };
  });

  app.get('/onboarding/defaults', async () => ({
    bio: DEFAULT_BIO,
    bioMax: LIMITS.bio,
    houseTypes: HOUSE,
    buildingTypes: BUILDING,
    safetyUrl: config.legal.safetyUrl,
  }));

  // ONB-24: community invite link.
  app.get('/communities/mine/invite', async (req) => {
    const u = requireUser(req);
    const m = await one<{ code: string; name: string }>(
      `select c.code, c.name from memberships m join communities c on c.id = m.community_id where m.user_id = $1`, [u.id],
    );
    if (!m) throw badRequest('COMMUNITY_REQUIRED', 'Join a community first.');
    const link = `${config.linkBaseUrl}/c/${m.code}`;
    return { link, code: m.code, community: m.name, message: `${INVITE_MESSAGE} ${link}` };
  });

  // ONB-24.4: an invite link opened in the app. Signed-out users carry the
  // code into sign-up; signed-in users see whether they are eligible.
  app.get('/communities/by-code/:code', async (req) => {
    const { code } = z.object({ code: z.string() }).parse(req.params);
    const com = await one<CommunityRow>('select * from communities where code = $1', [code.toUpperCase()]);
    if (!com) throw new AppError(404, 'NOT_AVAILABLE', INVALID_CODE);
    const out: any = { community: await card(com), code: com.code };
    if (req.authUser) {
      const addr = await one('select 1 from users where id = $1 and home_address_id is not null', [req.authUser.id]);
      if (addr) {
        const c = await ctx(req.authUser.id);
        out.eligibility = c.step === 'complete' ? { kind: 'already_member' } : await match(c, com.code);
      }
    }
    return out;
  });

  // ONB-25: welcome post template. Publishing goes through the Feed post API.
  app.get('/onboarding/welcome-post', async (req) => {
    const u = requireUser(req);
    const m = await membership(u.id);
    return {
      community: m.name,
      text: `Hi neighbours! I'm ${u.first_name} and I've just joined ${m.name} on Keys. Looking forward to getting to know you all!`,
      imageUrl: '/static/welcome-post.png',
      audience: 'everyone',
    };
  });
  app.post('/onboarding/welcome-prompt/done', async (req) => {
    const u = requireUser(req);
    await q('update users set welcome_prompt_done_at = coalesce(welcome_prompt_done_at, $2) where id = $1', [u.id, clock.now()]);
    return { ok: true };
  });

  // LRN-01.4 / LRN-01.5: tour finished or skipped, never shown again on any device.
  app.post('/learning/done', async (req) => {
    const u = requireUser(req);
    z.object({ outcome: z.enum(['completed', 'skipped']) }).parse(req.body);
    await q('update users set learning_done_at = coalesce(learning_done_at, $2) where id = $1', [u.id, clock.now()]);
    return { ok: true };
  });
}

export { normalise };
