-- 24–25 Oct 2026: Register hostel (short form), New joiner confirmation (Confirm / Reject with reason,
-- booking status, 2-hour reminder), free UPI payments with 12 checks, receipt purge, permissions.
-- Run after migration 20261028000001_oct24_25_features.sql. Ends with OCT24_25_TESTS_PASSED.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, phone, raw_user_meta_data) values
  ('99999999-0000-9999-9999-999999999901', '+919848000901', '{"full_name":"Short Owner"}'),
  ('99999999-0000-9999-9999-999999999902', '+919848000902', '{"full_name":"Other Owner"}'),
  ('99999999-0000-9999-9999-999999999903', '919848000903',  '{"full_name":"No Plus Owner"}');

-- ---------- Register hostel: short form ----------
set role authenticated;
set request.jwt.claim.sub = '99999999-0000-9999-9999-999999999901';
insert into public.hostels (name, type, city, area, latitude, longitude)
values ('Sunrise Boys PG', 'mens', 'Hyderabad', 'Madhapur', 17.443500, 78.377200)
returning id as h1 \gset
select set_config('app.h1', :'h1', false);
do $$
declare h public.hostels;
begin
  select * into h from public.hostels where id = current_setting('app.h1')::uuid;
  assert h.contact_phone = '+919848000901', 'contact number = owner login number';
  assert h.address = 'Madhapur', 'address made from the area';
  assert h.pincode is null, 'pincode is optional';
  assert h.latitude = 17.4435 and h.longitude = 78.3772, 'exact point saved';
  begin
    insert into public.hostels (name, type, city, area, latitude) values ('Half Point', 'mens', 'Hyderabad', 'Kondapur', 17.4);
    raise exception 'should fail';
  exception when check_violation then null; end;
  begin
    insert into public.hostels (name, type, city, area, latitude, longitude) values ('Bad Point', 'mens', 'Hyderabad', 'Kondapur', 95, 78);
    raise exception 'should fail';
  exception when check_violation then null; end;
  begin
    insert into public.hostels (name, type, city, area, pincode) values ('Bad Pin', 'mens', 'Hyderabad', 'Kondapur', '12345');
    raise exception 'should fail';
  exception when check_violation then null; end;
end $$;
set request.jwt.claim.sub = '99999999-0000-9999-9999-999999999903';
insert into public.hostels (name, type, city, area) values ('No Plus Hostel', 'womens', 'Hyderabad', 'Gachibowli') returning id as h3 \gset
select set_config('app.h3', :'h3', false);
do $$ begin
  assert (select contact_phone from public.hostels where id = current_setting('app.h3')::uuid) = '+919848000903', 'number without + is fixed';
end $$;
set request.jwt.claim.sub = '99999999-0000-9999-9999-999999999901';

-- ---------- setup: two rooms, four new joiners waiting to pay ----------
select public.add_room(:'h1', '301', 3, 2, 5000, 3000, '{}', false, 0) as room1 \gset
select public.add_room(:'h1', '302', 3, 2, 5000, 3000, '{}', false, 0) as room2 \gset
reset role;
do $$
declare
  n int := 0; b record;
begin
  for b in select id, row_number() over (order by (select room_no from public.rooms r where r.id = beds.room_id), label) as rn
             from public.beds where hostel_id = current_setting('app.h1')::uuid order by 2
  loop
    n := n + 1;
    insert into public.tenants (id, hostel_id, full_name, phone, status, bed_id, rent_month, deposit, joining_date)
    values (('e9e9e9e9-0000-0000-0000-00000000000' || n)::uuid, current_setting('app.h1')::uuid, (array['Anita','Kiran','Meena','Divya'])[n],
            '+91900000090' || n, 'awaiting_payment', b.id, 5000, 3000, current_date);
    update public.beds set status = 'held', held_for = ('e9e9e9e9-0000-0000-0000-00000000000' || n)::uuid,
           held_until = now() + interval '1 hour' where id = b.id;
    insert into public.student_sessions (id, hostel_id, phone, tenant_id, token_hash)
    values (('a9a9a9a9-0000-0000-0000-00000000000' || n)::uuid, current_setting('app.h1')::uuid, '+91900000090' || n,
            ('e9e9e9e9-0000-0000-0000-00000000000' || n)::uuid, 'hash-oct24-' || n);
  end loop;
  assert n = 4, 'four joiners set up';
end $$;

-- ---------- UPI payment, all 12 checks pass ----------
do $$
declare
  s uuid := 'a9a9a9a9-0000-0000-0000-000000000001';
  t uuid := 'e9e9e9e9-0000-0000-0000-000000000001';
  r jsonb;
