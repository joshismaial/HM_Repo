-- 24–25 Oct 2026 decisions, database side.
--  * Register hostel (short form): hostels.area / latitude / longitude; pincode and house/street optional;
--    contact number defaults to the owner's login number.
--  * New joiner confirmation: Confirm booking / Reject with a reason, "Your booking" page data,
--    2-hour reminder to the owner (pg_cron job).
--  * Free UPI payments with checks: check results, receipt + image fingerprint stored per payment,
--    UTR can never be used twice (any hostel, any status), receipts removed from the server after 7 days.
-- Student functions are callable by the server (service_role) only; owner functions by signed-in owners only.

-- ===========================================================================
-- 1. Register hostel – short form
-- ===========================================================================
alter table public.hostels
  add column if not exists area      text,
  add column if not exists latitude  numeric(9, 6),
  add column if not exists longitude numeric(9, 6);

do $$
declare c record;
begin
  -- old rules: pincode required (6 digits), address at least 5 characters
  for c in select conname from pg_constraint
            where conrelid = 'public.hostels'::regclass and contype = 'c'
              and (pg_get_constraintdef(oid) like '%pincode%' or pg_get_constraintdef(oid) like '%FROM address%')
  loop
    execute format('alter table public.hostels drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.hostels alter column pincode drop not null;
alter table public.hostels add constraint hostels_pincode_ok
  check (pincode is null or pincode ~ '^[1-9][0-9]{5}$');
alter table public.hostels add constraint hostels_address_ok
  check (length(trim(address)) between 2 and 300);
alter table public.hostels add constraint hostels_area_ok
  check (area is null or length(trim(area)) between 2 and 80);
alter table public.hostels add constraint hostels_latitude_ok
  check (latitude is null or latitude between -90 and 90);
alter table public.hostels add constraint hostels_longitude_ok
  check (longitude is null or longitude between -180 and 180);
alter table public.hostels add constraint hostels_point_both_or_none
  check ((latitude is null) = (longitude is null));

-- Fill what the short form leaves out: address from the area, contact number from the owner's login number.
create or replace function private.hostel_defaults()
returns trigger language plpgsql security definer set search_path = '' as $$
declare ph text;
begin
  if nullif(trim(coalesce(new.address, '')), '') is null then
    new.address := new.area;
  end if;
  if new.contact_phone is null then
    select p.phone into ph from public.profiles p where p.id = new.owner_id;
    if ph ~ '^91[6-9][0-9]{9}$' then ph := '+' || ph; end if;
    new.contact_phone := ph;
  end if;
  return new;
end;
$$;
drop trigger if exists hostels_defaults on public.hostels;
create trigger hostels_defaults before insert on public.hostels
  for each row execute function private.hostel_defaults();

-- the new columns for signed-in owners (no change if the table already allows every column)
grant select (area, latitude, longitude) on public.hostels to authenticated;
grant insert (area, latitude, longitude) on public.hostels to authenticated;
grant update (area, latitude, longitude) on public.hostels to authenticated;

-- ===========================================================================
-- 2. New joiner confirmation
-- ===========================================================================
alter table public.tenants
  add column if not exists reject_reason     text,
  add column if not exists reject_note       text,
  add column if not exists rejected_at       timestamptz,
  add column if not exists owner_reminded_at timestamptz;
alter table public.tenants add constraint tenants_reject_reason_ok
  check (reject_reason is null or reject_reason in
         ('wrong_details', 'aadhaar_unclear', 'payment_not_received', 'bed_not_available', 'other'));
alter table public.tenants add constraint tenants_reject_note_ok
  check (reject_note is null or length(reject_note) <= 300);

-- tenants uses column-level privileges for owners: let them read the reason they gave
grant select (reject_reason, reject_note, rejected_at) on public.tenants to authenticated;

-- "Not received" message to the student is sent for a plain payment rejection, but not when the owner rejects a
-- booking for another reason (wrong details, Aadhaar not clear, bed not available, other).
create or replace function private.after_payment_rejected()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'rejected' and old.status = 'pending' and new.created_by = 'student'
     and coalesce(current_setting('app.skip_payment_msg', true), '') <> '1' then
    perform private.message_student(new.tenant_id,
      case when new.method = 'cash' then 'cash_not_received' else 'payment_not_received' end,
      jsonb_build_object('amount', new.amount_claimed, 'method', new.method, 'date', new.paid_on));
  end if;
  return new;
end;
$$;

-- Owner: Confirm booking (new joiner). Confirms the waiting payment for the amount paid (or the amount received).
create or replace function public.confirm_booking(p_tenant uuid, p_amount_received integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  p public.payments;
begin
  select * into t from public.tenants where id = p_tenant for update;
  perform private.assert_owner(t.hostel_id);
  if t.is_existing then raise exception 'USE_APPROVE'; end if;
  if t.status <> 'pending_approval' then raise exception 'NOT_PENDING'; end if;
  select * into p from public.payments
   where tenant_id = t.id and status = 'pending' order by created_at desc limit 1;
  if p.id is null then raise exception 'NO_PAYMENT'; end if;
  perform public.confirm_payment(p.id, coalesce(p_amount_received, p.amount_claimed));
  return jsonb_build_object('tenant_id', t.id, 'status', 'active');
end;
$$;

-- Owner: Reject booking with a reason. The bed is free for others again.
create or replace function public.reject_booking(p_tenant uuid, p_reason text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  label text;
begin
  select * into t from public.tenants where id = p_tenant for update;
  perform private.assert_owner(t.hostel_id);
  label := case p_reason
    when 'wrong_details'        then 'Wrong details'
    when 'aadhaar_unclear'      then 'Aadhaar not clear'
    when 'payment_not_received' then 'Payment not received'
    when 'bed_not_available'    then 'Bed not available'
    when 'other'                then 'Other'
  end;
  if label is null then raise exception 'BAD_REASON'; end if;
  if t.status not in ('pending_approval', 'awaiting_payment', 'draft') then raise exception 'NOT_PENDING'; end if;

  if p_reason <> 'payment_not_received' then
    perform set_config('app.skip_payment_msg', '1', true);
  end if;
  perform private.release_bed(t.bed_id, t.id);
  update public.tenants
     set status = 'rejected', reject_reason = p_reason,
         reject_note = left(nullif(trim(coalesce(p_note, '')), ''), 300), rejected_at = now()
   where id = t.id;
  update public.payments
     set status = 'rejected', decided_at = now(), recorded_by = auth.uid(),
         note = case when note is null then label else note || ' · ' || label end
   where tenant_id = t.id and status = 'pending';
  perform set_config('app.skip_payment_msg', '', true);
  return jsonb_build_object('tenant_id', t.id, 'status', 'rejected', 'reason', p_reason);
end;
$$;

-- Student "Your booking" page: where the booking stands, in one call (also works after a rejection).
create or replace function public.student_booking_status(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  h public.hostels;
  p public.payments;
  rm text;
  bd text;
  kept boolean := false;
begin
  select * into t from public.tenants
   where hostel_id = s.hostel_id and phone = s.phone order by created_at desc limit 1;
  if t.id is null then return jsonb_build_object('status', 'none'); end if;
  select * into h from public.hostels where id = t.hostel_id;
  select * into p from public.payments where tenant_id = t.id and created_by = 'student'
   order by created_at desc limit 1;
  select r.room_no, b.label, (b.held_for = t.id and b.held_until > now())
    into rm, bd, kept
    from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id;
  return jsonb_build_object(
    'status', t.status,
    'hostel_name', h.name,
    'owner_phone', h.contact_phone,
    'room_no', rm, 'bed', bd, 'bed_kept', coalesce(kept, false),
    'amount', p.amount_claimed, 'method', p.method,
    'utr_last4', case when p.utr is null then null else right(p.utr, 4) end,
    'payment_status', p.status, 'paid_at', p.created_at,
    'reject_reason', t.reject_reason, 'reject_note', t.reject_note);
end;
$$;

-- 2-hour reminder: a new joiner has paid, the owner has not answered.
create or replace function private.remind_pending_joiners()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select t.id, t.hostel_id, t.full_name from public.tenants t
     where t.status = 'pending_approval' and not t.is_existing and t.owner_reminded_at is null
       and exists (select 1 from public.payments p
                    where p.tenant_id = t.id and p.status = 'pending' and p.created_at < now() - interval '2 hours')
       for update of t skip locked
  loop
    update public.tenants set owner_reminded_at = now() where id = r.id;
    perform private.notify(r.hostel_id, 'reminder', 'New joiner waiting',
      coalesce(r.full_name, 'A new student') || ' paid more than 2 hours ago. Confirm or reject the booking.', r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('remind-pending-joiners', '*/10 * * * *', 'select private.remind_pending_joiners()');
  end if;
end $$;

-- ===========================================================================
-- 3. Free UPI payments with checks
-- ===========================================================================
alter table public.payments
  add column if not exists upi_status       text,
  add column if not exists upi_txn_ref      text,
  add column if not exists utr_from_app     boolean not null default false,
  add column if not exists pay_started_at   timestamptz,
  add column if not exists app_reply_at     timestamptz,
  add column if not exists receipt_key      text,
  add column if not exists receipt_hash     text,
  add column if not exists receipt_deleted_at timestamptz,
  add column if not exists checks           jsonb,
  add column if not exists checks_passed    int,
  add column if not exists checks_total     int;
alter table public.payments add constraint payments_upi_status_ok
  check (upi_status is null or upi_status in ('success', 'failure', 'submitted', 'unknown'));
alter table public.payments add constraint payments_receipt_key_ok
  check (receipt_key is null or length(receipt_key) <= 200);
alter table public.payments add constraint payments_receipt_hash_ok
  check (receipt_hash is null or receipt_hash ~ '^[a-f0-9]{16,128}$');

-- A UTR can be used once, ever – any hostel, any status. A "Not received" payment keeps its UTR blocked.
drop index if exists public.payments_unique_utr;
create unique index payments_unique_utr on public.payments (upper(utr)) where utr is not null;
-- The same receipt image can't back two payments (the image itself is deleted after 7 days; the fingerprint stays).
create unique index payments_unique_receipt_hash on public.payments (receipt_hash) where receipt_hash is not null;

-- owners read the check results (no change if the table already allows reading every column)
grant select (upi_status, upi_txn_ref, utr_from_app, pay_started_at, app_reply_at,
              receipt_deleted_at, checks, checks_passed, checks_total) on public.payments to authenticated;

-- The two existing student payment functions: same duplicate rule as the new index (any hostel, any status).
create or replace function public.student_submit_payment(p_session uuid, p_method public.pay_method, p_utr text, p_paid_on date default null)
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
  if v_utr is not null and exists (select 1 from public.payments where upper(payments.utr) = v_utr) then
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

create or replace function public.student_pay_bill(p_session uuid, p_method public.pay_method, p_utr text, p_amount integer, p_paid_on date default null)
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
  if v_utr is not null and v_utr !~ '^[A-Z0-9]{6,30}$' then raise exception 'UTR_REQUIRED'; end if;
  if v_utr is not null and exists (select 1 from public.payments where upper(payments.utr) = v_utr) then
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
    coalesce(' · UTR ' || v_utr, ' · look for the amount and note ' || private.payment_note(t.id)), pid);
  return jsonb_build_object('payment_id', pid);
end;
$$;

-- UPI / bank payment with the 12 checks. Works for a new joiner (first payment) and for a tenant paying rent.
-- Nothing counts as paid until the owner confirms. 7 checks on the payment, 5 on the receipt:
--   upi_success, reply_matches, utr_from_app, utr_new, amount_ok, time_ok, no_earlier_not_received,
--   r_successful, r_payee, r_utr_amount, r_after_tap (read from the receipt on the phone), r_image_new.
-- A UTR or receipt image that was used before is refused (DUPLICATE_UTR / RECEIPT_REUSED), so those two checks
-- are always true on a saved payment.
create or replace function public.student_submit_upi_payment(
  p_session uuid, p_method public.pay_method, p_utr text, p_amount integer,
  p_utr_from_app boolean, p_upi_status text, p_txn_ref text,
  p_started_at timestamptz, p_reply_at timestamptz,
  p_receipt_key text, p_receipt_hash text, p_receipt_checks jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  b public.beds;
  v_utr text := nullif(upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g')), '');
  v_hash text := nullif(lower(trim(coalesce(p_receipt_hash, ''))), '');
  rc jsonb := coalesce(p_receipt_checks, '{}'::jsonb);
  new_joiner boolean;
  due int;
  amt int;
  gap numeric;
  ck jsonb;
  passed int;
  pid uuid;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status not in ('awaiting_payment', 'active', 'notice') then
    raise exception 'NOT_READY_FOR_PAYMENT';
  end if;
  new_joiner := t.status = 'awaiting_payment';
  if p_method not in ('upi', 'bank') then raise exception 'BAD_METHOD'; end if;
  if v_utr is null or v_utr !~ '^[A-Z0-9]{6,30}$' then raise exception 'UTR_REQUIRED'; end if;
  if nullif(trim(coalesce(p_receipt_key, '')), '') is null or v_hash is null or v_hash !~ '^[a-f0-9]{16,128}$' then
    raise exception 'RECEIPT_REQUIRED';
  end if;
  if p_upi_status is not null and p_upi_status not in ('success', 'failure', 'submitted', 'unknown') then
    raise exception 'BAD_STATUS';
  end if;
  if exists (select 1 from public.payments where upper(utr) = v_utr) then raise exception 'DUPLICATE_UTR'; end if;
  if exists (select 1 from public.payments where receipt_hash = v_hash) then raise exception 'RECEIPT_REUSED'; end if;
  if (select count(*) from public.payments where tenant_id = t.id and status = 'pending') >= 3 then
    raise exception 'TOO_MANY_PENDING';
  end if;

  if new_joiner then
    select * into b from public.beds where id = t.bed_id for update;
    if b.held_for is distinct from t.id or b.held_until < now() then raise exception 'HOLD_EXPIRED'; end if;
    perform private.ensure_joining_bills(t.id);
    select coalesce(sum(amount), 0) into due from public.bills where tenant_id = t.id and status <> 'cancelled';
    amt := coalesce(p_amount, due);
  else
    select coalesce(sum(amount - paid_amount), 0) into due
      from public.bills where tenant_id = t.id and status in ('unpaid', 'partial');
    amt := p_amount;
  end if;
  if amt is null or amt <= 0 or amt > 1000000 then raise exception 'BAD_AMOUNT'; end if;

  gap := extract(epoch from (p_reply_at - p_started_at));
  ck := jsonb_build_object(
    'upi_success',             coalesce(p_upi_status = 'success', false),
    'reply_matches',           coalesce(p_txn_ref is not null and upper(p_txn_ref) = upper(private.payment_note(t.id)), false),
    'utr_from_app',            coalesce(p_utr_from_app, false),
    'utr_new',                 true,
    'amount_ok',               amt <= due and due > 0,
    'time_ok',                 coalesce(gap >= 8 and gap <= 3600 and p_started_at <= now() + interval '1 minute', false),
    'no_earlier_not_received', not exists (select 1 from public.payments x
                                            where x.tenant_id = t.id and x.status = 'rejected' and x.method in ('upi', 'bank')),
    'r_successful',            coalesce(rc -> 'successful' = 'true'::jsonb, false),
    'r_payee',                 coalesce(rc -> 'payee' = 'true'::jsonb, false),
    'r_utr_amount',            coalesce(rc -> 'utr_amount' = 'true'::jsonb, false),
    'r_after_tap',             coalesce(rc -> 'after_tap' = 'true'::jsonb, false),
    'r_image_new',             true);
  select count(*) into passed from jsonb_each(ck) where value = 'true'::jsonb;

  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, utr, payment_note, paid_on, created_by,
                               upi_status, upi_txn_ref, utr_from_app, pay_started_at, app_reply_at,
                               receipt_key, receipt_hash, checks, checks_passed, checks_total)
  values (t.hostel_id, t.id, p_method, amt, v_utr, private.payment_note(t.id), private.today(), 'student',
          p_upi_status, left(p_txn_ref, 80), coalesce(p_utr_from_app, false), p_started_at, p_reply_at,
          p_receipt_key, v_hash, ck, passed, 12)
  returning id into pid;

  if new_joiner then
    update public.tenants set status = 'pending_approval' where id = t.id;
    update public.beds set held_until = now() + interval '3 days' where id = b.id;   -- bed kept while the owner decides
  end if;

  perform private.notify(t.hostel_id, 'payment', 'Payment to check',
    coalesce(t.full_name, case when new_joiner then 'New student' else 'Tenant' end) || ' · ₹' || amt || ' · ' ||
    upper(p_method::text) || ' · UTR ' || v_utr || ' · ' ||
    case when passed = 12 then '12 of 12 checks' else 'checks failed – ' || passed || ' of 12' end, pid);

  return jsonb_build_object('payment_id', pid, 'amount', amt, 'checks_passed', passed, 'checks_total', 12,
                            'status', case when new_joiner then 'pending_approval' else t.status::text end);
end;
$$;

-- Receipt images stay on the server for 7 days (the owner's confirm window), then the server job deletes the files
-- and calls mark_receipts_purged. The fingerprint stays, so the same image can't be used again.
create or replace function public.receipts_to_purge()
returns table (payment_id uuid, receipt_key text)
language sql security definer set search_path = '' as $$
  select p.id, p.receipt_key from public.payments p
   where p.receipt_key is not null and p.receipt_deleted_at is null
     and p.created_at < now() - interval '7 days'
   order by p.created_at
   limit 500;
$$;

create or replace function public.mark_receipts_purged(p_payments uuid[])
returns void language sql security definer set search_path = '' as $$
  update public.payments set receipt_key = null, receipt_deleted_at = now()
   where id = any(p_payments) and receipt_key is not null;
$$;

-- ===========================================================================
-- 4. Who may call what
-- ===========================================================================
revoke execute on function public.student_booking_status(uuid) from public, anon, authenticated;
revoke execute on function public.student_submit_upi_payment(uuid, public.pay_method, text, integer, boolean, text, text,
  timestamptz, timestamptz, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.receipts_to_purge() from public, anon, authenticated;
revoke execute on function public.mark_receipts_purged(uuid[]) from public, anon, authenticated;
revoke execute on function public.confirm_booking(uuid, integer) from public, anon;
revoke execute on function public.reject_booking(uuid, text, text) from public, anon;
revoke execute on function public.student_submit_payment(uuid, public.pay_method, text, date) from public, anon, authenticated;
revoke execute on function public.student_pay_bill(uuid, public.pay_method, text, integer, date) from public, anon, authenticated;

grant execute on function public.student_booking_status(uuid) to service_role;
grant execute on function public.student_submit_upi_payment(uuid, public.pay_method, text, integer, boolean, text, text,
  timestamptz, timestamptz, text, text, jsonb) to service_role;
grant execute on function public.receipts_to_purge() to service_role;
grant execute on function public.mark_receipts_purged(uuid[]) to service_role;
grant execute on function public.student_submit_payment(uuid, public.pay_method, text, date) to service_role;
grant execute on function public.student_pay_bill(uuid, public.pay_method, text, integer, date) to service_role;
grant execute on function public.confirm_booking(uuid, integer) to authenticated, service_role;
grant execute on function public.reject_booking(uuid, text, text) to authenticated, service_role;
