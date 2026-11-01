-- Owner books a free bed from the Rooms tab and shows the student a QR code for that bed.
--  * owner_hold_bed: holds the bed for 15 minutes with a one-time booking code (in the QR link)
--  * booking_peek: the student's phone shows the bed, rent and deposit before the OTP
--  * student_hold_booked_bed: after the OTP the student takes that held bed (code must match)
-- Also: company / institute name for tenants, parent mobile required, profile photo optional.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
alter table public.beds add column if not exists booking_code text;

alter table public.tenants add column if not exists org_name text
  check (org_name is null or length(trim(org_name)) between 2 and 160);

grant select (org_name) on public.tenants to authenticated;
grant update (org_name) on public.tenants to authenticated;

-- ---------------------------------------------------------------------------
-- Owner: hold a free bed for 15 minutes and get the booking code for the QR link
-- ---------------------------------------------------------------------------
create or replace function public.owner_hold_bed(p_bed uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  b public.beds;
  r public.rooms;
  code text;
begin
  select * into b from public.beds where id = p_bed for update;
  if not found then raise exception 'BED_NOT_FOUND'; end if;
  perform private.assert_owner(b.hostel_id);
  select * into r from public.rooms where id = b.room_id;

  -- free = vacant, or a hold that has run out, or the owner's own earlier hold (no student yet)
  if not (b.status = 'vacant'
          or (b.status = 'held' and (b.held_until < now() or b.held_for is null))) then
    raise exception 'BED_TAKEN';
  end if;

  code := case when b.status = 'held' and b.held_for is null and b.held_until >= now() and b.booking_code is not null
               then b.booking_code
               else encode(extensions.gen_random_bytes(9), 'hex') end;

  update public.beds
     set status = 'held', held_for = null, booking_code = code,
         held_until = now() + interval '15 minutes'
   where id = p_bed;

  return jsonb_build_object(
    'bed_id', b.id, 'bed_label', b.label, 'booking_code', code,
    'held_until', now() + interval '15 minutes',
    'room_no', r.room_no, 'floor', r.floor, 'sharing', r.sharing, 'features', r.features,
    'rent_month', r.rent_month, 'deposit', r.deposit_month,
    'total', r.rent_month + r.deposit_month);
end;
$$;

-- Owner: give the bed back (closing the QR screen without a booking).
create or replace function public.owner_release_bed(p_bed uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare b public.beds;
begin
  select * into b from public.beds where id = p_bed for update;
  if not found then return; end if;
  perform private.assert_owner(b.hostel_id);
  if b.status = 'held' and b.held_for is null then
    update public.beds set status = 'vacant', held_until = null, booking_code = null where id = p_bed;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Student (server only): bed shown on the QR link before the OTP
-- ---------------------------------------------------------------------------
create or replace function public.booking_peek(p_join_code text, p_bed uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  h public.hostels;
  b public.beds;
  r public.rooms;
begin
  select * into h from public.hostels where join_code = upper(p_join_code);
  if not found then raise exception 'HOSTEL_NOT_FOUND'; end if;
  select * into b from public.beds where id = p_bed and hostel_id = h.id;
  if not found or b.booking_code is distinct from p_code then raise exception 'BOOKING_LINK_INVALID'; end if;
  if b.status <> 'held' or b.held_until < now() then raise exception 'BOOKING_EXPIRED'; end if;
  select * into r from public.rooms where id = b.room_id;
  return jsonb_build_object(
    'room_no', r.room_no, 'bed_label', b.label, 'floor', r.floor, 'sharing', r.sharing,
    'features', r.features, 'rent_month', r.rent_month, 'deposit', r.deposit_month,
    'total', r.rent_month + r.deposit_month, 'held_until', b.held_until,
    'taken', b.held_for is not null);
end;
$$;

-- Student (server only): take the bed the owner held for them.
create or replace function public.student_hold_booked_bed(p_session uuid, p_bed uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  b public.beds;
  r public.rooms;
begin
  t := private.session_tenant(s);
  if t.id is not null and t.status not in ('draft', 'awaiting_payment') then
    raise exception 'ALREADY_JOINED';
  end if;

  select * into b from public.beds where id = p_bed and hostel_id = s.hostel_id for update;
  if not found or b.booking_code is distinct from p_code then raise exception 'BOOKING_LINK_INVALID'; end if;
  if b.status <> 'held' or b.held_until < now() then raise exception 'BOOKING_EXPIRED'; end if;
  if b.held_for is not null and (t.id is null or b.held_for <> t.id) then raise exception 'BED_TAKEN'; end if;
  select * into r from public.rooms where id = b.room_id;

  if t.id is null then
    insert into public.tenants (hostel_id, phone, status)
    values (s.hostel_id, s.phone, 'draft')
    returning * into t;
    update public.student_sessions set tenant_id = t.id where id = s.id;
  elsif t.bed_id is not null and t.bed_id <> p_bed then
    perform private.release_bed(t.bed_id, t.id);
  end if;

  -- the student now owns the hold; give them time to fill the form
  update public.beds
     set held_for = t.id, held_until = greatest(held_until, now() + interval '15 minutes')
   where id = p_bed;
  update public.tenants
     set bed_id = p_bed, rent_month = r.rent_month, deposit = r.deposit_month, status = 'draft'
   where id = t.id;

  return jsonb_build_object('tenant_id', t.id, 'bed_id', p_bed, 'room_no', r.room_no, 'bed_label', b.label,
                            'held_until', (select held_until from public.beds where id = p_bed));
end;
$$;

-- ---------------------------------------------------------------------------
-- Student details: + company / institute name, parent mobile required, photo optional
-- ---------------------------------------------------------------------------
drop function if exists public.student_submit_details(
  uuid, text, text, text, public.id_type, text, text, text, text, text, boolean, date, boolean);

create or replace function public.student_submit_details(
  p_session uuid,
  p_full_name text, p_parent_phone text, p_reference_phone text,
  p_id_type public.id_type, p_id_number text,
  p_id_file_key text, p_photo_key text,
  p_home_address text, p_office_address text,
  p_is_existing boolean, p_joining_date date, p_consent boolean,
  p_org_name text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants := private.session_tenant(s);
  b public.beds;
  digits text;
  today date := private.today();
  join_date date;
begin
  if t.id is null or t.status not in ('draft', 'awaiting_payment') then raise exception 'NO_BED_HELD'; end if;
  select * into b from public.beds where id = t.bed_id for update;
  if b.held_for is distinct from t.id or (b.held_until is not null and b.held_until < now()) then
    raise exception 'HOLD_EXPIRED';
  end if;
  if b.status = 'offline_occupied' and not p_is_existing then
    raise exception 'BED_TAKEN';
  end if;
  if not coalesce(p_consent, false) then raise exception 'CONSENT_REQUIRED'; end if;
  if p_parent_phone is null then raise exception 'PARENT_PHONE_REQUIRED'; end if;

  -- ID number checks
  digits := regexp_replace(coalesce(p_id_number, ''), '\s', '', 'g');
  if p_id_type = 'aadhaar' and digits !~ '^[0-9X]{8}[0-9]{4}$' then raise exception 'BAD_ID_NUMBER'; end if;
  if p_id_type <> 'aadhaar' and digits !~ '^[A-Za-z0-9-]{6,20}$' then raise exception 'BAD_ID_NUMBER'; end if;
  if p_id_file_key is null then raise exception 'FILES_REQUIRED'; end if;  -- profile photo is optional

  if p_is_existing then
    join_date := p_joining_date;
    if join_date is null or join_date > today or join_date < today - 1825 then
      raise exception 'BAD_JOINING_DATE';
    end if;
  else
    join_date := today;
  end if;

  update public.tenants set
    full_name = trim(p_full_name),
    parent_phone = p_parent_phone,
    reference_phone = p_reference_phone,
    id_type = p_id_type,
    id_number_enc = case when digits ~ '^X' then null
                         else extensions.pgp_sym_encrypt(digits, private.id_key()) end,
    id_last4 = right(digits, 4),
    id_file_key = p_id_file_key,
    photo_key = p_photo_key,
    home_address = trim(p_home_address),
    office_address = nullif(trim(coalesce(p_office_address, '')), ''),
    org_name = nullif(trim(coalesce(p_org_name, '')), ''),
    is_existing = p_is_existing,
    joining_date = join_date,
    consent_at = now(),
    status = case when p_is_existing then 'pending_approval'::public.tenant_status
                  else 'awaiting_payment'::public.tenant_status end
  where id = t.id;

  if p_is_existing then
    update public.beds set held_until = now() + interval '7 days' where id = b.id;
    perform private.notify(t.hostel_id, 'existing_tenant', 'Existing tenant to approve',
      trim(p_full_name) || ' says they joined on ' || to_char(join_date, 'DD Mon YYYY'), t.id);
    return jsonb_build_object('tenant_id', t.id, 'status', 'pending_approval');
  end if;

  update public.beds set held_until = greatest(held_until, now() + interval '10 minutes') where id = b.id;
  return jsonb_build_object('tenant_id', t.id, 'status', 'awaiting_payment');
end;
$$;

-- ---------------------------------------------------------------------------
-- Expired holds: also free the owner's QR holds nobody used (held_for is null)
-- ---------------------------------------------------------------------------
create or replace function public.release_expired_holds()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with expired as (
    update public.beds b
       set status = case when b.status = 'held' then 'vacant'::public.bed_status else b.status end,
           held_for = null, held_until = null, booking_code = null
     where b.held_until < now()
       and (b.held_for is not null or b.status = 'held')
       and b.status in ('held', 'offline_occupied')
    returning b.id
  )
  select count(*) into n from expired;
  update public.tenants set status = 'expired', bed_id = null
   where status in ('draft', 'awaiting_payment')
     and (bed_id is null or not exists (select 1 from public.beds b where b.id = tenants.bed_id and b.held_for = tenants.id))
     and created_at < now() - interval '15 minutes';
  return n;
end;
$$;

-- the booking code is used once: clear it when the student's payment is in
create or replace function private.clear_booking_code()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status in ('pending_approval', 'active') and new.bed_id is not null then
    update public.beds set booking_code = null where id = new.bed_id;
  end if;
  return new;
end;
$$;
drop trigger if exists tenants_clear_booking_code on public.tenants;
create trigger tenants_clear_booking_code
  after update of status on public.tenants
  for each row when (old.status is distinct from new.status)
  execute function private.clear_booking_code();

-- ---------------------------------------------------------------------------
-- Student "me": include company / institute
-- ---------------------------------------------------------------------------
create or replace function public.student_me_extra(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
begin
  if s.tenant_id is not null then select * into t from public.tenants where id = s.tenant_id;
  else t := private.session_tenant(s); end if;
  if t.id is null then raise exception 'NO_BOOKING'; end if;
  return jsonb_build_object('org_name', t.org_name, 'has_photo', t.photo_key is not null);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
revoke execute on function public.owner_hold_bed(uuid), public.owner_release_bed(uuid),
  public.booking_peek(text, uuid, text), public.student_hold_booked_bed(uuid, uuid, text),
  public.student_submit_details(uuid, text, text, text, public.id_type, text, text, text, text, text, boolean, date, boolean, text),
  public.student_me_extra(uuid), public.release_expired_holds()
  from public, anon, authenticated;
grant execute on function public.owner_hold_bed(uuid), public.owner_release_bed(uuid) to authenticated;
grant execute on function
  public.booking_peek(text, uuid, text),
  public.student_hold_booked_bed(uuid, uuid, text),
  public.student_submit_details(uuid, text, text, text, public.id_type, text, text, text, text, text, boolean, date, boolean, text),
  public.student_me_extra(uuid),
  public.release_expired_holds()
to service_role;
revoke all on function private.clear_booking_code() from public, anon, authenticated;