begin
  r := public.student_submit_upi_payment(s, 'upi', 'TEST1234567890', null, true, 'success', private.payment_note(t),
         now() - interval '40 seconds', now() - interval '5 seconds', 'receipts/p1.jpg', 'aaaaaaaaaaaaaaaa1111',
         '{"successful":true,"payee":true,"utr_amount":true,"after_tap":true}');
  assert (r->>'checks_passed')::int = 12 and (r->>'checks_total')::int = 12, '12 of 12 checks';
  assert (r->>'amount')::int = (select sum(amount) from public.bills where tenant_id = t), 'full amount of the joining bills';
  assert (select status from public.tenants where id = t) = 'pending_approval', 'waits for the owner';
  assert (select status from public.payments where id = (r->>'payment_id')::uuid) = 'pending', 'nothing counts as paid yet';
  assert (select held_until from public.beds where held_for = t) > now() + interval '2 days', 'bed kept while the owner decides';
  assert exists (select 1 from public.notifications where kind = 'payment' and body like '%12 of 12 checks%'), 'owner told';
end $$;

-- ---------- UPI payment, checks fail (typed UTR, no match, too quick) – saved, owner decides ----------
do $$
declare
  s uuid := 'a9a9a9a9-0000-0000-0000-000000000002';
  r jsonb;
begin
  r := public.student_submit_upi_payment(s, 'upi', 'TEST1234567891', null, false, 'unknown', 'WRONG-NOTE',
         now() - interval '2 seconds', now(), 'receipts/p2.jpg', 'bbbbbbbbbbbbbbbb2222', '{}');
  assert (r->>'checks_passed')::int < 12, 'some checks failed';
  assert (select checks->>'utr_from_app' = 'false' and checks->>'reply_matches' = 'false' and checks->>'time_ok' = 'false'
            from public.payments where id = (r->>'payment_id')::uuid), 'failed checks are listed';
  assert exists (select 1 from public.notifications where body like '%checks failed%'), 'owner sees "checks failed"';
end $$;

-- ---------- refused payments ----------
do $$
declare
  s uuid := 'a9a9a9a9-0000-0000-0000-000000000003';
  t uuid := 'e9e9e9e9-0000-0000-0000-000000000003';
  note text := private.payment_note('e9e9e9e9-0000-0000-0000-000000000003');
  ok jsonb := '{"successful":true,"payee":true,"utr_amount":true,"after_tap":true}';
begin
  begin perform public.student_submit_upi_payment(s, 'upi', 'TEST1234567899', null, true, 'success', note, now() - interval '30 seconds', now(), null, null, ok);
    raise exception 'x'; exception when others then if sqlerrm <> 'RECEIPT_REQUIRED' then raise; end if; end;
  begin perform public.student_submit_upi_payment(s, 'upi', 'test1234567890', null, true, 'success', note, now() - interval '30 seconds', now(), 'r.jpg', 'cccccccccccccccc3333', ok);
    raise exception 'x'; exception when others then if sqlerrm <> 'DUPLICATE_UTR' then raise; end if; end;
  begin perform public.student_submit_upi_payment(s, 'upi', 'TEST1234567899', null, true, 'success', note, now() - interval '30 seconds', now(), 'r.jpg', 'AAAAAAAAAAAAAAAA1111', ok);
    raise exception 'x'; exception when others then if sqlerrm <> 'RECEIPT_REUSED' then raise; end if; end;
  begin perform public.student_submit_upi_payment(s, 'cash', 'TEST1234567899', null, true, 'success', note, now() - interval '30 seconds', now(), 'r.jpg', 'cccccccccccccccc3333', ok);
    raise exception 'x'; exception when others then if sqlerrm <> 'BAD_METHOD' then raise; end if; end;
  begin perform public.student_submit_payment(s, 'upi', 'TEST1234567890', null);
    raise exception 'x'; exception when others then if sqlerrm <> 'DUPLICATE_UTR' then raise; end if; end;
  assert (select status from public.tenants where id = t) = 'awaiting_payment', 'refused payments change nothing';
  -- T3 pays properly (UTR TEST…92) so the owner can reject it below
  perform public.student_submit_upi_payment(s, 'upi', 'TEST1234567892', null, true, 'success', note, now() - interval '30 seconds', now() - interval '3 seconds',
          'receipts/p3.jpg', 'cccccccccccccccc3333', ok);
end $$;

