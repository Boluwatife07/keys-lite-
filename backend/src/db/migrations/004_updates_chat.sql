-- Milestone 4: Updates (UPD), update group chat (UCH) and Chat (CHT).

alter table media drop constraint media_kind_check;
alter table media add constraint media_kind_check check (kind in ('photo', 'video', 'document', 'audio'));

-- ---------------------------------------------------------------- chat
create table chats (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  type text not null check (type in ('direct', 'group', 'update', 'club', 'event', 'services', 'volunteering')),
  name text,
  description text,
  icon_url text,
  created_by uuid references users(id) on delete set null,
  -- direct chats: message request state (CHT-04)
  requester_id uuid references users(id) on delete set null,
  accepted_at timestamptz,
  -- group settings (CHT-12)
  members_can_message boolean not null default true,
  members_can_invite boolean not null default true,
  approval_required boolean not null default false,
  committee_only boolean not null default false,
  invite_code text unique,
  read_only boolean not null default false,          -- update chats after resolve/delete (UCH-04.1)
  update_id uuid,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index chats_community on chats(community_id);

create table chat_members (
  chat_id uuid not null references chats(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  left_reason text check (left_reason in ('left', 'removed')),
  muted_until timestamptz,                           -- 'infinity' = till I unmute
  pinned_at timestamptz,
  cleared_at timestamptz,                            -- clear chat for me (CHT-10.2)
  hidden_at timestamptz,                             -- delete chat for me (CHT-02.5); new messages bring it back
  request_deleted_at timestamptz,                    -- recipient deleted a message request (CHT-04.4)
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (chat_id, user_id)
);
create index chat_members_user on chat_members(user_id) where left_at is null;

create table messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references chats(id) on delete cascade,
  sender_id uuid references users(id) on delete set null,      -- null = system message
  kind text not null check (kind in ('text', 'media', 'document', 'voice', 'system')),
  text text not null default '',
  media_ids uuid[] not null default '{}',
  link jsonb,
  reply_to_id uuid references messages(id) on delete set null,
  forwarded boolean not null default false,
  system jsonb,
  hidden_from uuid[] not null default '{}',                    -- e.g. a recipient who blocked the sender (CHT-05.5)
  deleted_for_all_at timestamptz,
  created_at timestamptz not null default now()
);
create index messages_chat on messages(chat_id, created_at desc);
create index messages_text on messages using gin (to_tsvector('simple', text));

create table message_hidden (
  message_id uuid not null references messages(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  primary key (message_id, user_id)
);
create table message_reactions (
  message_id uuid not null references messages(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create table chat_join_requests (
  chat_id uuid not null references chats(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  added_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);

-- ---------------------------------------------------------------- updates
create table updates (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references communities(id) on delete cascade,
  author_id uuid not null references users(id) on delete cascade,
  title text not null,
  details text not null,
  audience text not null default 'all' check (audience in ('all', 'sub')),
  document_media_id uuid references media(id),
  document_downloads int not null default 0,
  chat_id uuid references chats(id) on delete set null,
  status text not null default 'live' check (status in ('live', 'resolved', 'deleted', 'removed')),
  resolved_at timestamptz,
  resolved_by uuid references users(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);
create index updates_community on updates(community_id, created_at desc);
alter table chats add constraint chats_update_fk foreign key (update_id) references updates(id) on delete set null;

-- Sub-community audience: streets of the community and its buildings (UPD-03).
create table update_targets (
  update_id uuid not null references updates(id) on delete cascade,
  street_id uuid references streets(id),
  building_id uuid references communities(id),
  check ((street_id is null) <> (building_id is null))
);
create index update_targets_update on update_targets(update_id);

create table update_media (
  update_id uuid not null references updates(id) on delete cascade,
  media_id uuid not null references media(id),
  position int not null,
  primary key (update_id, position)
);

create table additional_updates (
  id uuid primary key default gen_random_uuid(),
  update_id uuid not null references updates(id) on delete cascade,
  author_id uuid not null references users(id) on delete cascade,
  text text not null default '',
  media_id uuid references media(id),
  mention_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);
create index additional_updates_update on additional_updates(update_id, created_at);

create table update_pins (user_id uuid not null references users(id) on delete cascade, update_id uuid not null references updates(id) on delete cascade, created_at timestamptz not null default now(), primary key (user_id, update_id));
create table update_mutes (user_id uuid not null references users(id) on delete cascade, update_id uuid not null references updates(id) on delete cascade, until timestamptz not null, primary key (user_id, update_id));
create table update_hides (user_id uuid not null references users(id) on delete cascade, update_id uuid not null references updates(id) on delete cascade, primary key (user_id, update_id));
create table update_reads (user_id uuid not null references users(id) on delete cascade, update_id uuid not null references updates(id) on delete cascade, seen_at timestamptz not null, primary key (user_id, update_id));
