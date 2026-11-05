-- Milestone 5: Free events (EVT), Free clubs (CLB) and Calendar (CAL).

-- ---------------------------------------------------------------- clubs
create table clubs (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  name text not null,
  description text not null default '',
  category text not null,
  member_limit int not null check (member_limit >= 10),
  cover_media_id uuid references media(id),
  president_id uuid references users(id) on delete set null,
  status text not null default 'active' check (status in ('active', 'closing', 'closed')),
  closing_at timestamptz,
  closed_at timestamptz,
  chat_id uuid references chats(id) on delete set null,
  full_notified_at timestamptz,
  attempts_notified_at timestamptz,
  milestones int[] not null default '{}',
  created_at timestamptz not null default now()
);
-- CLB-03.3: names are unique within a community (closed clubs free the name).
create unique index clubs_name_unique on clubs(community_id, lower(name)) where status <> 'closed';

create table club_members (
  club_id uuid not null references clubs(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  role text not null default 'member' check (role in ('president', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  muted_until timestamptz,
  primary key (club_id, user_id)
);
create index club_members_user on club_members(user_id);

-- CLB-06.3: people who tried to join while the club was full.
create table club_join_attempts (
  club_id uuid not null references clubs(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  attempted_at timestamptz not null,
  primary key (club_id, user_id)
);

create table club_invites (
  club_id uuid not null references clubs(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  invited_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

create table club_transfers (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs(id) on delete cascade,
  from_id uuid not null references users(id) on delete cascade,
  to_id uuid not null references users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

-- CLB-13: club announcements are posts with a club and an audience.
alter table posts add column club_id uuid references clubs(id) on delete cascade;
alter table posts add column club_audience text check (club_audience in ('all', 'members'));
create index posts_club on posts(club_id, created_at desc) where club_id is not null;

-- ---------------------------------------------------------------- events
create table events (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  host_id uuid references users(id) on delete set null,
  category text not null check (category in ('residential', 'administrative', 'club')),
  club_id uuid references clubs(id) on delete cascade,
  audience text not null default 'all' check (audience in ('all', 'members')),
  title text not null default '',
  description text not null default '',
  start_at timestamptz,
  end_at timestamptz,
  format text check (format in ('physical', 'online')),
  location_place_id text,
  location_name text,
  location_address text,
  lat double precision,
  lng double precision,
  platform text check (platform in ('zoom', 'google_meet', 'facebook_live', 'other')),
  link text,
  meeting_id text,
  meeting_password text,
  tags text[] not null default '{}',
  capacity int check (capacity is null or capacity >= 10),
  accept_volunteers boolean not null default false,
  volunteer_cap int check (volunteer_cap is null or volunteer_cap >= 1),
  status text not null default 'draft' check (status in ('draft', 'live', 'cancelled')),
  cancel_reason text,
  cancel_text text,
  chat_id uuid references chats(id) on delete set null,
  launched_at timestamptz,
  cancelled_at timestamptz,
  reminder_sent_at timestamptz,
  draft_reminder_at timestamptz,
  completed_notified_at timestamptz,
  feedback_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index events_community on events(community_id, start_at);

create table event_media (
  event_id uuid not null references events(id) on delete cascade,
  media_id uuid not null references media(id),
  position int not null,
  primary key (event_id, position)
);

create table event_guests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  name text not null,
  title text not null default '',
  photo_media_id uuid references media(id),
  position int not null
);

-- EVT-09: residents (invited until they accept) or external names.
create table event_cohosts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  user_id uuid references users(id) on delete cascade,
  external_name text,
  status text not null default 'invited' check (status in ('invited', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check ((user_id is null) <> (external_name is null))
);
create unique index event_cohosts_user on event_cohosts(event_id, user_id) where user_id is not null;

create table event_volunteers (
  event_id uuid not null references events(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'left', 'removed')),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table tickets (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  seat int not null,
  code text not null unique,
  status text not null default 'active' check (status in ('active', 'cancelled', 'void')),
  checked_in_at timestamptz,
  checked_in_by uuid references users(id) on delete set null,
  cancel_seen_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index tickets_one_active on tickets(event_id, user_id) where status = 'active';
create index tickets_user on tickets(user_id);

create table event_saves (
  user_id uuid not null references users(id) on delete cascade,
  event_id uuid not null references events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

-- EVT-24: one rating per person. stars null = the prompt was dismissed.
create table event_ratings (
  event_id uuid not null references events(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  stars int check (stars between 1 and 5),
  text text not null default '',
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

-- EVT-11.4: personal templates saved at launch.
create table event_templates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  data jsonb not null,
  created_at timestamptz not null default now()
);