-- ---------- student "Your booking" page ----------
do $$
declare x jsonb := public.student_booking_status('a9a9a9a9-0000-0000-0000-000000000001');
begin
  assert x->>'status' = 'pending_approval' and (x->>'bed_kept')::boolean, 'waiting: bed kept for him';
  assert x->>'utr_last4' = '7890' and x->>'method' = 'upi' and x->>'room_no' = '301' and x->>'owner_phone' = '+919848000901',
    'payment, room and owner number shown';
end $$;

-- ---------- owner: Confirm booking / Reject with reason ----------
set role authenticated;
set request.jwt.claim.sub = '99999999-0000-9999-9999-999999999902';
do $$ begin
  begin perform public.confirm_booking('e9e9e9e9-0000-0000-0000-000000000001'); raise exception 'x';
  exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end;
  begin perform public.reject_booking('e9e9e9e9-0000-0000-0000-000000000002', 'other'); raise exception 'x';
  exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end;
end $$;
set request.jwt.claim.sub = '99999999-0000-9999-9999-999999999901';
do $$
declare t1 uuid := 'e9e9e9e9-0000-0000-0000-000000000001';
        t2 uuid := 'e9e9e9e9-0000-0000-0000-000000000002';
        t3 uuid := 'e9e9e9e9-0000-0000-0000-000000000003';
begin
  assert (select checks_passed from public.payments where tenant_id = t1) = 12, 'owner reads the check results';

  perform public.confirm_booking(t1);
  assert (select status from public.tenants where id = t1) = 'active', 'Confirm booking → tenant added';
  assert (select status from public.beds where id = (select bed_id from public.tenants where id = t1)) = 'occupied', 'bed filled';
  assert (select status from public.payments where tenant_id = t1) = 'received', 'payment counted';
  begin perform public.confirm_booking(t1); raise exception 'x';
  exception when others then if sqlerrm <> 'NOT_PENDING' then raise; end if; end;

  begin perform public.reject_booking(t2, 'because I said so'); raise exception 'x';
  exception when others then if sqlerrm <> 'BAD_REASON' then raise; end if; end;
  perform public.reject_booking(t2, 'wrong_details', 'Name does not match the Aadhaar');
  assert (select status = 'rejected' and reject_reason = 'wrong_details' and reject_note like 'Name does%' and rejected_at is not null
            from public.tenants where id = t2), 'rejected with a reason';
  assert (select status from public.beds where id = (select bed_id from public.tenants where id = t2)) = 'vacant', 'bed free again';
  assert (select status from public.payments where tenant_id = t2) = 'rejected', 'payment closed';
  begin perform public.reject_booking(t2, 'other'); raise exception 'x';
  exception when others then if sqlerrm <> 'NOT_PENDING' then raise; end if; end;

  perform public.reject_booking(t3, 'payment_not_received');
end $$;
reset role;
do $$
declare
  t2 uuid := 'e9e9e9e9-0000-0000-0000-000000000002';
  t3 uuid := 'e9e9e9e9-0000-0000-0000-000000000003';
begin
  assert (select count(*) from public.student_messages where tenant_id = t2 and kind = 'payment_not_received') = 0,
    'wrong details: no misleading "payment not received" message';
  assert (select count(*) from public.student_messages where tenant_id = t3 and kind = 'payment_not_received') = 1,
    '"payment not received" tells the student';
  assert public.student_booking_status('a9a9a9a9-0000-0000-0000-000000000002')->>'reject_reason' = 'wrong_details'
     and public.student_booking_status('a9a9a9a9-0000-0000-0000-000000000002')->>'status' = 'rejected', 'student sees the reason';
  assert public.student_booking_status('a9a9a9a9-0000-0000-0000-000000000001')->>'status' = 'active', 'confirmed → active';
end $$;

-- ---------- a "Not received" UTR stays blocked; later payments show "had Not received before" ----------
do $$
declare
  s uuid := 'a9a9a9a9-0000-0000-0000-000000000004';
  t uuid := 'e9e9e9e9-0000-0000-0000-000000000004';
  note text := private.payment_note('e9e9e9e9-0000-0000-0000-000000000004');
  ok jsonb := '{"successful":true,"payee":true,"utr_amount":true,"after_tap":true}';
  r jsonb;
