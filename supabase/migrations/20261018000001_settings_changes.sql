-- Hostel settings, round 3 (decided 18 Oct 2026):
--  * messages to students (sharing change, fee date change, notice period change)
--  * Change room details: when the sharing changes, the students in that room pay the new
--    sharing's price from their next fee date (a price change in Rent per bed alone is only
--    for new students)
--  * Rent date change: the days between the old and the new fee date are added (or taken off)
--    once, in the next fee: monthly fee ÷ days in that month × days
--  * Notice period: owner picks any number of days (1–90); students are told
--  * Add room from Hostel settings (floor, room number, sharing, price)
-- All of these are owner only (private.assert_owner).

-- ---------------------------------------------------------------------------
-- Messages to students (shown on the student's home; text is built in the app's language)
-- ---------------------------------------------------------------------------
create table if not exists public.student_messages (
  id         uuid primary key default gen_random_uuid(),
  hostel_id  uuid not null references public.hostels (id) on delete cascade,
  tenant_id  uuid not null references public.tenants (id) on delete cascade,
  kind       text not null check (kind in ('sharing_change', 'rent_date_change', 'notice_change')),
  params     jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists student_messages_tenant_idx on public.student_messages (tenant_id, created_at desc);
alter table public.student_messages enable row level security;
create policy "own student messages: read" on public.student_messages for select to authenticated
  using (private.owns_hostel(hostel_id));

create or replace function private.message_student(p_tenant uuid, p_kind text, p_params jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.student_messages (hostel_id, tenant_id, kind, params)
  select t.hostel_id, t.id, p_kind, coalesce(p_params, '{}') from public.tenants t where t.id = p_tenant;
$$;

-- the date of a tenant's next fee (first unpaid future rent bill, else the day after the last one)
create or replace function private.next_fee_date(p_tenant uuid)
returns date language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select min(due_date) from public.bills
      where tenant_id = p_tenant and kind = 'rent' and status in ('unpaid', 'partial') and due_date >= private.today()),
    (select max(period_end) + 1 from public.bills where tenant_id = p_tenant and kind = 'rent'));
$$;

