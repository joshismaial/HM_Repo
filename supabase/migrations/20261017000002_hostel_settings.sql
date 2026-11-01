-- Hostel settings (simple page): rent per sharing, advance / deposit on-off + amount, day-wise stay
-- on-off + per-day price, extra charges (electricity per unit, laundry per month, own charges) and
-- Google Pay / PhonePe / Paytm buttons for UPI. Wi-Fi rows are floor + password.

alter table public.hostels add column if not exists sharing_prices jsonb not null default '[]'::jsonb;
alter table public.hostels add column if not exists deposit_on     boolean not null default true;
alter table public.hostels add column if not exists deposit_amount int not null default 0;
alter table public.hostels add column if not exists day_wise_on    boolean not null default false;
alter table public.hostels add column if not exists per_day_rent   int not null default 0;
alter table public.hostels add column if not exists extra_charges  jsonb not null default
  '[{"kind":"electricity","name":"Electricity bill","amount":10,"per":"unit","on":false},
    {"kind":"laundry","name":"Laundry","amount":300,"per":"month","on":false}]'::jsonb;
alter table public.hostels add column if not exists accept_gpay    boolean not null default false;
alter table public.hostels add column if not exists accept_phonepe boolean not null default false;
alter table public.hostels add column if not exists accept_paytm   boolean not null default false;

do $$ begin
  alter table public.hostels add constraint hostels_settings_checks check (
    jsonb_typeof(sharing_prices) = 'array' and jsonb_array_length(sharing_prices) <= 12
    and jsonb_typeof(extra_charges) = 'array' and jsonb_array_length(extra_charges) <= 20
    and deposit_amount between 0 and 1000000 and per_day_rent between 0 and 50000);
exception when duplicate_object then null; end $$;

-- UPI apps the owner switched on (students see a button for each).
create or replace function private.upi_apps(p_hostel uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(a), '[]'::jsonb) from (
    select 'gpay' as a from public.hostels where id = p_hostel and accept_gpay
    union all select 'phonepe' from public.hostels where id = p_hostel and accept_phonepe
    union all select 'paytm' from public.hostels where id = p_hostel and accept_paytm) x;
$$;

-- Save rent per sharing, deposit and day-wise price, and copy them to the hostel's rooms
-- (new students pay these; students already staying keep their own rent).
create or replace function public.save_hostel_prices(
  p_hostel uuid, p_prices jsonb, p_deposit_on boolean, p_deposit_amount int, p_day_wise_on boolean, p_per_day int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  e jsonb;
  s int;
  r int;
  seen int[] := '{}';
begin
  perform private.assert_owner(p_hostel);
  if jsonb_typeof(coalesce(p_prices, '[]'::jsonb)) <> 'array' then raise exception 'INVALID_VALUE'; end if;
  for e in select x from jsonb_array_elements(coalesce(p_prices, '[]'::jsonb)) x loop
    s := (e->>'sharing')::int;
    r := (e->>'rent')::int;
    if s is null or s not between 1 and 12 then raise exception 'BAD_SHARING'; end if;
    if r is null or r <= 0 or r > 500000 then raise exception 'BAD_AMOUNT'; end if;
    if s = any(seen) then raise exception 'INVALID_VALUE'; end if;
    seen := seen || s;
  end loop;
  if coalesce(p_deposit_amount, 0) < 0 or coalesce(p_deposit_amount, 0) > 1000000 then raise exception 'BAD_AMOUNT'; end if;
  if coalesce(p_per_day, 0) < 0 or coalesce(p_per_day, 0) > 50000 then raise exception 'BAD_AMOUNT'; end if;
  if coalesce(p_day_wise_on, false) and coalesce(p_per_day, 0) <= 0 then raise exception 'BAD_AMOUNT'; end if;

  update public.hostels set
    sharing_prices = (select coalesce(jsonb_agg(jsonb_build_object('sharing', (x->>'sharing')::int, 'rent', (x->>'rent')::int)
                                                 order by (x->>'sharing')::int), '[]'::jsonb)
                        from jsonb_array_elements(coalesce(p_prices, '[]'::jsonb)) x),
    deposit_on = coalesce(p_deposit_on, false),
    deposit_amount = coalesce(p_deposit_amount, 0),
    day_wise_on = coalesce(p_day_wise_on, false),
    per_day_rent = coalesce(p_per_day, 0)
  where id = p_hostel;

  update public.rooms r set rent_month = (x->>'rent')::int
    from jsonb_array_elements(coalesce(p_prices, '[]'::jsonb)) x
   where r.hostel_id = p_hostel and r.sharing = (x->>'sharing')::int;
  update public.rooms set deposit_month = case when coalesce(p_deposit_on, false) then coalesce(p_deposit_amount, 0) else 0 end
   where hostel_id = p_hostel;
  if coalesce(p_day_wise_on, false) then
    update public.rooms set rent_day = p_per_day where hostel_id = p_hostel;
  end if;
end;
$$;

-- Wi-Fi rows are now floor + password (the network name is optional).
create or replace function private.tenant_wifi(p_tenant uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(w->>'name', ''), 'password', w->>'password', 'floor', w->'floor')
                            order by (w->>'floor') nulls first), '[]'::jsonb)
  from public.tenants t
  join public.hostels h on h.id = t.hostel_id
  left join public.beds b on b.id = t.bed_id
  left join public.rooms r on r.id = b.room_id
  cross join lateral jsonb_array_elements(h.wifi) w
  where t.id = p_tenant and t.status in ('active', 'notice')
    and coalesce(w->>'password', '') <> ''
    and (jsonb_typeof(w->'floor') is distinct from 'number' or (w->>'floor')::int = r.floor);
