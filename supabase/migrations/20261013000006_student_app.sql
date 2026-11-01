-- Student app (QR → install → app opens on the bed):
--  * the owner's QR hold lasts 60 minutes (time to install the app); the student's 15 minutes start
--    when the app first opens on the bed (booking_peek with p_start)
--  * parent name and reference name on the student details screen

alter table public.beds add column if not exists booking_opened_at timestamptz;
alter table public.tenants add column if not exists parent_name text check (parent_name is null or length(parent_name) <= 120);
alter table public.tenants add column if not exists reference_name text check (reference_name is null or length(reference_name) <= 120);

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
     set status = 'held', held_for = null, booking_code = code, booking_opened_at = null,
         held_until = now() + interval '60 minutes'
   where id = p_bed;

  return jsonb_build_object(
    'bed_id', b.id, 'bed_label', b.label, 'booking_code', code,
    'held_until', now() + interval '60 minutes',
    'room_no', r.room_no, 'floor', r.floor, 'sharing', r.sharing, 'features', r.features,
    'rent_month', r.rent_month, 'deposit', r.deposit_month,
    'total', r.rent_month + r.deposit_month);
end;
$$;

-- Peek at the held bed. p_start = the app opened on it: the 15-minute timer starts now (once).
drop function if exists public.booking_peek(text, uuid, text);
create or replace function public.booking_peek(p_join_code text, p_bed uuid, p_code text, p_start boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  h public.hostels;
  b public.beds;
  r public.rooms;
begin
  select * into h from public.hostels where join_code = upper(p_join_code);
  if not found then raise exception 'HOSTEL_NOT_FOUND'; end if;
  select * into b from public.beds where id = p_bed and hostel_id = h.id for update;
  if not found or b.booking_code is distinct from p_code then raise exception 'BOOKING_LINK_INVALID'; end if;
  if b.status <> 'held' or b.held_until < now() then raise exception 'BOOKING_EXPIRED'; end if;
  if coalesce(p_start, false) and b.booking_opened_at is null and b.held_for is null then
    update public.beds set booking_opened_at = now(), held_until = now() + interval '15 minutes'
     where id = b.id returning * into b;
  end if;
  select * into r from public.rooms where id = b.room_id;
  return jsonb_build_object(
    'hostel_name', h.name, 'hostel_area', h.city, 'address', h.address,
    'room_no', r.room_no, 'bed_label', b.label, 'floor', r.floor, 'sharing', r.sharing,
    'features', r.features, 'rent_month', r.rent_month, 'deposit', r.deposit_month,
    'total', r.rent_month + r.deposit_month, 'held_until', b.held_until,
    'timer_started', b.booking_opened_at is not null,
    'taken', b.held_for is not null);
end;
$$;

-- Parent name and reference name (saved right after the details).
create or replace function public.student_set_names(p_session uuid, p_parent_name text, p_reference_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants := private.session_tenant(s);
begin
  if t.id is null then raise exception 'NO_BOOKING'; end if;
  if nullif(trim(coalesce(p_parent_name, '')), '') is null then raise exception 'PARENT_NAME_REQUIRED'; end if;
  update public.tenants
     set parent_name = left(trim(p_parent_name), 120),
         reference_name = left(nullif(trim(coalesce(p_reference_name, '')), ''), 120)
   where id = t.id;
end;
$$;

-- Student app extras: + parent / reference names (late fee from 20261013000005 kept).
create or replace function public.student_me_extra(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  lf record;
begin
  if s.tenant_id is not null then select * into t from public.tenants where id = s.tenant_id;
  else t := private.session_tenant(s); end if;
  if t.id is null then raise exception 'NO_BOOKING'; end if;
  select * into lf from private.late_fee(t.id, private.today());
  return jsonb_build_object('org_name', t.org_name, 'has_photo', t.photo_key is not null,
    'parent_name', t.parent_name, 'reference_name', t.reference_name,
    'late_fee', coalesce(lf.fee, 0), 'late_days', coalesce(lf.days, 0), 'late_fee_per_day', coalesce(lf.per_day, 0));
end;
$$;

revoke execute on function public.booking_peek(text, uuid, text, boolean), public.student_set_names(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.booking_peek(text, uuid, text, boolean), public.student_set_names(uuid, text, text)
  to service_role;
