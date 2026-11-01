-- Wi-Fi for students: the owner adds one network for the whole hostel or one per floor
-- (Hostel settings → Wi-Fi). Approved students see their network on My room.

alter table public.hostels add column if not exists wifi jsonb not null default '[]'::jsonb;
do $$ begin
  alter table public.hostels add constraint hostels_wifi_is_list
    check (jsonb_typeof(wifi) = 'array' and jsonb_array_length(wifi) <= 50);
exception when duplicate_object then null; end $$;

-- Wi-Fi networks a tenant may see: the whole-hostel one(s) and their floor's, only while staying.
create or replace function private.tenant_wifi(p_tenant uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', w->>'name', 'password', w->>'password', 'floor', w->'floor')
                            order by (w->>'floor') nulls first), '[]'::jsonb)
  from public.tenants t
  join public.hostels h on h.id = t.hostel_id
  left join public.beds b on b.id = t.bed_id
  left join public.rooms r on r.id = b.room_id
  cross join lateral jsonb_array_elements(h.wifi) w
  where t.id = p_tenant and t.status in ('active', 'notice')
    and coalesce(w->>'name', '') <> ''
    and (jsonb_typeof(w->'floor') is distinct from 'number' or (w->>'floor')::int = r.floor);
$$;

-- Student app extras: + Wi-Fi and room floor (late fee, parent / reference names kept).
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
    'room_floor', (select r.floor from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id),
    'wifi', private.tenant_wifi(t.id),
    'late_fee', coalesce(lf.fee, 0), 'late_days', coalesce(lf.days, 0), 'late_fee_per_day', coalesce(lf.per_day, 0));
end;
$$;

-- Student hostel info: + the verified mobile (shown on Student Details Entry before a bed is held).
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
    'min_rent', (select min(r.rent_month) from public.rooms r where r.hostel_id = h.id),
    'sharing_min', (select min(r.sharing) from public.rooms r where r.hostel_id = h.id),
    'sharing_max', (select max(r.sharing) from public.rooms r where r.hostel_id = h.id),
    'free_beds', (select count(*) from public.beds b where b.hostel_id = h.id
                   and (b.status = 'vacant' or (b.status = 'held' and b.held_until < now()))),
    'tenant_id', t.id, 'tenant_status', t.status, 'phone', s.phone);
end;
$$;

revoke execute on function private.tenant_wifi(uuid) from public, anon, authenticated;
