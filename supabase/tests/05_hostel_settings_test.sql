-- Hostel settings: rent per sharing, deposit on/off, day-wise price, extra charges, UPI apps, Wi-Fi by floor.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, phone, raw_user_meta_data) values
  ('77777777-7777-7777-7777-777777777777', '+919848000077', '{"full_name":"Settings Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone, upi_id)
values ('ffffffff-0000-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777',
        'Settings PG', 'mens', 'Road 7, Area', 'Hyderabad', '500007', '+919848000077', 'settings@okicici');
set role authenticated;
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
select public.add_room('ffffffff-0000-0000-0000-000000000001', '201', 2, 2, 7000, 7000, '{}', false, 0) is not null as a \gset
select public.add_room('ffffffff-0000-0000-0000-000000000001', '301', 3, 3, 6000, 6000, '{}', false, 0) is not null as b \gset
do $$
declare h uuid := 'ffffffff-0000-0000-0000-000000000001';
begin
  assert (select jsonb_array_length(extra_charges) from public.hostels where id = h) = 2, 'electricity + laundry by default';
  perform public.save_hostel_prices(h, '[{"sharing":3,"rent":6500},{"sharing":2,"rent":7500}]', true, 5000, true, 500);
  assert (select sharing_prices->0->>'sharing' from public.hostels where id = h) = '2', 'prices sorted by sharing';
  assert (select rent_month from public.rooms where hostel_id = h and room_no = '201') = 7500, '2-sharing room price updated';
  assert (select rent_month from public.rooms where hostel_id = h and room_no = '301') = 6500, '3-sharing room price updated';
  assert (select deposit_month from public.rooms where hostel_id = h and room_no = '201') = 5000, 'deposit copied to rooms';
  assert (select rent_day from public.rooms where hostel_id = h and room_no = '201') = 500, 'per-day price copied';
  -- deposit off → rooms take no deposit
  perform public.save_hostel_prices(h, '[{"sharing":2,"rent":7500}]', false, 5000, false, 0);
  assert (select deposit_month from public.rooms where hostel_id = h and room_no = '301') = 0, 'deposit off';
  begin
    perform public.save_hostel_prices(h, '[{"sharing":2,"rent":7500},{"sharing":2,"rent":8000}]', true, 0, false, 0);
    raise exception 'same sharing twice should fail';
  exception when others then
    if sqlerrm <> 'INVALID_VALUE' then raise; end if;
  end;
  begin
    perform public.save_hostel_prices(h, '[]', true, 0, true, 0);
    raise exception 'day-wise on needs a price';
  exception when others then
    if sqlerrm <> 'BAD_AMOUNT' then raise; end if;
  end;
  -- UPI apps and Wi-Fi rows (floor + password, no name)
  update public.hostels set accept_gpay = true, accept_paytm = true,
         wifi = '[{"floor":2,"password":"f2pass"},{"floor":3,"password":"f3pass"}]' where id = h;
end $$;
reset role;
do $$
declare h uuid := 'ffffffff-0000-0000-0000-000000000001';
begin
  assert private.upi_apps(h) = '["gpay", "paytm"]'::jsonb, 'apps switched on';
  insert into public.tenants (id, hostel_id, full_name, phone, status, bed_id, rent_month)
  values ('dddddddd-0000-0000-0000-000000000077', h, 'Wifi Student', '+919000000377', 'active',
          (select b.id from public.beds b join public.rooms r on r.id = b.room_id where r.hostel_id = h and r.room_no = '201' limit 1), 7500);
  assert jsonb_array_length(private.tenant_wifi('dddddddd-0000-0000-0000-000000000077')) = 1, 'only floor 2 password';
  assert private.tenant_wifi('dddddddd-0000-0000-0000-000000000077')->0->>'password' = 'f2pass', 'right password';
end $$;
-- Change room details: number, sharing, rent
set role authenticated;
set request.jwt.claim.sub = '77777777-7777-7777-7777-777777777777';
do $$
declare h uuid := 'ffffffff-0000-0000-0000-000000000001'; rid uuid;
begin
  select id into rid from public.rooms where hostel_id = h and room_no = '201';
  perform public.update_room(rid, '205', 4, 6000);
  assert (select room_no from public.rooms where id = rid) = '205', 'room number changed';
  assert (select sharing from public.rooms where id = rid) = 4, 'sharing changed';
  assert (select count(*) from public.beds where room_id = rid) = 4, 'beds follow the sharing';
  assert (select rent_month from public.rooms where id = rid) = 6000, 'rent changed';
  assert (select rent_month from public.tenants where id = 'dddddddd-0000-0000-0000-000000000077') = 6000, 'sharing changed: tenant pays the new fee';
  begin
    perform public.update_room(rid, '301', 4, 6000);
    raise exception 'duplicate number should fail';
  exception when others then
    if sqlerrm <> 'ROOM_EXISTS' then raise; end if;
  end;
  begin
    perform public.update_room(rid, 'G5', 4, 6000);
    raise exception 'G number on floor 2 should fail';
  exception when others then
    if sqlerrm <> 'BAD_GROUND_ROOM' then raise; end if;
  end;
  perform public.update_room(rid, '205', 1, 6000);
  assert (select count(*) from public.beds where room_id = rid) = 1, 'shrinks to the one person staying';
  begin
    perform public.update_room(rid, '205', 1, 0);
    raise exception 'zero rent should fail';
  exception when others then
    if sqlerrm <> 'BAD_AMOUNT' then raise; end if;
  end;
end $$;
reset role;
-- another owner can't change these prices
insert into auth.users (id, phone) values ('88888888-8888-8888-8888-888888888888', '+919848000088');
set role authenticated;
set request.jwt.claim.sub = '88888888-8888-8888-8888-888888888888';
do $$ begin
  perform public.save_hostel_prices('ffffffff-0000-0000-0000-000000000001', '[]', false, 0, false, 0);
  raise exception 'other owner must not save';
exception when others then
  if sqlerrm <> 'NOT_ALLOWED' then raise; end if;
end $$;
reset role;
\echo HOSTEL_SETTINGS_TESTS_PASSED
