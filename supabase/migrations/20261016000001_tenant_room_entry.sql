-- Phase 1 only: rooms entered by tenants.
-- Owners don't want to type every floor / room / sharing / price at the start, so each student who
-- scans the hostel QR types their own floor, room number, sharing, monthly price and deposit in
-- "Your details". The room is created (unconfirmed) from what they typed and a bed in it is held
-- for them, so the rest of the flow (uploads, payment, approval) works unchanged.
-- The owner checks everything in "Rooms from tenants" (More) and "Price by sharing" (Hostel settings),
-- corrects wrong entries himself (students are not told) and confirms. Confirmed rooms are normal rooms.
-- Turn it off per hostel (hostels.tenant_room_entry) once all rooms are set; remove in Phase 2/3.

alter table public.hostels add column if not exists tenant_room_entry boolean not null default true;
alter table public.hostels add column if not exists use_tenant_prices boolean not null default true;

-- rooms the owner added are confirmed; rooms made from a tenant's entry start unconfirmed
alter table public.rooms add column if not exists confirmed    boolean not null default true;
alter table public.rooms add column if not exists from_tenants boolean not null default false;

-- What each student typed (kept as typed; the owner's corrections go to the room itself).
create table if not exists public.tenant_room_entries (
  id          uuid primary key default gen_random_uuid(),
  hostel_id   uuid not null references public.hostels (id) on delete cascade,
  tenant_id   uuid not null unique references public.tenants (id) on delete cascade,
  room_id     uuid references public.rooms (id) on delete cascade,
  room_no     text not null check (length(trim(room_no)) between 1 and 20),
  floor       int  not null check (floor between 0 and 50),
  sharing     int  not null check (sharing between 1 and 6),
  rent_month  int  not null check (rent_month > 0 and rent_month <= 500000),
  deposit     int  not null default 0 check (deposit >= 0 and deposit <= 1000000),
  created_at  timestamptz not null default now()
);
create index if not exists tenant_room_entries_room on public.tenant_room_entries (room_id);

alter table public.tenant_room_entries enable row level security;
drop policy if exists "own room entries: read" on public.tenant_room_entries;
create policy "own room entries: read" on public.tenant_room_entries for select to authenticated
  using (private.owns_hostel(hostel_id));
revoke insert, update, delete on public.tenant_room_entries from authenticated;
revoke all on public.tenant_room_entries from anon;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Add beds to a room until it has p_count beds (labels continue A, B, C…).
create or replace function private.grow_beds(p_room uuid, p_count int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  n int;
  i int;
begin
  select * into r from public.rooms where id = p_room;
  select count(*) into n from public.beds where room_id = p_room;
  for i in n + 1 .. least(p_count, 6) loop
    insert into public.beds (room_id, hostel_id, label, status)
    values (p_room, r.hostel_id, chr(64 + i), 'vacant')
    on conflict (room_id, label) do nothing;
  end loop;
end;
$$;

-- Rooms entered by tenants with what each tenant typed and whether the owner must fix them.
--   status: 'confirmed' (owner confirmed) · 'fix' (tenants typed different sharing / price / floor) · 'ok'
create or replace function private.tenant_room_rows(p_hostel uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  with e as (
    select e.*, t.full_name, t.status as tenant_status
      from public.tenant_room_entries e
      join public.tenants t on t.id = e.tenant_id
     where e.hostel_id = p_hostel and t.status not in ('draft', 'rejected', 'expired')
  ), agg as (
    select r.id, r.room_no, r.floor, r.sharing, r.rent_month, r.deposit_month, r.confirmed,
           (select count(*) from public.beds b where b.room_id = r.id) as beds,
           (select count(*) from public.beds b where b.room_id = r.id
              and (b.status in ('occupied', 'offline_occupied') or (b.held_for is not null and b.held_until > now()))) as filled,
           (select count(distinct e.sharing) from e where e.room_id = r.id) as n_sharing,
           (select count(distinct e.rent_month) from e where e.room_id = r.id) as n_rent,
           (select count(distinct e.floor) from e where e.room_id = r.id) as n_floor,
           (select coalesce(jsonb_agg(jsonb_build_object(
                     'tenant_id', e.tenant_id, 'name', coalesce(e.full_name, ''), 'floor', e.floor,
                     'sharing', e.sharing, 'rent_month', e.rent_month, 'deposit', e.deposit,
                     'tenant_status', e.tenant_status) order by e.created_at), '[]'::jsonb)
              from e where e.room_id = r.id) as entries
      from public.rooms r
     where r.hostel_id = p_hostel and r.from_tenants
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'room_id', a.id, 'room_no', a.room_no, 'floor', a.floor, 'sharing', a.sharing,
           'rent_month', a.rent_month, 'deposit', a.deposit_month, 'confirmed', a.confirmed,
           'beds', a.beds, 'filled', a.filled, 'entries', a.entries,
           'status', case when a.confirmed then 'confirmed'
                          when a.n_sharing > 1 or a.n_rent > 1 or a.n_floor > 1 then 'fix'
                          else 'ok' end)
         order by a.floor, a.room_no), '[]'::jsonb)
    from agg a;
$$;

-- Owner confirms a room with the correct floor / sharing / price / deposit.
-- Beds follow the sharing: extra empty beds are removed, missing beds are added.
create or replace function private.confirm_room(p_room uuid, p_floor int, p_sharing int, p_rent int, p_deposit int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  n int;
  used int;
begin
  if p_sharing is null or p_sharing not between 1 and 6 then raise exception 'BAD_SHARING'; end if;
  if p_rent is null or p_rent <= 0 or p_rent > 500000 then raise exception 'BAD_AMOUNT'; end if;
  if p_floor is null or p_floor not between 0 and 50 then raise exception 'BAD_FLOOR'; end if;
  perform 1 from public.rooms where id = p_room for update;
  select count(*) into n from public.beds where room_id = p_room;
  if n > p_sharing then
    select count(*) into used from public.beds where room_id = p_room
       and (status <> 'vacant' or (held_for is not null and held_until > now()));
    if used > p_sharing then raise exception 'TOO_MANY_TENANTS'; end if;
    -- remove empty beds from the end (Z → A) until the room has p_sharing beds
    delete from public.beds where id in (
      select id from public.beds where room_id = p_room and status = 'vacant'
         and not (held_for is not null and held_until > now())
       order by label desc limit n - p_sharing);
    -- re-letter the remaining beds A, B, C… (two passes to avoid clashes)
    update public.beds set label = '~' || label where room_id = p_room;
    update public.beds b set label = chr(64 + x.rn::int)
      from (select id, row_number() over (order by label) as rn from public.beds where room_id = p_room) x
     where b.id = x.id;
  elsif n < p_sharing then
    perform private.grow_beds(p_room, p_sharing);
  end if;
  update public.rooms set floor = p_floor, sharing = p_sharing, rent_month = p_rent,
         deposit_month = coalesce(p_deposit, 0), confirmed = true
   where id = p_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- OWNER functions
-- ---------------------------------------------------------------------------

-- More → Rooms from tenants
create or replace function public.tenant_rooms(p_hostel uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.assert_owner(p_hostel);
  return private.tenant_room_rows(p_hostel);
end;
$$;

-- Correct one room (the students are not told) and confirm it.
create or replace function public.confirm_tenant_room(p_room uuid, p_floor int, p_sharing int, p_rent int, p_deposit int)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.rooms;
begin
  select * into r from public.rooms where id = p_room;
  perform private.assert_owner(r.hostel_id);
  perform private.confirm_room(p_room, p_floor, p_sharing, p_rent, p_deposit);
end;
$$;

-- "Confirm all correct rooms": every unconfirmed room whose tenants all typed the same thing.
create or replace function public.confirm_correct_tenant_rooms(p_hostel uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare
  row jsonb;
  e jsonb;
  n int := 0;
begin
  perform private.assert_owner(p_hostel);
  for row in select x from jsonb_array_elements(private.tenant_room_rows(p_hostel)) x loop
    continue when row->>'status' <> 'ok' or jsonb_array_length(row->'entries') = 0;
    e := row->'entries'->0;
    perform private.confirm_room((row->>'room_id')::uuid, (e->>'floor')::int, (e->>'sharing')::int,
                                 (e->>'rent_month')::int, (e->>'deposit')::int);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Hostel settings → Price by sharing: one price and deposit for every tenant-entered room of that sharing.
create or replace function public.set_sharing_price(p_hostel uuid, p_sharing int, p_rent int, p_deposit int)
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform private.assert_owner(p_hostel);
  if p_rent is null or p_rent <= 0 or p_rent > 500000 then raise exception 'BAD_AMOUNT'; end if;
  update public.rooms set rent_month = p_rent, deposit_month = coalesce(p_deposit, 0)
   where hostel_id = p_hostel and from_tenants and sharing = p_sharing;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- STUDENT functions (service role only; called by the student-api Edge Function)
-- ---------------------------------------------------------------------------

-- The student typed a room number: if the owner has already set that room, its details are
-- filled in (and locked) on the form.
create or replace function public.student_room_lookup(p_session uuid, p_room_no text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  r public.rooms;
begin
  select * into r from public.rooms
   where hostel_id = s.hostel_id and lower(room_no) = lower(trim(coalesce(p_room_no, ''))) and confirmed;
  if not found then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'room_no', r.room_no, 'floor', r.floor, 'sharing', r.sharing,
                            'rent_month', r.rent_month, 'deposit', r.deposit_month);
end;
$$;

-- Use the room the student typed: create it (unconfirmed) if it doesn't exist yet and hold a bed in it.
create or replace function public.student_claim_typed_room(
  p_session uuid, p_room_no text, p_floor int, p_sharing int, p_rent int, p_deposit int, p_existing boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  h public.hostels;
  t public.tenants;
  r public.rooms;
  b public.beds;
  no text := trim(coalesce(p_room_no, ''));
  n int;
  rent int;
  dep int;
begin
  select * into h from public.hostels where id = s.hostel_id;
  if not h.is_open then raise exception 'HOSTEL_CLOSED'; end if;
  if not h.tenant_room_entry then raise exception 'ROOM_ENTRY_OFF'; end if;
  if length(no) not between 1 and 20 then raise exception 'BAD_ROOM_NO'; end if;
  if p_floor is null or p_floor not between 0 and 50 then raise exception 'BAD_FLOOR'; end if;
  if p_sharing is null or p_sharing not between 1 and 6 then raise exception 'BAD_SHARING'; end if;
  if p_rent is null or p_rent <= 0 or p_rent > 500000 then raise exception 'BAD_AMOUNT'; end if;
  if coalesce(p_deposit, 0) < 0 or coalesce(p_deposit, 0) > 1000000 then raise exception 'BAD_AMOUNT'; end if;

  t := private.session_tenant(s);
  if t.id is not null and t.status not in ('draft', 'awaiting_payment') then
    raise exception 'ALREADY_JOINED';
  end if;

  -- find or make the room (lock it so two students typing the same room don't clash)
  insert into public.rooms (hostel_id, room_no, floor, sharing, rent_month, deposit_month, confirmed, from_tenants)
  values (s.hostel_id, no, p_floor, p_sharing, p_rent, coalesce(p_deposit, 0), false, true)
  on conflict (hostel_id, room_no) do nothing;
  select * into r from public.rooms where hostel_id = s.hostel_id and lower(room_no) = lower(no) for update;

  -- an unconfirmed room grows if a tenant says it has more beds
  if not r.confirmed and p_sharing > r.sharing then
    update public.rooms set sharing = p_sharing where id = r.id;
    r.sharing := p_sharing;
  end if;
  select count(*) into n from public.beds where room_id = r.id;
  if n < r.sharing then perform private.grow_beds(r.id, r.sharing); end if;

  -- the bed this student already holds in this room, else a free one
  -- (existing tenants prefer a bed marked "already used"; new joiners need an empty bed)
  select * into b from public.beds
   where room_id = r.id and t.id is not null and held_for = t.id
     and (held_until is null or held_until > now())
   limit 1 for update;
  if not found then
    select * into b from public.beds
     where room_id = r.id
       and (status = 'vacant'
            or (status = 'held' and held_until < now())
            or (coalesce(p_existing, false) and status = 'offline_occupied' and (held_for is null or held_until < now())))
     order by case when coalesce(p_existing, false) and status = 'offline_occupied' then 0 else 1 end, label
     limit 1 for update skip locked;
  end if;
  if not found and not r.confirmed then
    -- more tenants than the room had beds: add one (the owner sees and fixes it)
    select count(*) into n from public.beds where room_id = r.id;
    if n >= 6 then raise exception 'ROOM_FULL'; end if;
    perform private.grow_beds(r.id, n + 1);
    select * into b from public.beds where room_id = r.id and label = chr(65 + n) for update;
  end if;
  if b.id is null then raise exception 'ROOM_FULL'; end if;

  if t.id is null then
    insert into public.tenants (hostel_id, phone, status)
    values (s.hostel_id, s.phone, 'draft')
    returning * into t;
    update public.student_sessions set tenant_id = t.id where id = s.id;
  elsif t.bed_id is not null and t.bed_id <> b.id then
    perform private.release_bed(t.bed_id, t.id);
  end if;

  update public.beds
     set status = case when status = 'offline_occupied' then status else 'held'::public.bed_status end,
         held_until = now() + interval '15 minutes',
         held_for = t.id
   where id = b.id;

  -- each tenant keeps the fee they typed; a room the owner already set uses its price
  rent := case when r.confirmed then r.rent_month else p_rent end;
  dep  := case when r.confirmed then r.deposit_month else coalesce(p_deposit, 0) end;
  update public.tenants set bed_id = b.id, rent_month = rent, deposit = dep, status = 'draft' where id = t.id;

  insert into public.tenant_room_entries (hostel_id, tenant_id, room_id, room_no, floor, sharing, rent_month, deposit)
  values (s.hostel_id, t.id, r.id, no, p_floor, p_sharing, p_rent, coalesce(p_deposit, 0))
  on conflict (tenant_id) do update
     set room_id = excluded.room_id, room_no = excluded.room_no, floor = excluded.floor,
         sharing = excluded.sharing, rent_month = excluded.rent_month, deposit = excluded.deposit,
         created_at = now();

  return jsonb_build_object('tenant_id', t.id, 'bed_id', b.id, 'room_no', r.room_no, 'bed_label', b.label,
                            'held_until', now() + interval '15 minutes',
                            'offline_bed', b.status = 'offline_occupied', 'confirmed_room', r.confirmed);
end;
$$;

-- Room selection: only rooms the owner has confirmed (tenant-entered ones only when
-- "Use these prices for new joiners" is on).
create or replace function public.student_rooms(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants := private.session_tenant(s);
  h public.hostels;
begin
  select * into h from public.hostels where id = s.hostel_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'room_no', r.room_no, 'floor', r.floor, 'sharing', r.sharing,
      'rent_month', r.rent_month, 'deposit_month', r.deposit_month, 'features', to_jsonb(r.features),
      'beds', (select jsonb_agg(jsonb_build_object(
                 'id', b.id, 'label', b.label,
                 'state', case
                   when b.held_for is not null and b.held_for = t.id and (b.held_until is null or b.held_until > now()) then 'yours'
                   when b.status = 'vacant' then 'free'
                   when b.status = 'held' and b.held_until < now() then 'free'
                   when b.status = 'offline_occupied' and (b.held_for is null or b.held_until < now()) then 'offline'
                   else 'taken' end)
               order by b.label)
               from public.beds b where b.room_id = r.id)
    ) order by r.floor, r.room_no)
    from public.rooms r
    where r.hostel_id = s.hostel_id and r.confirmed and (h.use_tenant_prices or not r.from_tenants)
  ), '[]'::jsonb);
end;
$$;

-- Student hostel info: + tenant_room_entry (the details form then asks for the room).
create or replace function public.student_hostel(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  h public.hostels;
  o public.profiles;
  t public.tenants;
begin
  select * into h from public.hostels where id = s.hostel_id;
  select * into o from public.profiles where id = h.owner_id;
  t := private.session_tenant(s);
  return jsonb_build_object(
    'id', h.id, 'name', h.name, 'type', h.type, 'address', h.address, 'city', h.city,
    'contact_phone', h.contact_phone, 'owner_name', o.full_name,
    'rent_day_mode', h.rent_day_mode, 'rent_fixed_day', h.rent_fixed_day, 'notice_days', h.notice_days,
    'amenities', to_jsonb(h.amenities), 'house_rules', h.house_rules, 'is_open', h.is_open,
    'min_rent', (select min(r.rent_month) from public.rooms r where r.hostel_id = h.id and r.confirmed),
    'sharing_min', (select min(r.sharing) from public.rooms r where r.hostel_id = h.id and r.confirmed),
    'sharing_max', (select max(r.sharing) from public.rooms r where r.hostel_id = h.id and r.confirmed),
    'free_beds', (select count(*) from public.beds b join public.rooms r on r.id = b.room_id
                   where b.hostel_id = h.id and r.confirmed
                   and (b.status = 'vacant' or (b.status = 'held' and b.held_until < now()))),
    'tenant_id', t.id, 'tenant_status', t.status, 'phone', s.phone,
    'tenant_room_entry', h.tenant_room_entry);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
revoke execute on function
  private.grow_beds(uuid, int),
  private.tenant_room_rows(uuid),
  private.confirm_room(uuid, int, int, int, int)
from public, anon, authenticated;

revoke execute on function
  public.tenant_rooms(uuid),
  public.confirm_tenant_room(uuid, int, int, int, int),
  public.confirm_correct_tenant_rooms(uuid),
  public.set_sharing_price(uuid, int, int, int),
  public.student_room_lookup(uuid, text),
  public.student_claim_typed_room(uuid, text, int, int, int, int, boolean)
from public, anon;

grant execute on function
  public.tenant_rooms(uuid),
  public.confirm_tenant_room(uuid, int, int, int, int),
  public.confirm_correct_tenant_rooms(uuid),
  public.set_sharing_price(uuid, int, int, int)
to authenticated;

revoke execute on function
  public.student_room_lookup(uuid, text),
  public.student_claim_typed_room(uuid, text, int, int, int, int, boolean)
from authenticated;
grant execute on function
  public.student_room_lookup(uuid, text),
  public.student_claim_typed_room(uuid, text, int, int, int, int, boolean)
to service_role;
