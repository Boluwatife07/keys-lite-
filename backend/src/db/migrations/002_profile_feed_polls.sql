-- Milestone 2: profile & settings, feed, polls. Committee tables are created
-- here so role labels and committee-only checks work; board logic is milestone 3.

alter table email_codes drop constraint email_codes_purpose_check;
alter table email_codes add constraint email_codes_purpose_check
  check (purpose in ('signup', 'reset', 'change_email', 'create_password'));
alter table email_codes add column new_email citext;

-- Committee board (CBM). Seats: 8 preset roles plus tier-unlocked extra and champion seats.
create table boards (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null unique references communities(id) on delete cascade,
  created_at timestamptz not null default now()
);
create type seat_kind as enum ('preset', 'extra', 'champion');
create table board_seats (
  id uuid primary key default gen_random_uuid(),
  board_id uuid not null references boards(id) on delete cascade,
  kind seat_kind not null,
  role text not null,                 -- preset role name, 'Committee Member' or 'Champion'
  position int not null,
  active boolean not null default true,
  occupant_id uuid references users(id) on delete set null,
  occupied_at timestamptz,
  created_at timestamptz not null default now(),
  unique (board_id, kind, position)
);
-- A resident holds at most one seat.
create unique index one_seat_per_user on board_seats(occupant_id) where occupant_id is not null;

-- Safety (PRF-04, PRF-05).
create table mutes (
  user_id uuid not null references users(id) on delete cascade,
  target_id uuid not null references users(id) on delete cascade,
  until timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (user_id, target_id)
);
create table blocks (
  user_id uuid not null references users(id) on delete cascade,
  target_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, target_id)
);

create table notification_prefs (
  user_id uuid not null references users(id) on delete cascade,
  key text not null,
  enabled boolean not null,
  primary key (user_id, key)
);
create table push_tokens (
  token text primary key,
  user_id uuid not null references users(id) on delete cascade,
  platform text,
  created_at timestamptz not null default now()
);
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null,
  actor_id uuid references users(id) on delete cascade,
  item_type text,
  item_id uuid,
  data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_user on notifications(user_id, created_at desc);

-- Feed (FED). A poll is a post with kind = 'poll'.
create table posts (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  author_id uuid not null references users(id) on delete cascade,
  kind text not null default 'post' check (kind in ('post', 'poll')),
  text text not null default '',
  attachment text not null default 'none' check (attachment in ('none', 'photos', 'video', 'document', 'link')),
  document_media_id uuid references media(id),
  document_title text,
  document_pages int,
  document_downloads int not null default 0,
  link_url text,
  link_title text,
  link_description text,
  link_image text,
  status text not null default 'live' check (status in ('live', 'deleted', 'removed')),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);
create index posts_feed on posts(community_id, created_at desc, id desc) where status = 'live';
create index posts_author on posts(author_id, created_at desc);

create table post_media (
  post_id uuid not null references posts(id) on delete cascade,
  media_id uuid not null references media(id),
  position int not null,
  primary key (post_id, position)
);

create table comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  parent_id uuid references comments(id) on delete cascade,  -- replies are one level deep
  author_id uuid not null references users(id) on delete cascade,
  text text not null default '',
  media_id uuid references media(id),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);
create index comments_post on comments(post_id, created_at);
create index comments_parent on comments(parent_id, created_at);

create table mentions (
  id bigserial primary key,
  post_id uuid references posts(id) on delete cascade,
  comment_id uuid references comments(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade
);
create index mentions_post on mentions(post_id);
create index mentions_comment on mentions(comment_id);

create table likes (
  item_type text not null check (item_type in ('post', 'comment')),
  item_id uuid not null,
  user_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (item_type, item_id, user_id)
);

-- Polls (POL).
create table polls (
  post_id uuid primary key references posts(id) on delete cascade,
  question text not null,
  promise text,
  multi boolean not null default false,
  duration text not null check (duration in ('24h', '48h', '7d', '2w')),
  closes_at timestamptz not null,
  closed_notified_at timestamptz
);
create table poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references polls(post_id) on delete cascade,
  position int not null,
  text text not null,
  media_id uuid references media(id),
  unique (post_id, position)
);
create table poll_votes (
  post_id uuid not null references polls(post_id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  option_ids uuid[] not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