-- ---------------------------------------------------------------------------
-- Change room details: sharing change moves the students in the room to the new fee
-- ---------------------------------------------------------------------------
create or replace function public.update_room(p_room uuid, p_room_no text, p_sharing int, p_rent int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  no text := trim(coalesce(p_room_no, ''));
  t record;
  next_due date;
begin
  select * into r from public.rooms where id = p_room;
  perform private.assert_owner(r.hostel_id);
  if length(no) not between 1 and 20 then raise exception 'BAD_ROOM_NO'; end if;
  if no ~* '^g' then no := 'G' || substr(no, 2); end if;
  if lower(no) <> lower(r.room_no) then
    if r.floor = 0 and no !~ '^G[0-9]{1,4}$' then raise exception 'BAD_GROUND_ROOM'; end if;
    if r.floor > 0 and no ~ '^G' then raise exception 'BAD_GROUND_ROOM'; end if;
    if exists (select 1 from public.rooms where hostel_id = r.hostel_id and lower(room_no) = lower(no) and id <> r.id) then
      raise exception 'ROOM_EXISTS';
    end if;
    update public.rooms set room_no = no where id = p_room;
  end if;
  perform private.confirm_room(p_room, r.floor, p_sharing, p_rent, r.deposit_month);

  -- the sharing changed: students staying in this room pay the new fee from their next fee date
  if p_sharing <> r.sharing then
    for t in
      select te.* from public.tenants te join public.beds b on b.id = te.bed_id
      where b.room_id = p_room and te.status in ('active', 'notice') and te.stay_type = 'monthly'
    loop
      next_due := private.next_fee_date(t.id);
      update public.tenants set rent_month = p_rent where id = t.id;
      -- fee bills made early (not paid yet, starting after today) take the new fee too
      update public.bills set amount = p_rent
        where tenant_id = t.id and kind = 'rent' and status = 'unpaid' and paid_amount = 0
          and period_start > private.today();
      perform private.message_student(t.id, 'sharing_change', jsonb_build_object(
        'room', no, 'from', r.sharing, 'to', p_sharing,
        'old_rent', coalesce(t.rent_month, r.rent_month), 'new_rent', p_rent, 'from_date', next_due));
    end loop;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rent date change with a one-time adjustment
-- ---------------------------------------------------------------------------
create or replace function private.days_in_month(p_day date)
returns int language sql immutable set search_path = '' as $$
  select extract(day from (date_trunc('month', p_day) + interval '1 month - 1 day'))::int;
$$;

-- Moves one tenant to the new fee date. s = start of the next fee under the old date.
-- The new fee date nearest to s is used: later → the days in between are added once;
-- earlier → those days (already paid) are taken off once. Returns the message params or null.
create or replace function private.move_fee_date(p_tenant uuid, p_mode public.rent_day_mode, p_fixed_day int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  s date;
  after_d date;
  before_d date;
  days int;
  adj int;
  rent int;
  amount int;
  p_start date;
  p_end date;
  due date;
begin
  select * into t from public.tenants where id = p_tenant;
  if t.stay_type <> 'monthly' or t.joining_date is null then return null; end if;
  rent := coalesce(t.rent_month, 0);
  -- fee bills made early (not paid, starting after today) are made again on the new date
  delete from public.bills where tenant_id = t.id and kind = 'rent' and status = 'unpaid' and paid_amount = 0
    and period_start > private.today();
  select max(period_end) + 1 into s from public.bills where tenant_id = t.id and kind = 'rent';
  if s is null then return null; end if;   -- not staying yet (first bill is made on joining)
  if t.status = 'notice' and t.leaving_date is not null and s > t.leaving_date then return null; end if;

  after_d := private.next_rent_start(p_mode, p_fixed_day, t.joining_date, s);
  if after_d = s then return null; end if;   -- same date as before
  before_d := (after_d - interval '1 month')::date;
  if p_mode = 'joining_date' then
    before_d := private.next_rent_start(p_mode, p_fixed_day, t.joining_date, (after_d - interval '1 month' - interval '3 days')::date);
  end if;

  if (after_d - s) <= (s - before_d) then
    -- new date is later: days s .. after_d-1 are added once
    days := after_d - s;
    adj := round(rent::numeric * days / private.days_in_month(s))::int;
    p_start := s;
    p_end := (after_d + interval '1 month')::date - 1;
    due := after_d;
    amount := rent + adj;
  else
    -- new date is earlier: days before_d .. s-1 were already paid, taken off once
    days := -(s - before_d);
    adj := -round(rent::numeric * (s - before_d) / private.days_in_month(before_d))::int;
    p_start := before_d;
    p_end := (before_d + interval '1 month')::date - 1;
    due := greatest(before_d, private.today());
    amount := greatest(rent + adj, 0);
  end if;

  insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
  values (t.hostel_id, t.id, 'rent', 'Rent ' || to_char(p_start, 'DD Mon') || ' – ' || to_char(p_end, 'DD Mon'),
          p_start, p_end, amount, due)
  on conflict do nothing;
  perform private.allocate_payments(t.id);
  return jsonb_build_object('mode', p_mode, 'day', case when p_mode = 'fixed_day' then p_fixed_day end,
    'next_due', due, 'rent', rent, 'days', days, 'adjust', adj, 'amount', amount);
end;
$$;

-- Owner saves Rent date. Every staying student moves to the new date and gets a message.
create or replace function public.change_rent_day(p_hostel uuid, p_mode public.rent_day_mode, p_fixed_day int)
returns int language plpgsql security definer set search_path = '' as $$
declare
  h public.hostels;
  t record;
  msg jsonb;
  n int := 0;
  day int := coalesce(p_fixed_day, 5);
begin
  perform private.assert_owner(p_hostel);
  if day not between 1 and 28 then raise exception 'BAD_DAY'; end if;
  select * into h from public.hostels where id = p_hostel;
  if h.rent_day_mode = p_mode and (p_mode = 'joining_date' or h.rent_fixed_day = day) then return 0; end if;
  update public.hostels set rent_day_mode = p_mode, rent_fixed_day = day where id = p_hostel;
  for t in select id from public.tenants where hostel_id = p_hostel and status in ('active', 'notice') loop
    msg := private.move_fee_date(t.id, p_mode, day);
    if msg is not null then
      perform private.message_student(t.id, 'rent_date_change', msg);
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

-- What a Rent date change would do (for the owner's "Yes, change" sheet): an example student.
create or replace function public.rent_day_preview(p_hostel uuid, p_mode public.rent_day_mode, p_fixed_day int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  h public.hostels;
  staying int;
begin
  perform private.assert_owner(p_hostel);
  select * into h from public.hostels where id = p_hostel;
  select count(*) into staying from public.tenants
    where hostel_id = p_hostel and status in ('active', 'notice') and stay_type = 'monthly';
  return jsonb_build_object('staying', staying, 'old_mode', h.rent_day_mode, 'old_day', h.rent_fixed_day,
    'new_mode', p_mode, 'new_day', p_fixed_day);
end;
$$;

-- ---------------------------------------------------------------------------
-- Notice period: any number of days; students who haven't given notice are told
-- ---------------------------------------------------------------------------
create or replace function public.set_notice_days(p_hostel uuid, p_days int)
returns int language plpgsql security definer set search_path = '' as $$
declare
  t record;
  n int := 0;
begin
  perform private.assert_owner(p_hostel);
  if p_days is null or p_days not between 1 and 90 then raise exception 'BAD_DAYS'; end if;
  if (select notice_days from public.hostels where id = p_hostel) = p_days then return 0; end if;
  update public.hostels set notice_days = p_days where id = p_hostel;
  -- students who already gave notice keep their leaving date
  for t in select id from public.tenants where hostel_id = p_hostel and status = 'active' loop
    perform private.message_student(t.id, 'notice_change', jsonb_build_object('days', p_days));
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Add room from Hostel settings
-- ---------------------------------------------------------------------------
create or replace function public.add_room_simple(p_hostel uuid, p_floor int, p_room_no text, p_sharing int, p_rent int)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  h public.hostels;
  no text := trim(coalesce(p_room_no, ''));
  rid uuid;
  prices jsonb;
begin
  perform private.assert_owner(p_hostel);
  select * into h from public.hostels where id = p_hostel;
  if p_floor is null or p_floor not between 0 and 50 then raise exception 'BAD_FLOOR'; end if;
  if length(no) not between 1 and 20 then raise exception 'BAD_ROOM_NO'; end if;
  if no ~* '^g' then no := 'G' || substr(no, 2); end if;
  if p_floor = 0 and no !~ '^G[0-9]{1,4}$' then raise exception 'BAD_GROUND_ROOM'; end if;
  if p_floor > 0 and no ~ '^G' then raise exception 'BAD_GROUND_ROOM'; end if;
  if p_sharing is null or p_sharing not between 1 and 12 then raise exception 'BAD_SHARING'; end if;
  if p_rent is null or p_rent <= 0 or p_rent > 500000 then raise exception 'BAD_AMOUNT'; end if;
  if exists (select 1 from public.rooms where hostel_id = p_hostel and lower(room_no) = lower(no)) then
    raise exception 'ROOM_EXISTS';
  end if;
  rid := public.add_room(p_hostel, no, p_floor, p_sharing, p_rent,
    case when h.deposit_on then coalesce(h.deposit_amount, 0) else 0 end, '{}', false, 0);
  if h.day_wise_on and coalesce(h.per_day_rent, 0) > 0 then
    update public.rooms set rent_day = h.per_day_rent where id = rid;
  end if;
  -- a sharing with no price yet gets this price in Rent per bed
  prices := coalesce(h.sharing_prices, '[]'::jsonb);
  if not exists (select 1 from jsonb_array_elements(prices) e where (e->>'sharing')::int = p_sharing) then
    select coalesce(jsonb_agg(e order by (e->>'sharing')::int), '[]'::jsonb) into prices
    from jsonb_array_elements(prices || jsonb_build_array(jsonb_build_object('sharing', p_sharing, 'rent', p_rent))) e;
    update public.hostels set sharing_prices = prices where id = p_hostel;
  end if;
  return rid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Student home: recent messages (last 30 days, newest first)
-- ---------------------------------------------------------------------------
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
    'late_fee', coalesce(lf.fee, 0), 'late_days', coalesce(lf.days, 0), 'late_fee_per_day', coalesce(lf.per_day, 0),
    'notice_days', (select notice_days from public.hostels where id = t.hostel_id),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object('kind', m.kind, 'params', m.params, 'at', m.created_at) order by m.created_at desc)
      from (select * from public.student_messages
            where tenant_id = t.id and created_at > now() - interval '30 days'
            order by created_at desc limit 5) m), '[]'::jsonb));
end;
$$;

revoke execute on function public.update_room(uuid, text, int, int) from public, anon;
grant execute on function public.update_room(uuid, text, int, int) to authenticated;
revoke execute on function public.change_rent_day(uuid, public.rent_day_mode, int) from public, anon;
grant execute on function public.change_rent_day(uuid, public.rent_day_mode, int) to authenticated;
revoke execute on function public.rent_day_preview(uuid, public.rent_day_mode, int) from public, anon;
grant execute on function public.rent_day_preview(uuid, public.rent_day_mode, int) to authenticated;
revoke execute on function public.set_notice_days(uuid, int) from public, anon;
grant execute on function public.set_notice_days(uuid, int) to authenticated;
revoke execute on function public.add_room_simple(uuid, int, text, int, int) from public, anon;
grant execute on function public.add_room_simple(uuid, int, text, int, int) to authenticated;
revoke execute on function public.student_me_extra(uuid) from public, anon, authenticated;
grant execute on function public.student_me_extra(uuid) to service_role;
revoke execute on function private.message_student(uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function private.move_fee_date(uuid, public.rent_day_mode, int) from public, anon, authenticated;
-- messages are written only by these functions
revoke all on public.student_messages from anon;
revoke insert, update, delete on public.student_messages from authenticated;
