-- My Hostel – Phase 1 schema
-- Tables for owners, hostels, rooms, beds, tenants (bookings), bills, payments,
-- student sessions (no-login access), OTP codes and owner notifications.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.hostel_type   as enum ('mens', 'womens', 'coliving');
create type public.rent_day_mode as enum ('joining_date', 'fixed_day');
create type public.bed_status    as enum ('vacant', 'held', 'occupied', 'offline_occupied');
create type public.tenant_status as enum (
  'draft',             -- bed held, details not yet sent
  'awaiting_payment',  -- details sent, payment not yet sent (new joiner)
  'pending_approval',  -- payment sent (new joiner) or existing tenant waiting for owner
  'active',
  'notice',            -- gave notice to leave
  'vacated',
  'rejected',
  'expired'            -- bed hold ran out before finishing
);
create type public.id_type     as enum ('aadhaar', 'passport', 'driving_licence');
create type public.pay_method  as enum ('upi', 'bank', 'cash', 'cheque', 'online');
create type public.pay_status  as enum ('pending', 'received', 'rejected');
create type public.bill_kind   as enum ('rent', 'deposit', 'other');
create type public.bill_status as enum ('unpaid', 'partial', 'paid', 'cancelled');

-- ---------------------------------------------------------------------------
-- Private settings (never exposed through the API)
-- ---------------------------------------------------------------------------
create table private.settings (
  name  text primary key,
  value text not null
);
-- The ID-number encryption key is set during setup (see README):
-- insert into private.settings values ('id_encryption_key', '<long random secret>');

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function private.gen_join_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no 0/O/1/I
  bytes bytea := extensions.gen_random_bytes(8);
  code text := '';
  i int;
begin
  for i in 0..7 loop
    code := code || substr(alphabet, (get_byte(bytes, i) % length(alphabet)) + 1, 1);
  end loop;
  return code;
end;
$$;

-- ---------------------------------------------------------------------------
-- Owners
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  full_name           text not null default '' check (length(full_name) <= 120),
  phone               text,
  language            text not null default 'en' check (language in ('en', 'hi', 'te', 'ta', 'mr', 'kn', 'bn')),
  delete_requested_at timestamptz,
  created_at          timestamptz not null default now()
);

-- Create a profile automatically when an owner signs up (phone + password).
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, language)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone,
    coalesce(nullif(new.raw_user_meta_data ->> 'language', ''), 'en')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------------------
-- Hostels
-- ---------------------------------------------------------------------------
create table public.hostels (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles (id) on delete cascade,
  name            text not null check (length(trim(name)) between 2 and 120),
  type            public.hostel_type not null,
  address         text not null check (length(trim(address)) between 5 and 300),
  city            text not null check (length(trim(city)) between 2 and 80),
  pincode         text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  contact_phone   text not null check (contact_phone ~ '^\+91[6-9][0-9]{9}$'),
  floors          int  not null default 1 check (floors between 1 and 50),
  join_code       text not null unique default private.gen_join_code(),
  is_open         boolean not null default true,
  -- rent rules
  rent_day_mode   public.rent_day_mode not null default 'fixed_day',
  rent_fixed_day  int  not null default 5 check (rent_fixed_day between 1 and 28),
  notice_days     int  not null default 15 check (notice_days between 0 and 90),
  -- payment options
  accept_upi      boolean not null default true,
  upi_id          text check (upi_id is null or upi_id ~ '^[A-Za-z0-9._-]{2,128}@[A-Za-z]{2,64}$'),
  upi_payee_name  text,
  accept_bank     boolean not null default false,
  bank_details    text,
  accept_cash     boolean not null default true,
  cash_note       text,
  -- shown to students
  amenities       text[] not null default '{}',
  house_rules     text,
  created_at      timestamptz not null default now()
);
create index hostels_owner_idx on public.hostels (owner_id);

-- ---------------------------------------------------------------------------
-- Rooms and beds
-- ---------------------------------------------------------------------------
create table public.rooms (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels (id) on delete cascade,
  room_no        text not null check (length(trim(room_no)) between 1 and 20),
  floor          int  not null default 0 check (floor between 0 and 50),
  sharing        int  not null check (sharing between 1 and 6),
  rent_month     int  not null check (rent_month > 0 and rent_month <= 500000),
  deposit_month  int  not null default 0 check (deposit_month >= 0 and deposit_month <= 1000000),
  features       text[] not null default '{}',
  separate_meter boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (hostel_id, room_no)
);
create index rooms_hostel_idx on public.rooms (hostel_id);

create table public.beds (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  hostel_id   uuid not null references public.hostels (id) on delete cascade,
  label       text not null,
  status      public.bed_status not null default 'vacant',
  held_until  timestamptz,
  held_for    uuid,               -- tenant id holding the bed
  created_at  timestamptz not null default now(),
  unique (room_id, label)
);
create index beds_hostel_idx on public.beds (hostel_id);

