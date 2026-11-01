-- Hostel settings round 3: sharing change moves students' fee, rent date change with one-time
-- adjustment, notice period, add room, student messages.
\set ON_ERROR_STOP 1
\set QUIET 1
-- this test runs on a fixed day (18 Oct 2026); the real private.today() is put back at the end
create or replace function private.today() returns date language sql stable set search_path = '' as $$ select date '2026-10-18' $$;
insert into auth.users (id, phone, raw_user_meta_data) values
  ('99999999-9999-9999-9999-999999999999', '+919848000099', '{"full_name":"Round3 Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone, upi_id, rent_day_mode, rent_fixed_day)
values ('e6e6e6e6-0000-0000-0000-000000000001', '99999999-9999-9999-9999-999999999999',
        'Round3 PG', 'mens', 'Road 9, Area', 'Hyderabad', '500009', '+919848000099', 'r3@okicici', 'fixed_day', 5);
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
-- Add room: G rule, price added to Rent per bed
do $$
declare h uuid := 'e6e6e6e6-0000-0000-0000-000000000001'; rid uuid;
begin
  rid := public.add_room_simple(h, 2, '204', 3, 6500);
  assert (select count(*) from public.beds where room_id = rid) = 3, 'three beds';
  assert (select sharing_prices->0->>'rent' from public.hostels where id = h) = '6500', 'price added to Rent per bed';
  perform public.add_room_simple(h, 0, 'g1', 2, 7000);
  assert exists (select 1 from public.rooms where hostel_id = h and room_no = 'G1' and floor = 0), 'G1 on ground';
  begin perform public.add_room_simple(h, 0, '101', 2, 7000); raise exception 'x';
  exception when others then if sqlerrm <> 'BAD_GROUND_ROOM' then raise; end if; end;
  begin perform public.add_room_simple(h, 2, '204', 2, 7000); raise exception 'x';
  exception when others then if sqlerrm <> 'ROOM_EXISTS' then raise; end if; end;
  -- an existing price is not changed by Add room
  perform public.add_room_simple(h, 2, '205', 3, 9999);
  assert (select jsonb_array_length(sharing_prices) from public.hostels where id = h) = 2, 'only new sharings added';
  assert (select (e->>'rent')::int from public.hostels, jsonb_array_elements(sharing_prices) e
          where id = h and (e->>'sharing')::int = 3) = 6500, '3 sharing price kept';
end $$;
reset role;
-- two students in room 204, paying 6500, fee on the 5th
do $$
declare h uuid := 'e6e6e6e6-0000-0000-0000-000000000001'; b1 uuid; b2 uuid;
begin
  select b.id into b1 from public.beds b join public.rooms r on r.id = b.room_id where r.hostel_id = h and r.room_no = '204' and b.label = 'A';
  select b.id into b2 from public.beds b join public.rooms r on r.id = b.room_id where r.hostel_id = h and r.room_no = '204' and b.label = 'B';
  update public.beds set status = 'occupied' where id in (b1, b2);
  insert into public.tenants (id, hostel_id, full_name, phone, status, bed_id, rent_month, joining_date, stay_type)
  values ('d6d6d6d6-0000-0000-0000-000000000001', h, 'Ravi', '+919000000901', 'active', b1, 6500, date '2026-09-05', 'monthly'),
         ('d6d6d6d6-0000-0000-0000-000000000002', h, 'Kiran', '+919000000902', 'notice', b2, 6500, date '2026-09-05', 'monthly');
  update public.tenants set leaving_date = date '2027-03-01' where id = 'd6d6d6d6-0000-0000-0000-000000000002';
  -- paid till 4 Nov
  insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, paid_amount, due_date, status)
  values (h, 'd6d6d6d6-0000-0000-0000-000000000001', 'rent', 'Rent', date '2026-10-05', date '2026-11-04', 6500, 6500, date '2026-10-05', 'paid'),
         (h, 'd6d6d6d6-0000-0000-0000-000000000002', 'rent', 'Rent', date '2026-10-05', date '2026-11-04', 6500, 6500, date '2026-10-05', 'paid');
end $$;
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
-- sharing change 3 → 4 with the 4-sharing price: both students move to 5500 and get a message
do $$
declare h uuid := 'e6e6e6e6-0000-0000-0000-000000000001'; rid uuid;
begin
  perform public.save_hostel_prices(h, '[{"sharing":3,"rent":6500},{"sharing":4,"rent":5500}]', false, 0, false, 0);
  assert (select rent_month from public.tenants where id = 'd6d6d6d6-0000-0000-0000-000000000001') = 6500, 'price change alone: students keep fee';
  select id into rid from public.rooms where hostel_id = h and room_no = '204';
  perform public.update_room(rid, '204', 4, 5500);
