import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { one, q, tx } from '../../db/pool.js';
import { requireUser, requireVerified } from '../../lib/auth.js';
import { clock } from '../../lib/clock.js';
import { badRequest, conflict, forbidden, notFound } from '../../lib/errors.js';
import { exitCheck } from '../../lib/exit.js';
import { notify } from '../../lib/notify.js';
import { communityOf, people, person, seatOf } from '../../lib/people.js';
import { shareLink } from '../links/routes.js';
import { markMilestoneSeen, milestonePrompt, MILESTONES, newMemberIds } from './milestones.js';
import { eligibleVoters, evaluate, tally } from './proposals.js';
import {
  announce, boardFor, broadcast, closesAt, committeeIds, leaveBoard, occupy, PRESET_ROLES, protectSeat, refreshTier, residentCount,
  ROLE_ABOUT, seats, syncSeats, TIERS, tierFor, VOTE_MIN_BOARD, withinAllowance, type Board, type SeatRow,
} from './service.js';

const LONG = 500;
const answers = z.object({
  pledge: z.literal(true, { message: 'Please tick the pledge to continue' }),
  hasLeadership: z.boolean(),
  leadershipTitle: z.string().trim().max(100).optional(),
  leadershipDescription: z.string().trim().max(LONG).optional(),
  qualified: z.string().trim().min(1, 'Tell us what makes you qualified for this role').max(LONG),
  aim: z.string().trim().min(1, 'Tell us what you aim to achieve in this role').max(LONG),
});
type Answers = z.infer<typeof answers>;

async function ctx(userId: string) {
  const c = await communityOf(userId);
  if (!c) throw notFound('Join a community first.');
  let board = await boardFor(c);
  if (board) board = await refreshTier(board);
  return { communityId: c, board };
}

async function requireBoard(userId: string) {
  const x = await ctx(userId);
  if (!x.board) throw notFound('Create a committee board to make this feature available for your community.');
  return { ...x, board: x.board };
}

async function requireCommittee(userId: string) {
  const x = await requireBoard(userId);
  const s = await seatOf(userId);
  if (!s || s.kind === 'champion') throw forbidden('COMMITTEE_ONLY', 'Only committee members can do this.');
  return { ...x, seat: s };
}

async function saveApplication(c: any, boardId: string, userId: string, seat: SeatRow, a: Answers, status: 'pending' | 'added') {
  if (a.hasLeadership && !a.leadershipTitle) throw badRequest('VALIDATION', 'Add your role title', { field: 'leadershipTitle' });
  return (await one<{ id: string }>(
    `insert into board_applications(board_id, user_id, seat_id, role, pledged_at, has_leadership, leadership_title, leadership_description, qualified, aim, status, created_at)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$5) returning id`,
    [boardId, userId, seat.id, seat.role, clock.now(), a.hasLeadership, a.hasLeadership ? a.leadershipTitle : null, a.hasLeadership ? a.leadershipDescription ?? null : null, a.qualified, a.aim, status], c,
  ))!;
}

function seatStatus(s: SeatRow, viewer: string, pendingSeat?: string | null) {
  if (s.occupant_id) return s.occupant_id === viewer ? 'you' : 'occupied';
  if (pendingSeat === s.id) return 'pending';
  return 'unoccupied';
}

async function boardSummary(board: Board, viewer: string) {
  const all = await seats(board.id);
  const committee = all.filter((s) => s.kind !== 'champion' && s.occupant_id);
  const champions = all.filter((s) => s.kind === 'champion' && s.occupant_id);
  const ps = await people(committee.map((s) => s.occupant_id!));
  return {
    id: board.id,
    tier: board.tier,
    committeeCount: committee.length,
    championCount: champions.length,
    votingAvailable: committee.length >= VOTE_MIN_BOARD,
    preview: committee.slice(0, 6).map((s) => ({ ...ps.get(s.occupant_id!), isYou: s.occupant_id === viewer })),
  };
}

function proposalStatusFor(p: any, viewerVoted: boolean) {
  if (p.status === 'pending') return viewerVoted ? 'awaiting_approval' : 'pending';
  if (p.status === 'approved') return p.type === 'join' ? 'added' : 'approved';
  return p.status; // declined | no_longer_applicable
}