begin
  begin perform public.student_submit_upi_payment(s, 'upi', 'TEST1234567892', null, true, 'success', note, now() - interval '30 seconds', now(), 'r.jpg', 'dddddddddddddddd4444', ok);
    raise exception 'x'; exception when others then if sqlerrm <> 'DUPLICATE_UTR' then raise; end if; end;
  r := public.student_submit_upi_payment(s, 'upi', 'TEST1234567894', null, true, 'success', note, now() - interval '30 seconds', now() - interval '4 seconds',
         'receipts/p4.jpg', 'dddddddddddddddd4444', ok);
  assert (r->>'checks_passed')::int = 12, 'a fresh tenant has no earlier "Not received"';
end $$;
-- Anita (confirmed) pays part of next month's rent: tenants can pay too, and the amount check uses what is due
insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
values (:'h1', 'e9e9e9e9-0000-0000-0000-000000000001', 'rent', 'Rent next', current_date + 20, current_date + 49, 6500, current_date + 20);
do $$
declare
  s uuid := 'a9a9a9a9-0000-0000-0000-000000000001';
  note text := private.payment_note('e9e9e9e9-0000-0000-0000-000000000001');
  ok jsonb := '{"successful":true,"payee":true,"utr_amount":true,"after_tap":true}';
  r jsonb;
begin
  r := public.student_submit_upi_payment(s, 'upi', 'TEST1234567893', 2000, true, 'success', note, now() - interval '30 seconds', now() - interval '4 seconds',
         'receipts/p5.jpg', 'eeeeeeeeeeeeeeee5555', ok);
  assert (r->>'amount')::int = 2000 and (r->>'checks_passed')::int = 12 and r->>'status' = 'active', 'part payment by an active tenant';
  r := public.student_submit_upi_payment(s, 'upi', 'TEST1234567895', 99999, true, 'success', note, now() - interval '30 seconds', now() - interval '4 seconds',
         'receipts/p6.jpg', 'ffffffffffffffff6666', ok);
  assert (select checks->>'amount_ok' from public.payments where id = (r->>'payment_id')::uuid) = 'false', 'more than due fails the amount check';
end $$;

-- ---------- 2-hour reminder to the owner ----------
do $$
declare t4 uuid := 'e9e9e9e9-0000-0000-0000-000000000004';
begin
  assert private.remind_pending_joiners() = 0, 'too early: no reminder';
  update public.payments set created_at = now() - interval '3 hours' where tenant_id = t4;
  assert private.remind_pending_joiners() = 1, 'reminder after 2 hours';
  assert (select count(*) from public.notifications where kind = 'reminder' and ref_id = t4) = 1, 'owner gets the reminder';
  assert private.remind_pending_joiners() = 0, 'only one reminder per joiner';
  assert (select status from public.beds where held_for = t4) = 'held', 'bed stays kept';
end $$;

-- ---------- receipts: 7 days on the server, fingerprint stays ----------
do $$
declare p uuid := (select id from public.payments where receipt_key = 'receipts/p1.jpg');
begin
  assert not exists (select 1 from public.receipts_to_purge() where payment_id = p), 'fresh receipt stays';
  update public.payments set created_at = now() - interval '8 days' where id = p;
  assert exists (select 1 from public.receipts_to_purge() where payment_id = p), 'old receipt is listed for deletion';
  perform public.mark_receipts_purged(array[p]);
  assert (select receipt_key is null and receipt_deleted_at is not null and receipt_hash = 'aaaaaaaaaaaaaaaa1111'
            from public.payments where id = p), 'file reference removed, fingerprint kept';
  assert not exists (select 1 from public.receipts_to_purge() where payment_id = p), 'not listed twice';
end $$;

-- ---------- who may call what ----------
set role authenticated;
set request.jwt.claim.sub = '99999999-0000-9999-9999-999999999901';
do $$ begin
  begin perform public.student_submit_upi_payment('a9a9a9a9-0000-0000-0000-000000000004', 'upi', 'X', null, true, 'success', 'x', now(), now(), 'k', 'k', '{}');
    raise exception 'x'; exception when insufficient_privilege then null; end;
  begin perform public.student_booking_status('a9a9a9a9-0000-0000-0000-000000000004'); raise exception 'x';
  exception when insufficient_privilege then null; end;
  begin perform public.receipts_to_purge(); raise exception 'x'; exception when insufficient_privilege then null; end;
end $$;
set role anon;
do $$ begin
  begin perform public.confirm_booking('e9e9e9e9-0000-0000-0000-000000000004'); raise exception 'x';
  exception when insufficient_privilege then null; end;
  begin perform public.reject_booking('e9e9e9e9-0000-0000-0000-000000000004', 'other'); raise exception 'x';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select 'OCT24_25_TESTS_PASSED' as result;
