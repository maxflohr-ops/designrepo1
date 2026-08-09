-- Bounty Sounds — initial schema.
-- Money is never a column on a business object: balances are derived from
-- ledger_entry exclusively. bounty.purse_cents is the funded amount, not a
-- running balance.

create extension if not exists pgcrypto;

-- identity ------------------------------------------------------------------

create table account (
  id              uuid primary key default gen_random_uuid(),
  tiktok_open_id  text not null unique,
  handle          text not null,
  roles           text[] not null default '{clipper}',
  payout_method_id text,
  kyc_state       text not null default 'none',
  trust_score     int  not null default 50,
  suspended_at    timestamptz,
  created_at      timestamptz not null default now()
);

create table session (
  token       text primary key,
  account_id  uuid not null references account(id),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);

create table device_push_token (
  account_id uuid not null references account(id),
  token      text not null,
  platform   text not null default 'apns',
  created_at timestamptz not null default now(),
  primary key (account_id, token)
);

-- bounties ------------------------------------------------------------------

create table sound (
  id                uuid primary key default gen_random_uuid(),
  tiktok_music_id   text not null unique,
  title             text not null,
  artist_account_id uuid references account(id),
  isrc              text,
  verified_at       timestamptz
);

create sequence bounty_serial_seq start 131;

create table bounty (
  id            uuid primary key default gen_random_uuid(),
  serial        text not null unique default 'B ' || lpad(nextval('bounty_serial_seq')::text, 8, '0'),
  sound_id      uuid not null references sound(id),
  artist_account_id uuid not null references account(id),
  title         text not null,
  brief         text not null default '',
  payout_model  text not null check (payout_model in ('per_view','per_clip')),
  rate_cents    int  not null check (rate_cents > 0),
  rate_unit     int  not null default 1,          -- views per rate_cents for per_view; 1 for per_clip
  purse_cents   bigint not null check (purse_cents > 0),  -- funded amount (incl. top-ups), never a balance
  slot_cap      int  not null default 12,
  window_days   int  not null default 14,          -- counting window; per-platform config, Shorts deferred to v2
  platform      text not null default 'tiktok',
  deadline_at   timestamptz not null,
  state         text not null default 'draft'
                check (state in ('draft','funding','live','closing','settled','cancelled','frozen')),
  stripe_payment_intent_id text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table claim (
  id          uuid primary key default gen_random_uuid(),
  bounty_id   uuid not null references bounty(id),
  account_id  uuid not null references account(id),
  claimed_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  checklist   jsonb not null default '[false,false,false,false]',
  state       text not null default 'open' check (state in ('open','submitted','settled','expired'))
);
-- one live claim per clipper per bounty
create unique index claim_open_uniq on claim (bounty_id, account_id) where state = 'open';

create table submission (
  id              uuid primary key default gen_random_uuid(),
  claim_id        uuid not null unique references claim(id),
  tiktok_video_id text not null,
  posted_at       timestamptz not null,
  window_ends_at  timestamptz not null,
  checks          jsonb not null default '{}',
  state           text not null default 'pending_checks'
                  check (state in ('pending_checks','counting','payable','paid','held','void','rejected')),
  held_reason     text,
  accrued_cents   bigint not null default 0,   -- clipper portion reserved so far (cache of ledger; ledger is truth)
  next_poll_at    timestamptz,
  degrade_next    boolean not null default false,
  artist_approved boolean not null default false,
  created_at      timestamptz not null default now()
);
create index submission_poll_idx on submission (next_poll_at) where state in ('counting','held');

create table view_sample (
  id             bigint generated always as identity primary key,
  submission_id  uuid not null references submission(id),
  sampled_at     timestamptz not null default now(),
  view_count     bigint not null,
  source         text not null default 'tiktok_display_api',
  delta          bigint not null,
  anomaly_flags  text[] not null default '{}'
);
create index view_sample_sub_idx on view_sample (submission_id, sampled_at);
-- append only
create rule view_sample_no_update as on update to view_sample do instead nothing;
create rule view_sample_no_delete as on delete to view_sample do instead nothing;

create table dispute (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null references submission(id),
  opened_by     uuid not null references account(id),
  reason_code   text not null,
  statement     text not null default '',
  evidence      jsonb not null default '[]',
  state         text not null default 'open' check (state in ('open','appealed','resolved')),
  appeal_statement text,
  appeal_deadline  timestamptz,          -- 72h SLA clock, starts at appeal
  resolved_at   timestamptz,
  resolution    text check (resolution in ('clipper','artist')),
  created_at    timestamptz not null default now()
);

-- treasury ------------------------------------------------------------------

-- Double-entry, append-only. Entries in one txn_id must balance:
-- sum(credit amounts) == sum(debit amounts). Balance of an account_ref is
-- credits minus debits. Enforced by trigger below.
create table ledger_entry (
  id            bigint generated always as identity primary key,
  txn_id        uuid not null,
  account_ref   text not null,
  direction     text not null check (direction in ('debit','credit')),
  amount_cents  bigint not null check (amount_cents > 0),
  kind          text not null check (kind in (
                  'purse_fund','accrual_reserve','release_reserve','payout_clear',
                  'cash_out','refund','chargeback')),
  bounty_id     uuid references bounty(id),
  submission_id uuid references submission(id),
  created_at    timestamptz not null default now()
);
create index ledger_ref_idx on ledger_entry (account_ref);
create index ledger_txn_idx on ledger_entry (txn_id);
create index ledger_bounty_idx on ledger_entry (bounty_id);
create rule ledger_no_update as on update to ledger_entry do instead nothing;
create rule ledger_no_delete as on delete to ledger_entry do instead nothing;

-- Deferred per-transaction zero-sum check: at commit, every txn_id present in
-- this database must balance.
create or replace function ledger_txn_balanced() returns trigger as $$
declare bad uuid;
begin
  select txn_id into bad from ledger_entry
    where txn_id = new.txn_id
    group by txn_id
    having sum(case direction when 'credit' then amount_cents else -amount_cents end) <> 0;
  if bad is not null then
    raise exception 'ledger txn % does not balance', bad;
  end if;
  return null;
end $$ language plpgsql;

create constraint trigger ledger_balanced
  after insert on ledger_entry
  deferrable initially deferred
  for each row execute function ledger_txn_balanced();

create table idempotency_key (
  key            text not null,
  account_id     uuid not null,
  endpoint       text not null,
  request_hash   text not null,
  response_status int,
  response_body  jsonb,
  created_at     timestamptz not null default now(),
  primary key (key, account_id)
);

-- notify --------------------------------------------------------------------

create table wire_item (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references account(id),
  body        text not null,
  tone        text not null default 'info' check (tone in ('money','warn','info')),
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index wire_account_idx on wire_item (account_id, created_at desc);