$$;

-- Student payment info: UPI now carries the apps the owner switched on.
create or replace function public.student_quote(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants := private.session_tenant(s);
  h public.hostels;
  fp record;
  join_date date;
begin
  if t.id is null or t.bed_id is null then raise exception 'NO_BED_HELD'; end if;
  select * into h from public.hostels where id = t.hostel_id;
  join_date := coalesce(t.joining_date, private.today());
  select * into fp from private.first_rent_period(h.rent_day_mode, h.rent_fixed_day, join_date, t.rent_month);
  return jsonb_build_object(
    'joining_date', join_date,
    'rent_period_start', fp.period_start, 'rent_period_end', fp.period_end,
    'rent_amount', fp.amount, 'prorated', fp.prorated, 'rent_month', t.rent_month,
    'deposit', coalesce(t.deposit, 0),
    'total', fp.amount + coalesce(t.deposit, 0),
    'rent_day_mode', h.rent_day_mode, 'rent_fixed_day', h.rent_fixed_day,
    'notice_days', h.notice_days,
    'payment_note', private.payment_note(t.id),
    'upi', case when h.accept_upi and h.upi_id is not null
                then jsonb_build_object('id', h.upi_id, 'name', coalesce(h.upi_payee_name, h.name), 'apps', private.upi_apps(h.id)) end,
    'bank', case when h.accept_bank then h.bank_details end,
    'cash', case when h.accept_cash then coalesce(h.cash_note, '') end,
    'held_until', (select held_until from public.beds where id = t.bed_id),
    'offline_bed', (select status = 'offline_occupied' from public.beds where id = t.bed_id),
    'room_no', (select r.room_no from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id),
    'bed_label', (select b.label from public.beds b where b.id = t.bed_id),
    'sharing', (select r.sharing from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id),
    'tenant_status', t.status, 'is_existing', t.is_existing, 'phone', s.phone);
end;
$$;

create or replace function public.student_me(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  h public.hostels;
  o public.profiles;
  bal record;
begin
  if s.tenant_id is not null then
    select * into t from public.tenants where id = s.tenant_id;
  else
    t := private.session_tenant(s);
  end if;
  if t.id is null then raise exception 'NO_BOOKING'; end if;
  select * into h from public.hostels where id = t.hostel_id;
  select * into o from public.profiles where id = h.owner_id;
  select * into bal from public.tenant_balances where tenant_id = t.id;

  return jsonb_build_object(
    'hostel', jsonb_build_object(
      'name', h.name, 'type', h.type, 'address', h.address, 'city', h.city,
      'contact_phone', h.contact_phone, 'owner_name', o.full_name,
      'notice_days', h.notice_days, 'rent_day_mode', h.rent_day_mode, 'rent_fixed_day', h.rent_fixed_day,
      'upi', case when h.accept_upi and h.upi_id is not null
                  then jsonb_build_object('id', h.upi_id, 'name', coalesce(h.upi_payee_name, h.name), 'apps', private.upi_apps(h.id)) end,
      'bank', case when h.accept_bank then h.bank_details end,
      'cash', case when h.accept_cash then coalesce(h.cash_note, '') end),
    'tenant', jsonb_build_object(
      'id', t.id, 'full_name', t.full_name, 'phone', t.phone, 'status', t.status,
      'joining_date', t.joining_date, 'is_existing', t.is_existing, 'stay_type', t.stay_type,
      'id_type', t.id_type, 'id_last4', t.id_last4,
      'parent_phone', t.parent_phone, 'reference_phone', t.reference_phone,
      'home_address', t.home_address, 'office_address', t.office_address,
      'rent_month', t.rent_month, 'deposit', t.deposit,
      'leaving_date', t.leaving_date, 'notice_given_at', t.notice_given_at,
      'room_no', (select r.room_no from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id),
      'sharing', (select r.sharing from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id),
      'bed_label', (select b.label from public.beds b where b.id = t.bed_id)),
    'balance', jsonb_build_object(
      'due_now', greatest(coalesce(bal.due_till_today, 0) - coalesce(bal.received_total, 0), 0),
      'billed_total', coalesce(bal.billed_total, 0),
      'received_total', coalesce(bal.received_total, 0)),
    'payment_note', private.payment_note(t.id),
    'bills', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'kind', b.kind, 'label', b.label, 'amount', b.amount, 'paid_amount', b.paid_amount,
        'due_date', b.due_date, 'status', b.status, 'period_start', b.period_start, 'period_end', b.period_end)
        order by b.due_date desc, b.created_at desc)
      from (select * from public.bills where tenant_id = t.id and status <> 'cancelled'
            order by due_date desc limit 24) b), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'method', p.method, 'amount_claimed', p.amount_claimed,
        'amount_received', p.amount_received, 'utr', p.utr, 'paid_on', p.paid_on,
        'status', p.status, 'created_at', p.created_at)
        order by p.created_at desc)
      from (select * from public.payments where tenant_id = t.id order by created_at desc limit 30) p), '[]'::jsonb));
end;
$$;

revoke execute on function private.upi_apps(uuid) from public, anon, authenticated;
revoke execute on function public.save_hostel_prices(uuid, jsonb, boolean, int, boolean, int) from public, anon;
grant execute on function public.save_hostel_prices(uuid, jsonb, boolean, int, boolean, int) to authenticated;
