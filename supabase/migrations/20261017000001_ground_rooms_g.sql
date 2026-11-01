-- Rooms entered by tenants: ground floor rooms are G + a number (G1, G2, G3 …).
-- A student who picks "Ground" types only the number after a fixed G; rooms on floors 1–9
-- can't start with G. The owner's fix panel follows the same rule.

create or replace function private.confirm_room(p_room uuid, p_floor int, p_sharing int, p_rent int, p_deposit int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  n int;
  used int;
begin
  if p_sharing is null or p_sharing not between 1 and 12 then raise exception 'BAD_SHARING'; end if;
  if p_rent is null or p_rent <= 0 or p_rent > 500000 then raise exception 'BAD_AMOUNT'; end if;
  if p_floor is null or p_floor not between 0 and 50 then raise exception 'BAD_FLOOR'; end if;
  if exists (select 1 from public.rooms where id = p_room and from_tenants
              and ((p_floor = 0 and room_no !~* '^G[0-9]{1,4}$') or (p_floor > 0 and room_no ~* '^G'))) then
    raise exception 'BAD_GROUND_ROOM';
  end if;
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
  -- ground floor rooms are G + a number (G1, G2 …); other floors can't start with G
  if no ~* '^g' then no := 'G' || substr(no, 2); end if;
  if p_floor = 0 and no !~ '^G[0-9]{1,4}$' then raise exception 'BAD_GROUND_ROOM'; end if;
  if p_floor > 0 and no ~ '^G' then raise exception 'BAD_GROUND_ROOM'; end if;
  if p_floor is null or p_floor not between 0 and 50 then raise exception 'BAD_FLOOR'; end if;
  if p_sharing is null or p_sharing not between 1 and 12 then raise exception 'BAD_SHARING'; end if;
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
    if n >= 12 then raise exception 'ROOM_FULL'; end if;
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