-- ---------------------------------------------------------------------------
-- Tenants (one row per stay / booking)
-- ---------------------------------------------------------------------------
create table public.tenants (
  id               uuid primary key default gen_random_uuid(),
  hostel_id        uuid not null references public.hostels (id) on delete cascade,
  bed_id           uuid references public.beds (id) on delete set null,
  phone            text not null check (phone ~ '^\+91[6-9][0-9]{9}$'),
  full_name        text check (full_name is null or length(trim(full_name)) between 2 and 120),
  parent_phone     text check (parent_phone is null or parent_phone ~ '^\+91[6-9][0-9]{9}$'),
  reference_phone  text check (reference_phone is null or reference_phone ~ '^\+91[6-9][0-9]{9}$'),
  id_type          public.id_type,
  id_number_enc    bytea,          -- encrypted with pgcrypto; never returned to the app
  id_last4         text,
  id_file_key      text,           -- object key in the private R2 bucket
  photo_key        text,
  home_address     text,
  office_address   text,
  joining_date     date,
  is_existing      boolean not null default false,
  stay_type        text not null default 'monthly' check (stay_type in ('monthly', 'daywise')),
  rent_month       int,            -- copied from the room when the bed is held
  deposit          int,
  status           public.tenant_status not null default 'draft',
  consent_at       timestamptz,
  notice_given_at  timestamptz,
  leaving_date     date,
  vacated_at       timestamptz,
  deposit_deduction int,
  deposit_refund   int,
  files_purged_at  timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index tenants_hostel_idx on public.tenants (hostel_id, status);
create index tenants_phone_idx on public.tenants (phone);
-- one live booking per phone per hostel
create unique index tenants_one_live_per_phone
  on public.tenants (hostel_id, phone)
  where status not in ('vacated', 'rejected', 'expired');

-- ---------------------------------------------------------------------------
-- Student access (no login): sessions created after OTP verification
-- ---------------------------------------------------------------------------
create table public.student_sessions (
  id           uuid primary key default gen_random_uuid(),
  hostel_id    uuid not null references public.hostels (id) on delete cascade,
  phone        text not null,
  tenant_id    uuid references public.tenants (id) on delete cascade,
  token_hash   text not null unique,      -- sha256 of the token; the token itself is never stored
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at   timestamptz
);
create index student_sessions_tenant_idx on public.student_sessions (tenant_id);

create table public.otp_codes (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  purpose     text not null,             -- e.g. 'join:<hostel_id>'
  code_hash   text not null,
  expires_at  timestamptz not null,
  attempts    int not null default 0,
  consumed_at timestamptz,
  created_at  timestamptz not null default now()
);
create index otp_codes_phone_idx on public.otp_codes (phone, created_at desc);

-- ---------------------------------------------------------------------------
-- Money: bills (what is owed) and payments (what was paid)
-- ---------------------------------------------------------------------------
create table public.bills (
  id           uuid primary key default gen_random_uuid(),
  hostel_id    uuid not null references public.hostels (id) on delete cascade,
  tenant_id    uuid not null references public.tenants (id) on delete cascade,
  kind         public.bill_kind not null,
  label        text not null,
  period_start date,
  period_end   date,
  amount       int  not null check (amount >= 0),
  paid_amount  int  not null default 0 check (paid_amount >= 0),
  due_date     date not null,
  status       public.bill_status not null default 'unpaid',
  created_at   timestamptz not null default now()
);
create index bills_tenant_idx on public.bills (tenant_id, due_date);
create index bills_hostel_idx on public.bills (hostel_id, due_date);
create unique index bills_one_rent_per_period on public.bills (tenant_id, period_start) where kind = 'rent';

create table public.payments (
  id              uuid primary key default gen_random_uuid(),
  hostel_id       uuid not null references public.hostels (id) on delete cascade,
  tenant_id       uuid not null references public.tenants (id) on delete cascade,
  method          public.pay_method not null,
  amount_claimed  int  not null check (amount_claimed > 0),
  amount_received int  check (amount_received is null or amount_received >= 0),
  utr             text check (utr is null or utr ~ '^[A-Za-z0-9]{6,30}$'),
  payment_note    text,              -- e.g. RPH-204B-1005, filled into the UPI app
  paid_on         date not null default current_date,
  status          public.pay_status not null default 'pending',
  note            text,
  created_by      text not null check (created_by in ('student', 'owner')),
  recorded_by     uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  decided_at      timestamptz
);
create index payments_hostel_idx on public.payments (hostel_id, status, created_at desc);
create index payments_tenant_idx on public.payments (tenant_id);
-- the same UTR can't be used twice at one hostel
create unique index payments_unique_utr on public.payments (hostel_id, upper(utr))
  where utr is not null and status <> 'rejected';

-- ---------------------------------------------------------------------------
-- Owner notifications and audit
-- ---------------------------------------------------------------------------
create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  hostel_id  uuid not null references public.hostels (id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text,
  ref_id     uuid,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_hostel_idx on public.notifications (hostel_id, created_at desc);

create table public.id_reveal_log (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   uuid not null references public.tenants (id) on delete cascade,
  revealed_by uuid not null references public.profiles (id) on delete cascade,
  revealed_at timestamptz not null default now()
);

-- keep tenants.updated_at fresh
create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger tenants_touch before update on public.tenants
  for each row execute function private.touch_updated_at();

-- Balance per tenant (what is due today vs. what was received)
create view public.tenant_balances
with (security_invoker = true) as
select
  t.id as tenant_id,
  t.hostel_id,
  coalesce((select sum(b.amount) from public.bills b
            where b.tenant_id = t.id and b.status <> 'cancelled' and b.due_date <= current_date), 0)::int as due_till_today,
  coalesce((select sum(b.amount) from public.bills b
            where b.tenant_id = t.id and b.status <> 'cancelled'), 0)::int as billed_total,
  coalesce((select sum(p.amount_received) from public.payments p
            where p.tenant_id = t.id and p.status = 'received'), 0)::int as received_total
from public.tenants t;