async function proposalView(p: any, viewer: string, detail = false) {
  const ps = await people([p.subject_id, p.creator_id, p.swap_with_id].filter(Boolean));
  const myVote = await one<{ choice: string }>('select choice from proposal_votes where proposal_id = $1 and voter_id = $2', [p.id, viewer]);
  const seat = p.seat_id ? await one<SeatRow>('select * from board_seats where id = $1', [p.seat_id]) : undefined;
  const from = p.from_seat_id ? await one<SeatRow>('select * from board_seats where id = $1', [p.from_seat_id]) : undefined;
  const eligible = await eligibleVoters(p);
  const base: any = {
    id: p.id,
    type: p.type,
    typeLabel: { join: 'Join board', reassign: 'Reassign role', remove: 'Remove Member' }[p.type as string],
    status: proposalStatusFor(p, !!myVote),
    outcomeNote: p.outcome_note === 'NEW_SEAT_PROTECTION' ? 'This proposal was turned down because the seat is already filled by the first winning applicant.' : null,
    subject: ps.get(p.subject_id),
    creator: ps.get(p.creator_id),
    role: p.type === 'join' ? seat?.role : from?.role,
    proposedRole: p.type === 'reassign' ? seat?.role : undefined,
    reason: p.reason,
    closesAt: p.closes_at,
    createdAt: p.created_at,
    category: 'Committee board',
    myVote: myVote?.choice ?? null,
    canVote: p.status === 'pending' && !myVote && eligible.includes(viewer),
  };
  if (p.swap_with_id) {
    const a = ps.get(p.subject_id)!.name, b = ps.get(p.swap_with_id)!.name;
    base.swap = { with: ps.get(p.swap_with_id), note: `If this proposal is approved by the board, ${b}'s current role would be reassigned to ${a} as well.` };
  }
  if (!detail) return base;
  if (p.application_id) {
    const a = await one<any>('select * from board_applications where id = $1', [p.application_id]);
    base.answers = a && {
      hasLeadership: a.has_leadership, leadershipTitle: a.leadership_title, leadershipDescription: a.leadership_description,
      qualified: a.qualified, aim: a.aim,
    };
  }
  // VOT-02.3: results after you vote or once closed.
  if (myVote || p.status !== 'pending') {
    const { yes, no } = await tally(p.id);
    const votes = await q<{ voter_id: string; choice: string; reason: string | null }>('select voter_id, choice, reason from proposal_votes where proposal_id = $1 order by created_at', [p.id]);
    const vp = await people(votes.map((v) => v.voter_id));
    const total = yes + no;
    base.results = {
      yes, no,
      yesPercent: total ? Math.round((yes / total) * 100) : 0,
      noPercent: total ? Math.round((no / total) * 100) : 0,
      eligible: eligible.length,
      voters: votes.map((v) => ({ person: vp.get(v.voter_id), choice: v.choice, reason: v.reason })),
    };
  }
  return base;
}