end $$;
reset role;
do $$
declare m jsonb;
begin
  assert (select rent_month from public.tenants where id = 'd6d6d6d6-0000-0000-0000-000000000001') = 5500, 'student fee follows the sharing';
  assert (select rent_month from public.tenants where id = 'd6d6d6d6-0000-0000-0000-000000000002') = 5500, 'notice student too';
  select params into m from public.student_messages where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001' and kind = 'sharing_change';
  assert m->>'from' = '3' and m->>'to' = '4' and m->>'new_rent' = '5500' and m->>'old_rent' = '6500', 'sharing message';
  assert m->>'from_date' = '2026-11-05', 'from the next fee date';
end $$;
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
-- fee date 5th → 10th: 5 days added once (5500 / 30 × 5 = 917), due 10 Nov, then normal
select public.change_rent_day('e6e6e6e6-0000-0000-0000-000000000001', 'fixed_day', 10) = 2 as moved \gset
reset role;
do $$
declare b public.bills; m jsonb;
begin
  select * into b from public.bills where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001' and kind = 'rent' and period_start = date '2026-11-05';
  assert b.amount = 5500 + 917, 'extra 5 days once: ' || b.amount;
  assert b.due_date = date '2026-11-10', 'due on the new date';
  assert b.period_end = date '2026-12-09', 'covers till the next new date';
  select params into m from public.student_messages where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001' and kind = 'rent_date_change';
  assert m->>'days' = '5' and m->>'adjust' = '917' and m->>'amount' = '6417', 'rent date message';
  perform public.generate_rent_bills(date '2026-12-08');
  assert (select amount from public.bills where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001' and period_start = date '2026-12-10') = 5500,
    'then the normal fee on the new date';
end $$;
-- back to the 5th before the next fee is due: the extra-days fee is undone (no bill after 4 Nov)
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
select public.change_rent_day('e6e6e6e6-0000-0000-0000-000000000001', 'fixed_day', 5) >= 0 as moved2 \gset
reset role;
do $$ begin
  assert not exists (select 1 from public.bills where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001'
    and kind = 'rent' and period_start > date '2026-10-05'), 'future extra-days fee undone';
end $$;
-- fee date 5th → 1st (earlier): days already paid (1–4 Nov) are taken off once
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
select public.change_rent_day('e6e6e6e6-0000-0000-0000-000000000001', 'fixed_day', 1) >= 1 as moved3 \gset
reset role;
do $$
declare b public.bills; m jsonb;
begin
  select * into b from public.bills where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001' and kind = 'rent'
    order by period_start desc limit 1;
  assert b.period_start = date '2026-11-01', 'new cycle starts on the 1st: ' || b.period_start;
  assert b.amount = 5500 - 733, 'four days taken off once: ' || b.amount;   -- 5500 / 30 × 4
  assert b.due_date = date '2026-11-01', 'due on the new date';
  select params into m from public.student_messages where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001'
    and kind = 'rent_date_change' order by created_at desc, id limit 1;
  assert (m->>'days')::int = -4 and (m->>'adjust')::int = -733, 'message says 4 days less';
end $$;
-- notice period: any days 1–90, active students told, students on notice not
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-9999-9999-999999999999';
select public.set_notice_days('e6e6e6e6-0000-0000-0000-000000000001', 21) = 1 as told \gset
do $$ begin
  perform public.set_notice_days('e6e6e6e6-0000-0000-0000-000000000001', 0);
  raise exception 'x';
exception when others then if sqlerrm <> 'BAD_DAYS' then raise; end if; end $$;
reset role;
do $$ begin
  assert (select notice_days from public.hostels where id = 'e6e6e6e6-0000-0000-0000-000000000001') = 21, 'notice days saved';
  assert exists (select 1 from public.student_messages where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000001' and kind = 'notice_change' and params->>'days' = '21'), 'active student told';
  assert not exists (select 1 from public.student_messages where tenant_id = 'd6d6d6d6-0000-0000-0000-000000000002' and kind = 'notice_change'), 'notice student not told';
  assert (select leaving_date from public.tenants where id = 'd6d6d6d6-0000-0000-0000-000000000002') = date '2027-03-01', 'leaving date kept';
end $$;
-- another owner can't do any of this
insert into auth.users (id, phone) values ('a6a6a6a6-9999-9999-9999-999999999999', '+919848000098');
set role authenticated;
set request.jwt.claim.sub = 'a6a6a6a6-9999-9999-9999-999999999999';
do $$ begin
  perform public.set_notice_days('e6e6e6e6-0000-0000-0000-000000000001', 30); raise exception 'x';
exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end $$;
do $$ begin
  perform public.change_rent_day('e6e6e6e6-0000-0000-0000-000000000001', 'fixed_day', 1); raise exception 'x';
exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end $$;
do $$ begin
  perform public.add_room_simple('e6e6e6e6-0000-0000-0000-000000000001', 1, '101', 2, 5000); raise exception 'x';
exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end $$;
reset role;
create or replace function private.today() returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'Asia/Kolkata')::date;
$$;
\echo SETTINGS_CHANGES_TESTS_PASSED
