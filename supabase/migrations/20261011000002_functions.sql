-- My Hostel – Phase 1 server-side logic
-- Owner functions run as the logged-in owner and always check ownership.
-- Student functions are called only by Edge Functions (service role) after the
-- student's access token has been checked.
-- Errors are raised with short codes (e.g. BED_TAKEN) that the app turns into messages.

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
create or replace function private.today()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'Asia/Kolkata')::date;
$$;

create or replace function private.owns_hostel(p_hostel uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.hostels h
    where h.id = p_hostel and h.owner_id = (select auth.uid())
  );
$$;

create or replace function private.assert_owner(p_hostel uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if p_hostel is null or not private.owns_hostel(p_hostel) then
    raise exception 'NOT_ALLOWED';
  end if;
end;
$$;

create or replace function private.id_key()
returns text language plpgsql stable security definer set search_path = '' as $$
declare k text;
begin
  select value into k from private.settings where name = 'id_encryption_key';
  if k is null or length(k) < 24 then
    raise exception 'ID_KEY_NOT_SET';
  end if;
  return k;
end;
$$;

create or replace function private.notify(p_hostel uuid, p_kind text, p_title text, p_body text, p_ref uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications (hostel_id, kind, title, body, ref_id)
  values (p_hostel, p_kind, p_title, p_body, p_ref);
$$;

-- First rent period for a joining date, following the hostel's rent-day rule.
-- Fixed rent day + joining on another day => per-day rent up to the rent day.
create or replace function private.first_rent_period(
  p_mode public.rent_day_mode, p_fixed_day int, p_join date, p_rent int,
  out period_start date, out period_end date, out amount int, out prorated boolean)
language plpgsql immutable set search_path = '' as $$
declare
  next_fixed date;
begin
  period_start := p_join;
  if p_mode = 'joining_date' or extract(day from p_join)::int = p_fixed_day then
    period_end := (p_join + interval '1 month')::date - 1;
    amount := p_rent;
    prorated := false;
  else
    next_fixed := make_date(extract(year from p_join)::int, extract(month from p_join)::int, p_fixed_day);
    if next_fixed <= p_join then
      next_fixed := (next_fixed + interval '1 month')::date;
    end if;
    period_end := next_fixed - 1;
    amount := round(p_rent * (period_end - period_start + 1) / 30.0)::int;
    prorated := true;
  end if;
end;
$$;

-- Next rent day on/after a date (used when an existing tenant is approved).
create or replace function private.next_rent_start(
  p_mode public.rent_day_mode, p_fixed_day int, p_join date, p_from date)
returns date language plpgsql immutable set search_path = '' as $$
declare
  d date;
  k int := 0;
begin
  if p_mode = 'fixed_day' then
    d := make_date(extract(year from p_from)::int, extract(month from p_from)::int, p_fixed_day);
    if d < p_from then d := (d + interval '1 month')::date; end if;
    return d;
  end if;
  -- joining-date cycle: first anniversary of the joining day on/after p_from
  loop
    d := (p_join + make_interval(months => k))::date;
    exit when d >= p_from or k > 1200;
    k := k + 1;
  end loop;
  return d;
end;
$$;

-- Payment note filled into the UPI app, e.g. RPH-204B-1011
create or replace function private.payment_note(p_tenant uuid)
returns text language sql stable security definer set search_path = '' as $$
  select upper(left(h.join_code, 3)) || '-' ||
         coalesce(regexp_replace(r.room_no, '[^A-Za-z0-9]', '', 'g'), '') ||
         coalesce(b.label, '') || '-' ||
         to_char(private.today(), 'MMDD')
  from public.tenants t
  join public.hostels h on h.id = t.hostel_id
  left join public.beds b on b.id = t.bed_id
  left join public.rooms r on r.id = b.room_id
  where t.id = p_tenant;
$$;

-- Spread all received money over the tenant's bills, oldest first (deposit before rent on the same day).
create or replace function private.allocate_payments(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  remaining int;
  b record;
  pay int;
begin
  select coalesce(sum(amount_received), 0) into remaining
  from public.payments where tenant_id = p_tenant and status = 'received';

  for b in
    select id, amount from public.bills
    where tenant_id = p_tenant and status <> 'cancelled'
    order by due_date, case kind when 'deposit' then 0 when 'rent' then 1 else 2 end, created_at
  loop
    pay := least(remaining, b.amount);
    remaining := remaining - pay;
    update public.bills
      set paid_amount = pay,
          status = case when pay >= amount then 'paid'::public.bill_status
                        when pay > 0 then 'partial'::public.bill_status
                        else 'unpaid'::public.bill_status end
      where id = b.id;
  end loop;
end;
$$;

-- Create the joining bills (deposit + first rent) once.
create or replace function private.ensure_joining_bills(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  h public.hostels;
  fp record;
begin
  select * into t from public.tenants where id = p_tenant;
  select * into h from public.hostels where id = t.hostel_id;
  if exists (select 1 from public.bills where tenant_id = t.id) then
    return;
  end if;
  select * into fp from private.first_rent_period(h.rent_day_mode, h.rent_fixed_day, t.joining_date, t.rent_month);
  if coalesce(t.deposit, 0) > 0 then
    insert into public.bills (hostel_id, tenant_id, kind, label, amount, due_date)
    values (t.hostel_id, t.id, 'deposit', 'Security deposit', t.deposit, t.joining_date);
  end if;
  insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
  values (t.hostel_id, t.id, 'rent',
          'Rent ' || to_char(fp.period_start, 'DD Mon') || ' – ' || to_char(fp.period_end, 'DD Mon'),
          fp.period_start, fp.period_end, fp.amount, fp.period_start);
end;
$$;

-- Free a bed that a tenant was holding (not used for occupied beds).
create or replace function private.release_bed(p_bed uuid, p_tenant uuid)
returns void language sql security definer set search_path = '' as $$
  update public.beds
     set status = case when status = 'held' then 'vacant'::public.bed_status else status end,
         held_until = null,
         held_for = null
   where id = p_bed and held_for = p_tenant and status in ('held', 'offline_occupied');
$$;

-- ---------------------------------------------------------------------------
-- STUDENT functions (service role only; called by the student-api Edge Function)
-- ---------------------------------------------------------------------------

-- Load a session; raise if missing or revoked.
create or replace function private.session_row(p_session uuid)
returns public.student_sessions language plpgsql security definer set search_path = '' as $$
declare s public.student_sessions;
begin
  select * into s from public.student_sessions where id = p_session and revoked_at is null;
  if not found then
    raise exception 'SESSION_INVALID';
  end if;
  update public.student_sessions set last_used_at = now() where id = p_session;
  return s;
end;
$$;

-- Live tenant row for the session's phone at the session's hostel (may be null).
create or replace function private.session_tenant(s public.student_sessions)
returns public.tenants language sql stable security definer set search_path = '' as $$
  select t.* from public.tenants t
  where t.hostel_id = s.hostel_id and t.phone = s.phone
    and t.status not in ('vacated', 'rejected', 'expired')
  order by t.created_at desc
  limit 1;
$$;

-- After OTP check: create a session for a phone at a hostel (by join code).
create or replace function public.student_start_session(p_join_code text, p_phone text, p_token_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  h public.hostels;
  sid uuid;
  t public.tenants;
begin
  select * into h from public.hostels where join_code = upper(trim(p_join_code));
  if not found then raise exception 'HOSTEL_NOT_FOUND'; end if;
  if p_phone !~ '^\+91[6-9][0-9]{9}$' then raise exception 'BAD_PHONE'; end if;

  select * into t from public.tenants
   where hostel_id = h.id and phone = p_phone and status not in ('vacated', 'rejected', 'expired')
   order by created_at desc limit 1;

  insert into public.student_sessions (hostel_id, phone, tenant_id, token_hash)
  values (h.id, p_phone, t.id, p_token_hash)
  returning id into sid;

  return jsonb_build_object('session_id', sid, 'hostel_id', h.id,
                            'tenant_id', t.id, 'tenant_status', t.status);
end;
$$;

-- Look up a session by token hash (used for every student request).
create or replace function public.student_session_by_hash(p_token_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.student_sessions;
begin
  select * into s from public.student_sessions where token_hash = p_token_hash and revoked_at is null;
  if not found then raise exception 'SESSION_INVALID'; end if;
  -- links stop working 3 months after the tenant leaves
  if s.tenant_id is not null and exists (
       select 1 from public.tenants t where t.id = s.tenant_id
       and t.status = 'vacated' and t.vacated_at < now() - interval '90 days') then
    raise exception 'SESSION_INVALID';
  end if;
  return jsonb_build_object('session_id', s.id, 'hostel_id', s.hostel_id, 'phone', s.phone, 'tenant_id', s.tenant_id);
end;
$$;

-- Hostel details shown after the mobile is verified.
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
    'tenant_id', t.id, 'tenant_status', t.status);
end;
$$;

-- Rooms with each bed's state from this student's point of view.
create or replace function public.student_rooms(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants := private.session_tenant(s);
begin
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
    from public.rooms r where r.hostel_id = s.hostel_id
  ), '[]'::jsonb);
end;
$$;

-- Hold a bed for 15 minutes (only one student can hold a bed at a time).
create or replace function public.student_hold_bed(p_session uuid, p_bed uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  h public.hostels;
  t public.tenants;
  b public.beds;
  r public.rooms;
  free boolean;
begin
  select * into h from public.hostels where id = s.hostel_id;
  if not h.is_open then raise exception 'HOSTEL_CLOSED'; end if;

  t := private.session_tenant(s);
  if t.id is not null and t.status not in ('draft', 'awaiting_payment') then
    raise exception 'ALREADY_JOINED';
  end if;

  -- lock the bed row so two students can't take it at the same time
  select * into b from public.beds where id = p_bed and hostel_id = s.hostel_id for update;
  if not found then raise exception 'BED_NOT_FOUND'; end if;
  select * into r from public.rooms where id = b.room_id;

  free := coalesce(
            (b.status = 'vacant')
         or (b.status = 'held' and (b.held_until < now() or (t.id is not null and b.held_for = t.id)))
         or (b.status = 'offline_occupied' and (b.held_for is null or b.held_until < now()
                                                 or (t.id is not null and b.held_for = t.id))),
          false);
  if not free then raise exception 'BED_TAKEN'; end if;

  if t.id is null then
    insert into public.tenants (hostel_id, phone, status)
    values (s.hostel_id, s.phone, 'draft')
    returning * into t;
    update public.student_sessions set tenant_id = t.id where id = s.id;
  elsif t.bed_id is not null and t.bed_id <> p_bed then
    perform private.release_bed(t.bed_id, t.id);
  end if;

  update public.beds
     set status = case when status = 'offline_occupied' then status else 'held'::public.bed_status end,
         held_until = now() + interval '15 minutes',
         held_for = t.id
   where id = p_bed;

  update public.tenants
     set bed_id = p_bed, rent_month = r.rent_month, deposit = r.deposit_month,
         status = 'draft'
   where id = t.id;

  return jsonb_build_object('tenant_id', t.id, 'bed_id', p_bed,
                            'room_no', r.room_no, 'bed_label', b.label,
                            'held_until', now() + interval '15 minutes',
                            'offline_bed', b.status = 'offline_occupied');
end;
$$;

-- Amount for a new joiner: first rent (per-day up to the rent day if needed) + deposit.
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
                then jsonb_build_object('id', h.upi_id, 'name', coalesce(h.upi_payee_name, h.name)) end,
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

-- Save the student's details (new joiner or existing tenant).
create or replace function public.student_submit_details(
  p_session uuid,
  p_full_name text, p_parent_phone text, p_reference_phone text,
  p_id_type public.id_type, p_id_number text,
  p_id_file_key text, p_photo_key text,
  p_home_address text, p_office_address text,
  p_is_existing boolean, p_joining_date date, p_consent boolean)
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

  -- ID number checks
  digits := regexp_replace(coalesce(p_id_number, ''), '\s', '', 'g');
  if p_id_type = 'aadhaar' and digits !~ '^[0-9X]{8}[0-9]{4}$' then raise exception 'BAD_ID_NUMBER'; end if;
  if p_id_type <> 'aadhaar' and digits !~ '^[A-Za-z0-9-]{6,20}$' then raise exception 'BAD_ID_NUMBER'; end if;
  if p_id_file_key is null or p_photo_key is null then raise exception 'FILES_REQUIRED'; end if;

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
    is_existing = p_is_existing,
    joining_date = join_date,
    consent_at = now(),
    status = case when p_is_existing then 'pending_approval'::public.tenant_status
                  else 'awaiting_payment'::public.tenant_status end
  where id = t.id;

  if p_is_existing then
    -- keep the bed for the owner to check (7 days)
    update public.beds set held_until = now() + interval '7 days' where id = b.id;
    perform private.notify(t.hostel_id, 'existing_tenant', 'Existing tenant to approve',
      trim(p_full_name) || ' says they joined on ' || to_char(join_date, 'DD Mon YYYY'), t.id);
    return jsonb_build_object('tenant_id', t.id, 'status', 'pending_approval');
  end if;

  update public.beds set held_until = greatest(held_until, now() + interval '10 minutes') where id = b.id;
  return jsonb_build_object('tenant_id', t.id, 'status', 'awaiting_payment');
end;
$$;

-- New joiner sends payment details (UPI / bank with UTR, or cash).
create or replace function public.student_submit_payment(
  p_session uuid, p_method public.pay_method, p_utr text, p_paid_on date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants := private.session_tenant(s);
  b public.beds;
  total int;
  v_utr text := nullif(upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g')), '');
  pid uuid;
begin
  if t.id is null or t.status <> 'awaiting_payment' then raise exception 'NOT_READY_FOR_PAYMENT'; end if;
  if p_method not in ('upi', 'bank', 'cash') then raise exception 'BAD_METHOD'; end if;
  if p_method in ('upi', 'bank') and (v_utr is null or v_utr !~ '^[A-Z0-9]{6,30}$') then raise exception 'UTR_REQUIRED'; end if;
  if v_utr is not null and exists (select 1 from public.payments
      where hostel_id = t.hostel_id and upper(payments.utr) = v_utr and status <> 'rejected') then
    raise exception 'DUPLICATE_UTR';
  end if;

  select * into b from public.beds where id = t.bed_id for update;
  if b.held_for is distinct from t.id or b.held_until < now() then raise exception 'HOLD_EXPIRED'; end if;

  perform private.ensure_joining_bills(t.id);
  select sum(amount) into total from public.bills where tenant_id = t.id and status <> 'cancelled';

  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, utr, payment_note, paid_on, created_by)
  values (t.hostel_id, t.id, p_method, total, case when p_method = 'cash' then null else v_utr end,
          private.payment_note(t.id), coalesce(p_paid_on, private.today()), 'student')
  returning id into pid;

  update public.tenants set status = 'pending_approval' where id = t.id;
  -- keep the bed while the owner checks the payment
  update public.beds set held_until = now() + interval '3 days' where id = b.id;

  perform private.notify(t.hostel_id, 'payment', 'Payment to check',
    coalesce(t.full_name, 'New student') || ' · ₹' || total || ' · ' || upper(p_method::text) ||
    coalesce(' · UTR ' || v_utr, ''), pid);

  return jsonb_build_object('payment_id', pid, 'amount', total, 'status', 'pending_approval');
end;
$$;

-- Everything the "My stay" and "Pay rent" pages need.
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
                  then jsonb_build_object('id', h.upi_id, 'name', coalesce(h.upi_payee_name, h.name)) end,
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

-- Active tenant pays a bill (UPI / bank with UTR, or cash).
create or replace function public.student_pay_bill(
  p_session uuid, p_method public.pay_method, p_utr text, p_amount int, p_paid_on date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  v_utr text := nullif(upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g')), '');
  pid uuid;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status not in ('active', 'notice') then raise exception 'NOT_ACTIVE'; end if;
  if p_method not in ('upi', 'bank', 'cash') then raise exception 'BAD_METHOD'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000 then raise exception 'BAD_AMOUNT'; end if;
  if p_method in ('upi', 'bank') and (v_utr is null or v_utr !~ '^[A-Z0-9]{6,30}$') then raise exception 'UTR_REQUIRED'; end if;
  if v_utr is not null and exists (select 1 from public.payments
      where hostel_id = t.hostel_id and upper(payments.utr) = v_utr and status <> 'rejected') then
    raise exception 'DUPLICATE_UTR';
  end if;
  if (select count(*) from public.payments where tenant_id = t.id and status = 'pending') >= 3 then
    raise exception 'TOO_MANY_PENDING';
  end if;

  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, utr, payment_note, paid_on, created_by)
  values (t.hostel_id, t.id, p_method, p_amount, case when p_method = 'cash' then null else v_utr end,
          private.payment_note(t.id), coalesce(p_paid_on, private.today()), 'student')
  returning id into pid;

  perform private.notify(t.hostel_id, 'payment', 'Payment to check',
    coalesce(t.full_name, 'Tenant') || ' · ₹' || p_amount || ' · ' || upper(p_method::text) ||
    coalesce(' · UTR ' || v_utr, ''), pid);
  return jsonb_build_object('payment_id', pid);
end;
$$;

-- Student gives notice to leave.
create or replace function public.student_give_notice(p_session uuid, p_leaving_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  h public.hostels;
  days int;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status <> 'active' then raise exception 'NOT_ACTIVE'; end if;
  if p_leaving_date is null or p_leaving_date < private.today() then raise exception 'BAD_DATE'; end if;
  select * into h from public.hostels where id = t.hostel_id;
  days := p_leaving_date - private.today();
  update public.tenants set status = 'notice', notice_given_at = now(), leaving_date = p_leaving_date where id = t.id;
  perform private.notify(t.hostel_id, 'notice', 'Leaving notice',
    coalesce(t.full_name, 'Tenant') || ' will leave on ' || to_char(p_leaving_date, 'DD Mon') ||
    ' (' || days || ' days'' notice)', t.id);
  return jsonb_build_object('days', days, 'enough_notice', days >= h.notice_days, 'notice_days', h.notice_days);
end;
$$;

-- ---------------------------------------------------------------------------
-- OWNER functions (logged-in owners)
-- ---------------------------------------------------------------------------

-- Add a room and its beds (A, B, C…). p_offline_beds = beds already used by tenants not yet on the app.
create or replace function public.add_room(
  p_hostel uuid, p_room_no text, p_floor int, p_sharing int, p_rent int, p_deposit int,
  p_features text[] default '{}', p_separate_meter boolean default false, p_offline_beds int default 0)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  rid uuid;
  i int;
begin
  perform private.assert_owner(p_hostel);
  if p_offline_beds < 0 or p_offline_beds > p_sharing then raise exception 'BAD_OFFLINE_BEDS'; end if;
  insert into public.rooms (hostel_id, room_no, floor, sharing, rent_month, deposit_month, features, separate_meter)
  values (p_hostel, trim(p_room_no), p_floor, p_sharing, p_rent, coalesce(p_deposit, 0),
          coalesce(p_features, '{}'), coalesce(p_separate_meter, false))
  returning id into rid;
  for i in 1..p_sharing loop
    insert into public.beds (room_id, hostel_id, label, status)
    values (rid, p_hostel, chr(64 + i),
            case when i <= p_offline_beds then 'offline_occupied'::public.bed_status else 'vacant'::public.bed_status end);
  end loop;
  return rid;
end;
$$;

-- Delete a room only if nobody lives in it.
create or replace function public.delete_room(p_room uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.rooms;
begin
  select * into r from public.rooms where id = p_room;
  perform private.assert_owner(r.hostel_id);
  if exists (select 1 from public.tenants t join public.beds b on b.id = t.bed_id
             where b.room_id = p_room and t.status not in ('vacated', 'rejected', 'expired')) then
    raise exception 'ROOM_IN_USE';
  end if;
  delete from public.rooms where id = p_room;
end;
$$;

-- Mark a bed as used by a tenant who isn't on the app yet (or undo).
create or replace function public.set_bed_offline(p_bed uuid, p_offline boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare b public.beds;
begin
  select * into b from public.beds where id = p_bed for update;
  perform private.assert_owner(b.hostel_id);
  if b.status not in ('vacant', 'offline_occupied') or (b.held_for is not null and b.held_until > now()) then
    raise exception 'BED_IN_USE';
  end if;
  update public.beds set status = case when p_offline then 'offline_occupied'::public.bed_status
                                       else 'vacant'::public.bed_status end,
                         held_for = null, held_until = null
   where id = p_bed;
end;
$$;

-- Make a tenant active (used after payment confirmation or approval).
create or replace function private.activate_tenant(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  h public.hostels;
  start_d date;
  end_d date;
begin
  select * into t from public.tenants where id = p_tenant for update;
  if t.status not in ('pending_approval', 'awaiting_payment') then return; end if;
  select * into h from public.hostels where id = t.hostel_id;

  update public.beds set status = 'occupied', held_for = null, held_until = null where id = t.bed_id;
  update public.tenants set status = 'active' where id = t.id;

  if t.is_existing then
    -- existing tenant: billing starts from the next rent day
    if not exists (select 1 from public.bills where tenant_id = t.id and kind = 'rent') then
      start_d := private.next_rent_start(h.rent_day_mode, h.rent_fixed_day, t.joining_date, private.today());
      end_d := (start_d + interval '1 month')::date - 1;
      insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
      values (t.hostel_id, t.id, 'rent', 'Rent ' || to_char(start_d, 'DD Mon') || ' – ' || to_char(end_d, 'DD Mon'),
              start_d, end_d, t.rent_month, start_d);
    end if;
  else
    perform private.ensure_joining_bills(t.id);
  end if;
  perform private.allocate_payments(t.id);
end;
$$;

-- Owner checked the bank/UPI app and marks a payment received (amount can be less = part-payment).
create or replace function public.confirm_payment(p_payment uuid, p_amount_received int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.payments;
begin
  select * into p from public.payments where id = p_payment for update;
  perform private.assert_owner(p.hostel_id);
  if p.status <> 'pending' then raise exception 'ALREADY_DECIDED'; end if;
  if p_amount_received is null or p_amount_received <= 0 then raise exception 'BAD_AMOUNT'; end if;
  update public.payments
     set status = 'received', amount_received = p_amount_received, decided_at = now(), recorded_by = auth.uid()
   where id = p_payment;
  perform private.activate_tenant(p.tenant_id);   -- no-op if already active
  perform private.allocate_payments(p.tenant_id);
  return jsonb_build_object('tenant_id', p.tenant_id, 'part_payment', p_amount_received < p.amount_claimed);
end;
$$;

-- Owner did not receive the money.
create or replace function public.reject_payment(p_payment uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  p public.payments;
  t public.tenants;
begin
  select * into p from public.payments where id = p_payment for update;
  perform private.assert_owner(p.hostel_id);
  if p.status <> 'pending' then raise exception 'ALREADY_DECIDED'; end if;
  update public.payments set status = 'rejected', decided_at = now(), recorded_by = auth.uid(),
         note = coalesce(p_reason, note)
   where id = p_payment;
  select * into t from public.tenants where id = p.tenant_id;
  if t.status = 'pending_approval' and not t.is_existing
     and not exists (select 1 from public.payments where tenant_id = t.id and status = 'pending') then
    update public.tenants set status = 'awaiting_payment' where id = t.id;
    update public.beds set held_until = now() + interval '1 day' where id = t.bed_id and held_for = t.id;
  end if;
end;
$$;

-- Approve a joining request (mainly existing tenants who joined before the app).
create or replace function public.approve_tenant(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare t public.tenants;
begin
  select * into t from public.tenants where id = p_tenant;
  perform private.assert_owner(t.hostel_id);
  if t.status <> 'pending_approval' then raise exception 'NOT_PENDING'; end if;
  perform private.activate_tenant(t.id);
end;
$$;

create or replace function public.reject_tenant(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare t public.tenants;
begin
  select * into t from public.tenants where id = p_tenant for update;
  perform private.assert_owner(t.hostel_id);
  if t.status not in ('pending_approval', 'awaiting_payment', 'draft') then raise exception 'NOT_PENDING'; end if;
  perform private.release_bed(t.bed_id, t.id);
  update public.tenants set status = 'rejected' where id = t.id;
  update public.payments set status = 'rejected', decided_at = now(), recorded_by = auth.uid()
   where tenant_id = t.id and status = 'pending';
end;
$$;

-- Cash / cheque / any payment the owner received directly.
create or replace function public.record_payment(
  p_tenant uuid, p_amount int, p_method public.pay_method, p_paid_on date, p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  pid uuid;
begin
  select * into t from public.tenants where id = p_tenant;
  perform private.assert_owner(t.hostel_id);
  if t.status not in ('active', 'notice', 'pending_approval', 'vacated') then raise exception 'NOT_ACTIVE'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000 then raise exception 'BAD_AMOUNT'; end if;
  if p_paid_on is null or p_paid_on > private.today() then raise exception 'BAD_DATE'; end if;
  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, amount_received, paid_on,
                               status, note, created_by, recorded_by, decided_at)
  values (t.hostel_id, t.id, p_method, p_amount, p_amount, p_paid_on, 'received', p_note, 'owner', auth.uid(), now())
  returning id into pid;
  perform private.allocate_payments(t.id);
  return pid;
end;
$$;

-- Show the full ID number (logged every time).
create or replace function public.reveal_id_number(p_tenant uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare t public.tenants;
begin
  select * into t from public.tenants where id = p_tenant;
  perform private.assert_owner(t.hostel_id);
  if t.id_number_enc is null then return null; end if;
  insert into public.id_reveal_log (tenant_id, revealed_by) values (t.id, auth.uid());
  return extensions.pgp_sym_decrypt(t.id_number_enc, private.id_key());
end;
$$;

-- Tenant leaves: free the bed, cancel future bills, work out the deposit refund.
create or replace function public.mark_vacated(p_tenant uuid, p_deduction int default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  h public.hostels;
  deposit_paid int;
  enough_notice boolean;
  refund int;
begin
  select * into t from public.tenants where id = p_tenant for update;
  perform private.assert_owner(t.hostel_id);
  if t.status not in ('active', 'notice') then raise exception 'NOT_ACTIVE'; end if;
  select * into h from public.hostels where id = t.hostel_id;

  select coalesce(sum(paid_amount), 0) into deposit_paid
    from public.bills where tenant_id = t.id and kind = 'deposit' and status <> 'cancelled';
  enough_notice := t.notice_given_at is not null and t.leaving_date is not null
                   and (t.leaving_date - (t.notice_given_at at time zone 'Asia/Kolkata')::date) >= h.notice_days;
  refund := case when enough_notice then greatest(deposit_paid - greatest(coalesce(p_deduction, 0), 0), 0) else 0 end;

  update public.bills set status = 'cancelled'
   where tenant_id = t.id and status = 'unpaid' and due_date > private.today();
  update public.beds set status = 'vacant', held_for = null, held_until = null where id = t.bed_id;
  update public.tenants set status = 'vacated', vacated_at = now(),
         deposit_deduction = greatest(coalesce(p_deduction, 0), 0), deposit_refund = refund
   where id = t.id;
  return jsonb_build_object('deposit_paid', deposit_paid, 'enough_notice', enough_notice, 'refund', refund);
end;
$$;

-- Numbers for the owner's Home tab.
create or replace function public.hostel_summary(p_hostel uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  month_start date := date_trunc('month', private.today())::date;
begin
  perform private.assert_owner(p_hostel);
  return jsonb_build_object(
    'beds_total', (select count(*) from public.beds where hostel_id = p_hostel),
    'beds_filled', (select count(*) from public.beds where hostel_id = p_hostel and status in ('occupied', 'offline_occupied')),
    'beds_held', (select count(*) from public.beds where hostel_id = p_hostel and status = 'held' and held_until > now()),
    'rooms', (select count(*) from public.rooms where hostel_id = p_hostel),
    'collected_month', (select coalesce(sum(amount_received), 0) from public.payments
                        where hostel_id = p_hostel and status = 'received' and paid_on >= month_start),
    'pending_amount', (select coalesce(sum(greatest(b.amount - b.paid_amount, 0)), 0) from public.bills b
                       join public.tenants t on t.id = b.tenant_id
                       where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial')
                         and b.due_date <= private.today() and t.status in ('active', 'notice')),
    'pending_tenants', (select count(distinct b.tenant_id) from public.bills b
                        join public.tenants t on t.id = b.tenant_id
                        where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial')
                          and b.due_date <= private.today() and t.status in ('active', 'notice')),
    'payments_to_check', (select count(*) from public.payments where hostel_id = p_hostel and status = 'pending'),
    'joins_to_approve', (select count(*) from public.tenants where hostel_id = p_hostel
                         and status = 'pending_approval' and is_existing),
    'leaving', (select count(*) from public.tenants where hostel_id = p_hostel and status = 'notice'),
    'tenants', (select count(*) from public.tenants where hostel_id = p_hostel and status in ('active', 'notice')),
    'unread_notifications', (select count(*) from public.notifications where hostel_id = p_hostel and read_at is null));
end;
$$;

-- Rent tab: this month's collection and who still has to pay.
create or replace function public.rent_overview(p_hostel uuid, p_month date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  m_start date := date_trunc('month', coalesce(p_month, private.today()))::date;
  m_end date := (date_trunc('month', coalesce(p_month, private.today())) + interval '1 month')::date - 1;
begin
  perform private.assert_owner(p_hostel);
  return jsonb_build_object(
    'month_start', m_start,
    'billed', (select coalesce(sum(amount), 0) from public.bills
               where hostel_id = p_hostel and status <> 'cancelled' and due_date between m_start and m_end),
    'collected', (select coalesce(sum(amount_received), 0) from public.payments
                  where hostel_id = p_hostel and status = 'received' and paid_on between m_start and m_end),
    'to_check', (select count(*) from public.payments where hostel_id = p_hostel and status = 'pending'),
    'pending', coalesce((
      select jsonb_agg(x order by x.days_late desc) from (
        select t.id as tenant_id, t.full_name, t.phone, r.room_no, b2.label as bed_label,
               sum(greatest(b.amount - b.paid_amount, 0))::int as due,
               (private.today() - min(b.due_date))::int as days_late
        from public.bills b
        join public.tenants t on t.id = b.tenant_id
        left join public.beds b2 on b2.id = t.bed_id
        left join public.rooms r on r.id = b2.room_id
        where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial')
          and b.due_date <= greatest(m_end, private.today()) and b.due_date <= private.today()
          and t.status in ('active', 'notice')
        group by t.id, t.full_name, t.phone, r.room_no, b2.label
      ) x), '[]'::jsonb));
end;
$$;

create or replace function public.mark_notifications_read(p_hostel uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.assert_owner(p_hostel);
  update public.notifications set read_at = now() where hostel_id = p_hostel and read_at is null;
end;
$$;

-- Account deletion (required by Google Play and the App Store). Deleted after 7 days unless cancelled.
create or replace function public.request_account_deletion()
returns void language sql security definer set search_path = '' as $$
  update public.profiles set delete_requested_at = now() where id = auth.uid();
$$;

create or replace function public.cancel_account_deletion()
returns void language sql security definer set search_path = '' as $$
  update public.profiles set delete_requested_at = null where id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- SCHEDULED jobs (service role / pg_cron)
-- ---------------------------------------------------------------------------

-- Free beds whose 15-minute hold ran out before the student finished.
create or replace function public.release_expired_holds()
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  with expired as (
    update public.beds b
       set status = case when b.status = 'held' then 'vacant'::public.bed_status else b.status end,
           held_for = null, held_until = null
     where b.held_for is not null and b.held_until < now()
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

-- Create next month's rent bills 3 days before they start.
create or replace function public.generate_rent_bills(p_today date default null)
returns int language plpgsql security definer set search_path = '' as $$
declare
  today date := coalesce(p_today, private.today());
  t record;
  last_end date;
  s_d date;
  e_d date;
  n int := 0;
begin
  for t in select * from public.tenants where status in ('active', 'notice') and stay_type = 'monthly' loop
    select max(period_end) into last_end from public.bills where tenant_id = t.id and kind = 'rent';
    if last_end is null then continue; end if;
    loop
      s_d := last_end + 1;
      exit when s_d > today + 3;
      exit when t.status = 'notice' and t.leaving_date is not null and s_d > t.leaving_date;
      e_d := (s_d + interval '1 month')::date - 1;
      insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
      values (t.hostel_id, t.id, 'rent', 'Rent ' || to_char(s_d, 'DD Mon') || ' – ' || to_char(e_d, 'DD Mon'),
              s_d, e_d, t.rent_month, s_d)
      on conflict do nothing;
      n := n + 1;
      last_end := e_d;
    end loop;
    perform private.allocate_payments(t.id);
  end loop;
  return n;
end;
$$;

-- ID copies and photos to delete (3 months after leaving).
create or replace function public.files_to_purge()
returns table (tenant_id uuid, id_file_key text, photo_key text)
language sql stable security definer set search_path = '' as $$
  select id, id_file_key, photo_key from public.tenants
  where status in ('vacated', 'rejected', 'expired')
    and files_purged_at is null
    and (id_file_key is not null or photo_key is not null)
    and coalesce(vacated_at, updated_at) < now() - interval '90 days'
  limit 500;
$$;

create or replace function public.mark_files_purged(p_tenants uuid[])
returns void language sql security definer set search_path = '' as $$
  update public.tenants set id_file_key = null, photo_key = null, id_number_enc = null, files_purged_at = now()
  where id = any (p_tenants);
$$;

create or replace function public.accounts_to_delete()
returns table (user_id uuid) language sql stable security definer set search_path = '' as $$
  select id from public.profiles where delete_requested_at < now() - interval '7 days' limit 100;
$$;