export async function boardRoutes(app: FastifyInstance) {
  // CBM-01: community tab header, board summary, announcements.
  app.get('/community', async (req) => {
    const u = requireUser(req);
    const { communityId, board } = await ctx(u.id);
    const c = (await one<any>('select id, name, type, code from communities where id = $1', [communityId]))!;
    const a = await one<{ town: string; postcode: string }>('select a.town, a.postcode from users x join addresses a on a.id = x.home_address_id where x.id = $1', [u.id]);
    const seat = await seatOf(u.id);
    const typeLabel = { street: 'Street', development: 'Development', building: 'Building' }[c.type as string];
    return {
      community: { id: c.id, name: c.name, type: c.type, code: c.code, location: `${typeLabel} | ${a?.town ?? ''}, ${a?.postcode.split(' ')[0] ?? ''}, UK` },
      board: board ? await boardSummary(board, u.id) : null,
      me: { role: seat?.role ?? null, isCommittee: !!seat && seat.kind !== 'champion', isChampion: seat?.kind === 'champion', isChair: seat?.role === 'Chair' },
      proposalsTab: !!seat && seat.kind !== 'champion',
      announcements: board ? await announcements(board.id) : [],
      milestone: await milestonePrompt(u.id, communityId),
      tierUp: board?.tier_up_at && clock.now().getTime() - board.tier_up_at.getTime() < 14 * 86400000 ? { tier: board.tier } : null,
      shareLink: shareLink('c', c.code),
    };
  });

  // CBM-Q2: close the milestone prompt (also sent when "View new residents" is tapped).
  app.post('/community/milestone/seen', async (req) => {
    const u = requireUser(req);
    const { threshold } = z.object({ threshold: z.number().int().refine((t) => MILESTONES.includes(t)) }).parse(req.body);
    const { communityId } = await ctx(u.id);
    await markMilestoneSeen(u.id, communityId, threshold);
    return { ok: true };
  });

  // CBM-Q2: "New members" list behind "View new residents".
  app.get('/community/new-members', async (req) => {
    const u = requireUser(req);
    const { communityId } = await ctx(u.id);
    const ids = await newMemberIds(u.id, communityId);
    const ps = await people(ids);
    return { members: ids.map((id) => ps.get(id)).filter(Boolean) };
  });

  async function announcements(boardId: string) {
    const rows = await q<any>('select * from board_announcements where board_id = $1 order by created_at desc limit 20', [boardId]);
    const ps = await people(rows.map((r) => r.subject_id));
    const labels = { new_member: 'New member', role_change: 'Role change', board_exit: 'Board exit', member_removal: 'Member removal' } as Record<string, string>;
    return rows.map((r) => ({ id: r.id, type: r.type, label: labels[r.type], text: r.text, role: r.role, reason: r.reason, subject: ps.get(r.subject_id) ?? null, createdAt: r.created_at }));
  }

  app.get('/board/announcements', async (req) => {
    const { board } = await requireBoard(requireUser(req).id);
    return { announcements: await announcements(board.id) };
  });

  // CBM-04.3 / CBM-05.1: roles with their descriptions and whether they are free.
  app.get('/board/roles', async (req) => {
    const u = requireUser(req);
    const { board } = await ctx(u.id);
    const taken = board ? new Set((await seats(board.id)).filter((s) => s.kind === 'preset' && s.occupant_id).map((s) => s.role)) : new Set<string>();
    return { roles: PRESET_ROLES.map((r) => ({ role: r, about: ROLE_ABOUT[r], available: !taken.has(r) })) };
  });

  // CBM-09: the board.
  app.get('/board', async (req) => {
    const u = requireUser(req);
    const { board } = await requireBoard(u.id);
    const all = await seats(board.id);
    const pending = await one<{ seat_id: string }>(`select seat_id from board_applications where user_id = $1 and status = 'pending'`, [u.id]);
    const shown = all.filter((s) => s.occupant_id || (s.active && withinAllowance(s, board.tier)));
    const ps = await people(shown.map((s) => s.occupant_id!).filter(Boolean));
    const view = shown.map((s) => ({
      id: s.id, kind: s.kind, role: s.role, occupant: s.occupant_id ? ps.get(s.occupant_id) : null, status: seatStatus(s, u.id, pending?.seat_id),
    }));
    const committee = view.filter((s) => s.kind !== 'champion');
    const champions = view.filter((s) => s.kind === 'champion');
    const mySeat = all.find((s) => s.occupant_id === u.id);
    return {
      ...(await boardSummary(board, u.id)),
      seats: view,
      counts: { all: view.filter((s) => s.occupant).length, members: committee.filter((s) => s.occupant).length, champions: champions.filter((s) => s.occupant).length },
      myApplication: pending ? { seatId: pending.seat_id } : null,
      mySeat: mySeat ? { id: mySeat.id, role: mySeat.role, kind: mySeat.kind } : null,
      canManageSeats: mySeat?.role === 'Chair',
    };
  });

  // CBM-10: tiers explainer.
  app.get('/board/tiers', async (req) => {
    const u = requireUser(req);
    const { communityId, board } = await ctx(u.id);
    const residents = await residentCount(communityId);
    const all = board ? await seats(board.id) : [];
    const tier = board?.tier ?? tierFor(residents).tier;
    return {
      residents,
      currentTier: tier,
      tiers: TIERS.map((t) => ({ ...t, residentsLabel: t.max === null ? `${t.min}+` : `${t.min}-${t.max}` })),
      seats: {
        available: all.filter((s) => withinAllowance(s, tier)).length,
        active: all.filter((s) => s.active && withinAllowance(s, tier)).length,
        occupied: all.filter((s) => s.occupant_id).length,
      },
    };
  });

  // CBM-04: the first verified resident creates the board in a preset role.
  app.post('/board', async (req) => {
    const u = await requireVerified(req);
    const b = answers.extend({ role: z.enum(PRESET_ROLES) }).parse(req.body);
    const { communityId, board } = await ctx(u.id);
    if (board) throw conflict('BOARD_EXISTS', 'Your community already has a committee board.');
    const tier = tierFor(await residentCount(communityId)).tier;
    const note = await tx(async (c) => {
      const nb = await one<Board>('insert into boards(community_id, tier) values ($1,$2) on conflict (community_id) do nothing returning *', [communityId, tier], c);
      if (!nb) throw conflict('BOARD_EXISTS', 'Your community already has a committee board.');
      for (const [i, r] of PRESET_ROLES.entries()) {
        await q(`insert into board_seats(board_id, kind, role, position, active) values ($1,'preset',$2,$3,true)`, [nb.id, r, i], c);
      }
      await syncSeats(nb.id, tier, c);
      const seat = (await one<SeatRow>(`select * from board_seats where board_id = $1 and role = $2`, [nb.id, b.role], c))!;
      await occupy(c, seat.id, u.id);
      await saveApplication(c, nb.id, u.id, seat, b, 'added');
      return { board: nb, a: await announce(c, nb, 'new_member', u.id, b.role) };
    });
    await broadcast(note.board, [note.a]);
    return { message: 'Committee board for your community has been created successfully.', role: b.role };
  });

  // CBM-05 / CBM-06: take an empty preset role, or apply for an activated extra or champion seat.
  app.post('/board/join', async (req) => {
    const u = await requireVerified(req);
    const b = answers.extend({ role: z.enum(PRESET_ROLES).optional(), seatId: z.string().uuid().optional() }).parse(req.body);
    const { board } = await requireBoard(u.id);
    if (await seatOf(u.id)) throw conflict('ALREADY_ON_BOARD', 'You already hold a seat on the board.');
    if (await one(`select 1 from board_applications where user_id = $1 and status = 'pending'`, [u.id])) {
      throw conflict('APPLICATION_PENDING', 'You already have an active application.');
    }
    const seat = b.role
      ? await one<SeatRow>(`select * from board_seats where board_id = $1 and kind = 'preset' and role = $2`, [board.id, b.role])
      : await one<SeatRow>(`select * from board_seats where board_id = $1 and id = $2 and kind <> 'preset'`, [board.id, b.seatId]);
    if (!seat) throw badRequest('VALIDATION', 'Choose a role to join.');
    if (seat.occupant_id || !seat.active || !withinAllowance(seat, board.tier)) throw conflict('SEAT_FILLED', 'This seat has just been filled. Please choose another role.');
    const size = (await committeeIds(board.id)).length;
    // Preset roles: first come, first served at any board size (CBM-05.2).
    // Extra and champion seats: a vote once the board has 5+ members; below 5 they join straight away (CBM-Q1 decided).
    if (seat.kind === 'preset' || size < VOTE_MIN_BOARD) {
      const note = await tx(async (c) => {
        if (!(await occupy(c, seat.id, u.id))) throw conflict('SEAT_FILLED', 'This seat has just been filled. Please choose another role.');
        await saveApplication(c, board.id, u.id, seat, b, 'added');
        await protectSeat(c, seat.id);
        return announce(c, board, 'new_member', u.id, seat.role);
      });
      await broadcast(board, [note]);
      return { status: 'added', role: seat.role, message: seat.kind === 'champion' ? 'You are now a champion on the board.' : 'You are now a member of the committee board.' };
    }
    const p = await tx(async (c) => {
      const a = await saveApplication(c, board.id, u.id, seat, b, 'pending');
      return (await one<{ id: string }>(
        `insert into proposals(board_id, type, application_id, subject_id, seat_id, creator_id, closes_at, created_at) values ($1,'join',$2,$3,$4,$3,$5,$6) returning id`,
        [board.id, a.id, u.id, seat.id, closesAt(), clock.now()], c,
      ))!;
    });
    const me = (await person(u.id))!;
    for (const m of await committeeIds(board.id)) await notify(m, 'proposal_created', u.id, { type: 'proposal', id: p.id }, { message: `${me.name} has requested to join the committee` });
    return {
      status: 'pending',
      proposalId: p.id,
      title: 'Application in review',
      message: 'Your application to join the committee board is now under review, you would get a feedback within the next 7 days.',
    };
  });

  // CBM-11: Chair activates or deactivates empty seats.
  app.get('/board/manage', async (req) => {
    const u = requireUser(req);
    const { board, seat } = await requireCommittee(u.id);
    if (seat.role !== 'Chair') throw forbidden('CHAIR_ONLY', 'Only the Chair can manage seats.');
    const all = await seats(board.id);
    const ps = await people(all.map((s) => s.occupant_id!).filter(Boolean));
    const presetFull = all.filter((s) => s.kind === 'preset').every((s) => s.occupant_id);
    const t = TIERS[board.tier - 1];
    const v = (s: SeatRow) => ({
      id: s.id, kind: s.kind, role: s.role, active: s.active, occupant: s.occupant_id ? ps.get(s.occupant_id) : null,
      canToggle: !s.occupant_id && s.kind !== 'preset' && withinAllowance(s, board.tier) && (s.kind !== 'champion' || board.tier > 1 || presetFull),
    });
    return {
      tier: board.tier,
      tierLabel: `Tier ${board.tier} · ${t.max === null ? `${t.min}+ residents` : `up to ${t.max + 1} residents`}`,
      presetRoles: all.filter((s) => s.kind === 'preset').map(v),
      additionalSeats: all.filter((s) => s.kind === 'extra' && withinAllowance(s, board.tier)).map(v),
      championSeats: all.filter((s) => s.kind === 'champion' && withinAllowance(s, board.tier)).map(v),
      championsLockedReason: board.tier === 1 && !presetFull ? 'Fill all 8 preset roles to activate champion seats.' : null,
    };
  });

  for (const action of ['activate', 'deactivate'] as const) {
    app.post(`/board/seats/:id/${action}`, async (req) => {
      const u = requireUser(req);
      const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
      const { board, seat: mine } = await requireCommittee(u.id);
      if (mine.role !== 'Chair') throw forbidden('CHAIR_ONLY', 'Only the Chair can manage seats.');
      const s = await one<SeatRow>('select * from board_seats where id = $1 and board_id = $2', [id, board.id]);
      if (!s || s.kind === 'preset') throw badRequest('PRESET_LOCKED', "Preset roles can't be edited.");
      if (s.occupant_id) throw conflict('SEAT_OCCUPIED', 'Occupied seats cannot be deactivated.');
      if (!withinAllowance(s, board.tier)) throw forbidden('TIER_LOCKED', 'This seat unlocks at a higher tier.');
      if (action === 'activate' && s.kind === 'champion' && board.tier === 1) {
        const empty = await one(`select 1 from board_seats where board_id = $1 and kind = 'preset' and occupant_id is null`, [board.id]);
        if (empty) throw forbidden('PRESET_NOT_FULL', 'Fill all 8 preset roles to activate champion seats.');
      }
      await tx(async (c) => {
        await q('update board_seats set active = $2 where id = $1', [id, action === 'activate'], c);
        if (action === 'deactivate') {
          const gone = await q<{ application_id: string }>(
            `update proposals set status = 'no_longer_applicable', closed_at = $2 where seat_id = $1 and type = 'join' and status = 'pending' returning application_id`,
            [id, clock.now()], c,
          );
          for (const g of gone) await q(`update board_applications set status = 'cancelled' where id = $1`, [g.application_id], c);
        }
      });
      return { ok: true, message: action === 'activate' ? 'Seat activated.' : 'Seat deactivated.' };
    });
  }

  // CBM-13 / CBM-14: exit with a reason; the Chair hands over.
  app.post('/board/exit', async (req) => {
    const u = requireUser(req);
    const { reason } = z.object({ reason: z.string().trim().min(1, 'Tell us why you want to exit the committee board').max(LONG) }).parse(req.body);
    if (!(await seatOf(u.id))) throw badRequest('NOT_ON_BOARD', 'You are not on the committee board.');
    const check = await exitCheck(u.id, 'deactivate');
    // EVT-27.1: stepping down is blocked while hosting an event with tickets taken.
    const blockers = check.blockers.filter((b) => b.code === 'EVENT_WITH_TICKETS');
    if (blockers.length) throw forbidden('EXIT_BLOCKED', blockers[0].message);
    await leaveBoard(u.id, { reason, why: 'exit' });
    return { title: 'Sad to see you leave!', message: "Your access in the community has been reverted to a resident's." };
  });

  // CBM-15 / CBM-16: reassign or remove proposals (board of 5+).
  app.post('/board/proposals', async (req) => {
    const u = requireUser(req);
    const b = z.object({
      type: z.enum(['reassign', 'remove']),
      subjectId: z.string().uuid(),
      seatId: z.string().uuid().optional(),
      reason: z.string().trim().min(1, 'Add a reason').max(LONG),
    }).parse(req.body);
    const { board } = await requireCommittee(u.id);
    if ((await committeeIds(board.id)).length < VOTE_MIN_BOARD) throw forbidden('BOARD_TOO_SMALL', 'Proposals are available when the board has 5 or more members.');
    const from = await one<SeatRow>('select * from board_seats where occupant_id = $1 and board_id = $2', [b.subjectId, board.id]);
    if (!from) throw badRequest('NOT_ON_BOARD', 'This person is not on the committee board.');
    if (b.type === 'remove' && b.subjectId === u.id) throw badRequest('USE_EXIT', 'Use Exit committee to leave the board.');
    let target: SeatRow | undefined;
    if (b.type === 'reassign') {
      if (from.kind === 'champion') throw badRequest('CHAMPION', 'Champions can only be removed.');
      target = await one<SeatRow>(`select * from board_seats where id = $1 and board_id = $2 and kind <> 'champion'`, [b.seatId, board.id]);
      if (!target || target.id === from.id) throw badRequest('VALIDATION', 'Choose the proposed role.', { field: 'seatId' });
      if (!target.occupant_id && (!target.active || !withinAllowance(target, board.tier))) throw badRequest('VALIDATION', 'This seat is not available.');
    }
    if (await one(`select 1 from proposals where subject_id = $1 and type = $2 and status = 'pending'`, [b.subjectId, b.type])) {
      throw conflict('PROPOSAL_OPEN', 'There is already an open proposal for this member.');
    }
    const p = await tx(async (c) => {
      const row = (await one<{ id: string }>(
        `insert into proposals(board_id, type, subject_id, seat_id, from_seat_id, swap_with_id, reason, creator_id, closes_at, created_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) returning id`,
        [board.id, b.type, b.subjectId, target?.id ?? null, from.id, target?.occupant_id ?? null, b.reason, u.id, closesAt(), clock.now()], c,
      ))!;
      // VOT-05.2: the creator's Yes is recorded automatically.
      await q(`insert into proposal_votes(proposal_id, voter_id, choice, created_at) values ($1,$2,'yes',$3)`, [row.id, u.id, clock.now()], c);
      return row;
    });
    const [me, subject] = [(await person(u.id))!, (await person(b.subjectId))!];
    const text = b.type === 'remove' ? `${me.name} has proposed to remove ${subject.name}` : `${me.name} has proposed to reassign ${b.subjectId === u.id ? 'their role' : subject.name}`;
    for (const m of await committeeIds(board.id)) await notify(m, 'proposal_created', u.id, { type: 'proposal', id: p.id }, { message: text });
    await evaluate(p.id);
    const message = b.type === 'remove'
      ? `Your request to remove ${subject.name} has been submitted and sent to the committee board for approval`
      : b.subjectId === u.id
        ? `Your request to reassign to the role of ${target!.role} has been submitted and sent to the committee board for approval`
        : `Your request to reassign ${subject.name} has been submitted and sent to the committee board for approval`;
    return { proposalId: p.id, message };
  });

  // VOT-01: committee members only; filter by status or "closes today".
  app.get('/board/proposals', async (req) => {
    const u = requireUser(req);
    const f = z.object({
      status: z.enum(['all', 'pending', 'awaiting_approval', 'approved', 'declined', 'added', 'no_longer_applicable']).default('all'),
      closesToday: z.enum(['1', 'true']).optional(),
    }).parse(req.query);
    const { board } = await requireCommittee(u.id);
    const rows = await q<any>('select * from proposals where board_id = $1 order by created_at desc', [board.id]);
    let list = await Promise.all(rows.map((p) => proposalView(p, u.id)));
    if (f.status !== 'all') list = list.filter((p) => p.status === f.status);
    if (f.closesToday) {
      const end = new Date(clock.now());
      end.setHours(23, 59, 59, 999);
      list = list.filter((p) => ['pending', 'awaiting_approval'].includes(p.status) && new Date(p.closesAt) <= end);
    }
    return { proposals: list };
  });

  app.get('/board/proposals/:id', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const { board } = await requireCommittee(u.id);
    const p = await one<any>('select * from proposals where id = $1 and board_id = $2', [id, board.id]);
    if (!p) throw notFound('This proposal is not available.');
    return { proposal: await proposalView(p, u.id, true) };
  });

  // VOT-02 - VOT-05: one vote per committee member; a reason is required for No on remove/reassign.
  app.post('/board/proposals/:id/vote', async (req) => {
    const u = requireUser(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const b = z.object({ choice: z.enum(['yes', 'no']), reason: z.string().trim().max(LONG).optional() }).parse(req.body);
    const { board } = await requireCommittee(u.id);
    const p = await one<any>('select * from proposals where id = $1 and board_id = $2', [id, board.id]);
    if (!p) throw notFound('This proposal is not available.');
    if (p.status !== 'pending') throw conflict('PROPOSAL_CLOSED', 'Voting on this proposal has closed.');
    if (!(await eligibleVoters(p)).includes(u.id)) throw forbidden('CANNOT_VOTE', 'You cannot vote on this proposal.');
    if (b.choice === 'no' && p.type !== 'join' && !b.reason) throw badRequest('REASON_REQUIRED', 'Tell us why you voted no', { field: 'reason' });
    const r = await one(
      `insert into proposal_votes(proposal_id, voter_id, choice, reason, created_at) values ($1,$2,$3,$4,$5) on conflict do nothing returning 1`,
      [id, u.id, b.choice, b.reason ?? null, clock.now()],
    );
    if (!r) throw conflict('ALREADY_VOTED', 'Already voted');
    await evaluate(id);
    return { proposal: await proposalView(await one('select * from proposals where id = $1', [id]), u.id, true) };
  });

  // CBM-07: board invite link.
  app.get('/board/invite', async (req) => {
    const u = requireUser(req);
    const { communityId } = await requireCommittee(u.id);
    const c = (await one<{ code: string; name: string }>('select code, name from communities where id = $1', [communityId]))!;
    const link = shareLink('board', c.code);
    return { link, message: `You've been invited to join the Committee Board of ${c.name} on Keys. ${link}` };
  });
  app.get('/board/invite/:code', async (req) => {
    const u = requireUser(req);
    const { code } = z.object({ code: z.string() }).parse(req.params);
    const c = await one<{ id: string; name: string }>('select id, name from communities where code = $1', [code.toUpperCase()]);
    if (!c || c.id !== (await communityOf(u.id))) throw notFound('This invite is not available.');
    const board = await boardFor(c.id);
    const free = board ? (await seats(board.id)).filter((s) => !s.occupant_id && s.active && withinAllowance(s, board.tier)) : [];
    return {
      title: `You've been invited to join the Committee Board of ${c.name}`,
      duties: ['Manage community services and projects', 'Be the voice of residents', 'Vote on committee proposals'],
      next: !board ? 'create' : free.some((s) => s.kind === 'preset') ? 'join_preset' : free.length ? 'apply' : 'full',
    };
  });
}

export { leaveBoard };
