-- Phase 1: rooms entered by tenants (students type floor / room / sharing / price / deposit;
-- the owner checks, corrects and confirms them).
\set ON_ERROR_STOP 1
\set QUIET 1
insert into private.settings values ('id_encryption_key', 'test-key-0123456789-abcdefghij') on conflict do nothing;
insert into auth.users (id, phone, raw_user_meta_data) values
  ('55555555-5555-5555-5555-555555555555', '+919848000055', '{"full_name":"Room Owner"}'),
  ('66666666-6666-6666-6666-666666666666', '+919848000066', '{"full_name":"Other Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone)
values ('eeeeeeee-0000-0000-0000-000000000001', '55555555-5555-5555-5555-555555555555',
        'Typed Rooms PG', 'mens', 'Road 5, Area', 'Hyderabad', '500005', '+919848000055');
-- the owner set one room himself
set role authenticated;
set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
select public.add_room('eeeeeeee-0000-0000-0000-000000000001', '101', 1, 2, 8000, 8000, '{}', false, 0) is not null as r101 \gset
reset role;
select join_code as jc from public.hostels where id = 'eeeeeeee-0000-0000-0000-000000000001' \gset

set role service_role;
select (public.student_start_session(:'jc', '+919700000001', 'h-anil')   ->> 'session_id') as s1 \gset
select (public.student_start_session(:'jc', '+919700000002', 'h-kiran')  ->> 'session_id') as s2 \gset
select (public.student_start_session(:'jc', '+919700000003', 'h-suresh') ->> 'session_id') as s3 \gset
select (public.student_start_session(:'jc', '+919700000004', 'h-manoj')  ->> 'session_id') as s4 \gset
select (public.student_start_session(:'jc', '+919700000005', 'h-new')    ->> 'session_id') as s5 \gset
select set_config('t.s1', :'s1', false), set_config('t.s2', :'s2', false), set_config('t.s3', :'s3', false),
       set_config('t.s4', :'s4', false), set_config('t.s5', :'s5', false) \gset

do $$
declare
  s1 uuid := current_setting('t.s1'); s2 uuid := current_setting('t.s2'); s3 uuid := current_setting('t.s3');
  s4 uuid := current_setting('t.s4'); s5 uuid := current_setting('t.s5');
  r jsonb;
  rid uuid;
  submit_existing text := '';
begin
  assert (public.student_hostel(s1)->>'tenant_room_entry')::boolean, 'room entry is on by default';

  -- lookup: an owner-set room fills the form, an unknown one does not
  r := public.student_room_lookup(s1, '101');
  assert (r->>'found')::boolean and (r->>'sharing')::int = 2 and (r->>'rent_month')::int = 8000, 'owner room found';
  assert not (public.student_room_lookup(s1, '105')->>'found')::boolean, 'unknown room not found';

  -- three existing tenants type room 105; one says 4 sharing and no deposit
  r := public.student_claim_typed_room(s1, '105', 1, 3, 6500, 5000, true);
  assert r->>'bed_label' = 'A' and not (r->>'confirmed_room')::boolean, 'room 105 made, bed A held';
  perform public.student_claim_typed_room(s2, '105', 1, 3, 6500, 5000, true);
  r := public.student_claim_typed_room(s3, '105', 1, 4, 6500, 0, true);
  assert r->>'bed_label' = 'C', 'third tenant gets bed C';
  select id into rid from public.rooms where room_no = '105';
  assert (select sharing from public.rooms where id = rid) = 4, 'unconfirmed room grows to the biggest sharing typed';
  assert (select count(*) from public.beds where room_id = rid) = 4, '4 beds now';
  assert (select rent_month from public.tenants where phone = '+919700000003') = 6500
     and (select deposit from public.tenants where phone = '+919700000003') = 0, 'tenant keeps the fee typed';

  -- claiming again keeps the same bed (no second bed)
  r := public.student_claim_typed_room(s1, '105', 1, 3, 6500, 5000, true);
  assert r->>'bed_label' = 'A', 'same bed kept';
  assert (select count(*) from public.tenant_room_entries where tenant_id = (select id from public.tenants where phone = '+919700000001')) = 1, 'one entry per tenant';

  -- two tenants in room 106 agree
  perform public.student_claim_typed_room(s4, '106', 1, 2, 7500, 5000, true);

  -- they send their details (existing tenants → owner approval)
  foreach submit_existing in array array[s1::text, s2::text, s3::text, s4::text] loop
    perform public.student_submit_details(submit_existing::uuid, 'Tenant ' || right(submit_existing, 4), '+919811111111', null,
      'aadhaar', '123456789012', 'id/x.jpg', null, 'House 1, Some street', null, true, current_date - 30, true);
  end loop;

  -- a new joiner typing an owner-set room gets its price, not what they typed
  r := public.student_claim_typed_room(s5, '101', 1, 3, 1000, 0, false);
  assert (r->>'confirmed_room')::boolean, 'owner room used';
  assert (select rent_month from public.tenants where phone = '+919700000005') = 8000, 'owner price wins';
  assert (select count(*) from public.beds b join public.rooms x on x.id = b.room_id where x.room_no = '101') = 2, 'owner room not changed';

  -- unconfirmed rooms are hidden from room selection
  assert not exists (select 1 from jsonb_array_elements(public.student_rooms(s5)) x where x->>'room_no' in ('105', '106')),
    'unconfirmed rooms hidden';
end $$;

-- ---------- owner side ----------
reset role;
set role authenticated;
set request.jwt.claim.sub = '66666666-6666-6666-6666-666666666666';
do $$ begin
  perform public.tenant_rooms('eeeeeeee-0000-0000-0000-000000000001');
  raise exception 'other owner must not see the table';
exception when others then
  if sqlerrm <> 'NOT_ALLOWED' then raise; end if;
end $$;

set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
do $$
declare
  h uuid := 'eeeeeeee-0000-0000-0000-000000000001';
  rows jsonb := public.tenant_rooms(h);
  r105 jsonb;
  r106 jsonb;
  n int;
  rid uuid;
begin
  assert jsonb_array_length(rows) = 2, 'two tenant rooms (owner room 101 not listed)';
  select x into r105 from jsonb_array_elements(rows) x where x->>'room_no' = '105';
  select x into r106 from jsonb_array_elements(rows) x where x->>'room_no' = '106';
  assert r105->>'status' = 'fix', '105 needs fixing (3 vs 4 sharing)';
  assert jsonb_array_length(r105->'entries') = 3, 'three entries for 105';
  assert r106->>'status' = 'ok', '106 is consistent';

  n := public.confirm_correct_tenant_rooms(h);
  assert n = 1, 'only 106 confirmed';
  assert (select confirmed from public.rooms where hostel_id = h and room_no = '106'), '106 confirmed';
  assert (select count(*) from public.beds b join public.rooms x on x.id = b.room_id
           where x.hostel_id = h and x.room_no = '106') = 2, '106 has 2 beds';

  -- owner fixes 105: 3 sharing, 6500, deposit 5000 → the 4th (empty) bed is removed
  rid := (r105->>'room_id')::uuid;
  perform public.confirm_tenant_room(rid, 1, 3, 6500, 5000);
  assert (select sharing from public.rooms where id = rid) = 3, '105 is 3 sharing';
  assert (select count(*) from public.beds where room_id = rid) = 3, '105 has 3 beds';
  assert (select string_agg(label, '' order by label) from public.beds where room_id = rid) = 'ABC', 'beds A B C';
  assert (select deposit from public.tenants where phone = '+919700000003') = 0, 'tenant fee untouched by the fix';

  -- can't make a room smaller than the tenants in it
  begin
    perform public.confirm_tenant_room(rid, 1, 2, 6500, 5000);
    raise exception 'should not shrink below tenants';
  exception when others then
    if sqlerrm <> 'TOO_MANY_TENANTS' then raise; end if;
  end;

  -- price by sharing
  n := public.set_sharing_price(h, 3, 6800, 6000);
  assert n = 1, 'one 3-sharing tenant room';
  assert (select rent_month from public.rooms where id = rid) = 6800, 'price updated';
  assert (select rent_month from public.rooms where hostel_id = h and room_no = '101') = 8000, 'owner rooms untouched';

  -- owner turns room entry off
  update public.hostels set tenant_room_entry = false, use_tenant_prices = false where id = h;
end $$;

reset role;
set role service_role;
do $$
declare s5 uuid := current_setting('t.s5');
begin
  begin
    perform public.student_claim_typed_room(s5, '201', 2, 2, 7000, 0, false);
    raise exception 'room entry is off';
  exception when others then
    if sqlerrm <> 'ROOM_ENTRY_OFF' then raise; end if;
  end;
  assert not (public.student_hostel(s5)->>'tenant_room_entry')::boolean, 'form hides the room section';
  assert not exists (select 1 from jsonb_array_elements(public.student_rooms(s5)) x where x->>'room_no' = '105'),
    'tenant rooms hidden when "use these prices" is off';
end $$;
reset role;
-- students can't call owner functions and owners can't call student functions
set role authenticated;
do $$ begin
  perform public.student_claim_typed_room(gen_random_uuid(), '1', 0, 1, 100, 0, false);
  raise exception 'owner must not call student function';
exception when insufficient_privilege then null;
end $$;
reset role;
-- sharing can go up to 12 (the "+" button), floors 1–9 from the dropdown
update public.hostels set tenant_room_entry = true where id = 'eeeeeeee-0000-0000-0000-000000000001';
set role service_role;
select (public.student_start_session(:'jc', '+919700000009', 'h-big') ->> 'session_id') as s9 \gset
select set_config('t.s9', :'s9', false) \gset
do $$
declare s9 uuid := current_setting('t.s9'); r jsonb;
begin
  r := public.student_claim_typed_room(s9, '901', 9, 8, 4500, 3000, false);
  assert (select sharing from public.rooms where room_no = '901') = 8, '8-sharing room on floor 9';
  assert (select count(*) from public.beds b join public.rooms x on x.id = b.room_id where x.room_no = '901') = 8, '8 beds';
  begin
    perform public.student_claim_typed_room(s9, '902', 9, 13, 4500, 0, false);
    raise exception '13 sharing should fail';
  exception when others then
    if sqlerrm <> 'BAD_SHARING' then raise; end if;
  end;
end $$;
reset role;
-- ground floor rooms are G + a number
set role service_role;
do $$
declare s9 uuid := current_setting('t.s9'); r jsonb;
begin
  r := public.student_claim_typed_room(s9, 'g3', 0, 2, 7000, 0, false);
  assert r->>'room_no' = 'G3', 'g3 saved as G3 on the ground floor';
  begin
    perform public.student_claim_typed_room(s9, '104', 0, 2, 7000, 0, false);
    raise exception 'ground room without G should fail';
  exception when others then
    if sqlerrm <> 'BAD_GROUND_ROOM' then raise; end if;
  end;
  begin
    perform public.student_claim_typed_room(s9, 'G7', 2, 2, 7000, 0, false);
    raise exception 'G room on floor 2 should fail';
  exception when others then
    if sqlerrm <> 'BAD_GROUND_ROOM' then raise; end if;
  end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub = '55555555-5555-5555-5555-555555555555';
do $$ begin
  perform public.confirm_tenant_room((select id from public.rooms where room_no = 'G3'), 1, 2, 7000, 0);
  raise exception 'owner must not move a G room off the ground floor';
exception when others then
  if sqlerrm <> 'BAD_GROUND_ROOM' then raise; end if;
end $$;
reset role;
\echo TENANT_ROOMS_TESTS_PASSED
