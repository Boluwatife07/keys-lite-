-- Milestone 3: committee board (CBM) and voting (VOT).

alter table boards add column tier int not null default 1;
alter table boards add column tier_up_at timestamptz;

-- Questionnaire answers for every join, application or board creation (CBM-04 - CBM-06).
create table board_applications (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  seat_id uuid references board_seats(id) on delete set null,
  role text not null,
  pledged_at timestamptz not null,
  has_leadership boolean not null,
  leadership_title text,
  leadership_description text,
  qualified text not null,
  aim text not null,
  status text not null check (status in ('pending', 'added', 'declined', 'cancelled')),
  created_at timestamptz not null default now()
);
-- CBM-19.1: one pending application per resident.
create unique index one_pending_application on board_applications(user_id) where status = 'pending';

create table proposals (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  type text not null check (type in ('join', 'reassign', 'remove')),
  application_id uuid references board_applications(id) on delete set null,
  subject_id uuid not null references users(id) on delete cascade,
  seat_id uuid references board_seats(id) on delete set null,          -- join: seat applied for; reassign: target seat
  from_seat_id uuid references board_seats(id) on delete set null,     -- reassign/remove: subject's seat when proposed
  swap_with_id uuid references users(id) on delete set null,           -- reassign into a filled seat
  proposed_role text,
  reason text,
  creator_id uuid not null references users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'no_longer_applicable')),
  outcome_note text,                                                   -- e.g. NEW_SEAT_PROTECTION
  closes_at timestamptz not null,
  closed_at timestamptz,
  reminded_at timestamptz,
  created_at timestamptz not null default now()
);
create index proposals_board on proposals(board_id, created_at desc);

create table proposal_votes (
  proposal_id uuid not null references proposals(id) on delete cascade,
  voter_id uuid not null references users(id) on delete cascade,
  choice text not null check (choice in ('yes', 'no')),
  reason text,
  created_at timestamptz not null default now(),
  primary key (proposal_id, voter_id)
);

-- CBM-18: board change cards on the Community hub.
create table board_announcements (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  type text not null check (type in ('new_member', 'role_change', 'board_exit', 'member_removal')),
  subject_id uuid references users(id) on delete set null,
  role text,
  text text not null,
  reason text,
  created_at timestamptz not null default now()
);
create index board_announcements_board on board_announcements(board_id, created_at desc);
