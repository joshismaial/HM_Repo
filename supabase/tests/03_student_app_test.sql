-- QR booking for the student app: 60-minute owner hold, 15 minutes from when the app opens.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, phone, raw_user_meta_data) values
  ('44444444-4444-4444-4444-444444444444', '+919848000044', '{"full_name":"QR Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone)
values ('cccccccc-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444',
        'QR Test PG', 'womens', 'Road 2, Area', 'Hyderabad', '500002', '+919848000044');
set role authenticated;
set request.jwt.claim.sub = '44444444-4444-4444-4444-444444444444';
select public.add_room('cccccccc-0000-0000-0000-000000000001', '203', 2, 3, 6500, 6500, '{ac}', false, 0) as room \gset
select id as bed from public.beds where room_id = :'room' order by label limit 1 \gset
select public.owner_hold_bed(:'bed') ->> 'booking_code' as k \gset
reset role;
select join_code as jc from public.hostels where id = 'cccccccc-0000-0000-0000-000000000001' \gset
select set_config('test.bed', :'bed', false) is not null as s1 \gset
select set_config('test.k', :'k', false) is not null as s2 \gset
select set_config('test.jc', :'jc', false) is not null as s3 \gset
do $$
declare b uuid := current_setting('test.bed')::uuid; k text := current_setting('test.k'); jc text := current_setting('test.jc'); r jsonb;
begin
  assert (select held_until > now() + interval '55 minutes' from public.beds where id = b), 'owner hold is 60 minutes';
  r := public.booking_peek(jc, b, k);
  assert (r->>'timer_started')::boolean = false, 'peek alone does not start the timer';
  assert r->>'hostel_name' = 'QR Test PG', 'hostel name in peek';
  r := public.booking_peek(jc, b, k, true);
  assert (r->>'timer_started')::boolean, 'app open starts the timer';
  assert (select held_until < now() + interval '16 minutes' from public.beds where id = b), '15 minutes from opening';
  perform public.booking_peek(jc, b, k, true);
  assert (select booking_opened_at is not null from public.beds where id = b), 'opened once';
end $$;
-- Wi-Fi: whole-hostel network + the tenant's floor only, and only while staying
update public.hostels set wifi = '[{"floor":null,"name":"QR_PG","password":"all123"},{"floor":2,"name":"QR_F2","password":"f2pass"},{"floor":3,"name":"QR_F3","password":"f3pass"}]'
 where id = 'cccccccc-0000-0000-0000-000000000001';
insert into public.tenants (id, hostel_id, full_name, phone, status, bed_id, rent_month)
values ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'Wifi Wendy', '+919000000201', 'active',
        (select id from public.beds where room_id = (select id from public.rooms where room_no = '203' and hostel_id = 'cccccccc-0000-0000-0000-000000000001') order by label desc limit 1), 6500);
do $$
declare w jsonb := private.tenant_wifi('dddddddd-0000-0000-0000-000000000001');
begin
  assert jsonb_array_length(w) = 2, 'whole hostel + floor 2';
  assert w->0->>'name' = 'QR_PG' and w->1->>'name' = 'QR_F2', 'right networks';
  update public.tenants set status = 'vacated' where id = 'dddddddd-0000-0000-0000-000000000001';
  assert jsonb_array_length(private.tenant_wifi('dddddddd-0000-0000-0000-000000000001')) = 0, 'hidden after leaving';
end $$;
\echo STUDENT_APP_TESTS_PASSED
