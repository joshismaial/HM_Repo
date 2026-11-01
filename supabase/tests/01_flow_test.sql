-- End-to-end test of the Phase 1 flow. Run after the migrations on a test database.
\set ON_ERROR_STOP 1
\set QUIET 1

insert into private.settings values ('id_encryption_key', 'test-key-0123456789-abcdefghij');

-- Two owners
insert into auth.users (id, phone, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '+919848012345', '{"full_name":"Ravi Kumar"}'),
  ('22222222-2222-2222-2222-222222222222', '+919000000002', '{"full_name":"Other Owner"}');
do $$ begin
  assert (select full_name from public.profiles where id = '11111111-1111-1111-1111-111111111111') = 'Ravi Kumar', 'profile created';
end $$;

-- ---------- Owner 1 sets up a hostel ----------
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
insert into public.hostels (name, type, address, city, pincode, contact_phone, upi_id, upi_payee_name, accept_bank, bank_details)
values ('The Royal Palms Hostel', 'mens', 'Road No. 12, Banjara Hills', 'Hyderabad', '500034', '+919848012345',
        'royalpalms@upi', 'Royal Palms', true, 'A/C 1234 IFSC SBIN0001234');
select public.add_room((select id from public.hostels limit 1), '204', 2, 2, 6000, 5000, '{AC}', true, 0) as room204 \gset
select public.add_room((select id from public.hostels limit 1), '104', 1, 2, 6000, 5000, '{}', false, 1) as room104 \gset
select join_code from public.hostels limit 1 \gset
do $$ begin
  assert (select count(*) from public.beds) = 4, 'beds created';
  assert (select count(*) from public.beds where status = 'offline_occupied') = 1, 'offline bed marked';
end $$;

-- Owner 2 cannot see owner 1's data
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin
  assert (select count(*) from public.hostels) = 0, 'other owner sees no hostels';
  assert (select count(*) from public.beds) = 0, 'other owner sees no beds';
  begin
    perform public.hostel_summary((select id from public.hostels limit 1));
  exception when others then null;
  end;
end $$;
reset role;
do $$ declare h uuid := (select id from public.hostels limit 1); begin
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
  begin
    perform public.hostel_summary(h);
    raise exception 'other owner should not read summary';
  exception when others then
    if sqlerrm <> 'NOT_ALLOWED' then raise; end if;
  end;
end $$;

-- ---------- Student A joins (new joiner) ----------
set role service_role;
select (public.student_start_session(:'join_code', '+919876543210', 'hashA') ->> 'session_id') as sa \gset
select (public.student_start_session(:'join_code', '+919123456780', 'hashB') ->> 'session_id') as sb \gset
select id as bed204a from public.beds where room_id = :'room204' and label = 'A' \gset
select id as bed104a from public.beds where room_id = :'room104' and label = 'A' \gset

select public.student_hold_bed(:'sa', :'bed204a') is not null as held \gset
-- Student B tries the same bed -> BED_TAKEN
select set_config('test.sb', :'sb', false), set_config('test.bed', :'bed204a', false) \gset
do $$ begin
  perform public.student_hold_bed(current_setting('test.sb')::uuid, current_setting('test.bed')::uuid);
  raise exception 'second hold should fail';
exception when others then
  if sqlerrm <> 'BED_TAKEN' then raise; end if;
end $$;

-- Student B can't hold an offline bed and then claim to be new
select public.student_hold_bed(:'sb', :'bed104a') ->> 'offline_bed' as offline \gset
do $$ begin
  assert current_setting('test.sb') is not null;
end $$;
select set_config('test.sb', :'sb', false) \gset
do $$ begin
  perform public.student_submit_details(current_setting('test.sb')::uuid, 'Vikram Kumar', null, null,
    'aadhaar', 'XXXXXXXX4321', 'id/b.jpg', 'ph/b.jpg', 'Some address 123', null, false, null, true);
  raise exception 'new joiner on offline bed should fail';
exception when others then
  if sqlerrm <> 'BED_TAKEN' then raise; end if;
end $$;

-- Student A submits details (consent required)
select public.student_submit_details(:'sa', 'Rahul Sharma', '+919876523332', '+919988776655',
  'aadhaar', '1234 5678 9012', 'hostels/x/id.jpg', 'hostels/x/photo.jpg',
  'Flat 401, Sapphire Apts, Banjara Hills', 'Global Tech Institute', false, null, true) ->> 'status' as st \gset
do $$ begin
  assert (select status from public.tenants where full_name = 'Rahul Sharma') = 'awaiting_payment', 'awaiting payment';
  assert (select id_last4 from public.tenants where full_name = 'Rahul Sharma') = '9012', 'last4 stored';
  assert (select id_number_enc is not null from public.tenants where full_name = 'Rahul Sharma'), 'encrypted';
end $$;

select public.student_quote(:'sa') as quote \gset
\echo quote: :quote

-- UTR required for UPI
select set_config('test.sa', :'sa', false) \gset
do $$ begin
  perform public.student_submit_payment(current_setting('test.sa')::uuid, 'upi', null, null);
  raise exception 'should need UTR';
exception when others then
  if sqlerrm <> 'UTR_REQUIRED' then raise; end if;
end $$;
select public.student_submit_payment(:'sa', 'upi', '4281 9930 1176', null) as pay \gset
do $$ begin
  assert (select status from public.tenants where full_name = 'Rahul Sharma') = 'pending_approval', 'pending approval';
  assert (select count(*) from public.bills where tenant_id = (select id from public.tenants where full_name='Rahul Sharma')) = 2, 'deposit + rent bills';
  assert (select count(*) from public.notifications where kind = 'payment') = 1, 'owner notified';
end $$;

-- ---------- Student B: existing tenant on the offline bed ----------
select public.student_submit_details(:'sb', 'Vikram Kumar', '+919988776601', null,
  'aadhaar', 'XXXXXXXX4321', 'id/b.jpg', 'ph/b.jpg', 'Some address 123', null, true, current_date - 100, true) ->> 'status' as stb \gset
do $$ begin
  assert (select status from public.tenants where full_name = 'Vikram Kumar') = 'pending_approval', 'existing pending';
  assert (select id_number_enc is null from public.tenants where full_name = 'Vikram Kumar'), 'masked aadhaar not stored';
end $$;

-- ---------- Owner confirms A's payment (part payment) and approves B ----------
reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select public.confirm_payment((select id from public.payments limit 1), 8000) as conf \gset
select public.approve_tenant((select id from public.tenants where full_name = 'Vikram Kumar'));
do $$ declare a uuid := (select id from public.tenants where full_name = 'Rahul Sharma');
               b uuid := (select id from public.tenants where full_name = 'Vikram Kumar');
begin
  assert (select status from public.tenants where id = a) = 'active', 'A active';
  assert (select status from public.beds where id = (select bed_id from public.tenants where id = a)) = 'occupied', 'A bed occupied';
  assert (select status from public.bills where tenant_id = a and kind = 'deposit') = 'paid', 'deposit paid first';
  assert (select status from public.bills where tenant_id = a and kind = 'rent') = 'partial', 'rent partly paid';
  assert (select status from public.tenants where id = b) = 'active', 'B active';
  assert (select count(*) from public.bills where tenant_id = b and kind = 'rent') = 1, 'B first bill';
end $$;

-- Owner can't read the encrypted column directly, but can reveal (logged)
do $$ begin
  begin
    perform id_number_enc from public.tenants limit 1;
    raise exception 'encrypted column should not be readable';
  exception when insufficient_privilege then null;
  end;
end $$;
select public.reveal_id_number((select id from public.tenants where full_name = 'Rahul Sharma')) as revealed \gset
\echo revealed: :revealed
do $$ begin assert (select count(*) from public.id_reveal_log) = 1, 'reveal logged'; end $$;

-- Record a cash payment for the rest
select public.record_payment((select id from public.tenants where full_name = 'Rahul Sharma'),
  (select sum(amount - paid_amount) from public.bills where tenant_id = (select id from public.tenants where full_name='Rahul Sharma'))::int,
  'cash', current_date, 'Paid at office') is not null as rec \gset
do $$ begin
  assert (select bool_and(status = 'paid') from public.bills
          where tenant_id = (select id from public.tenants where full_name = 'Rahul Sharma')), 'all bills paid';
end $$;

select public.hostel_summary((select id from public.hostels limit 1)) as summary \gset
\echo summary: :summary
select public.rent_overview((select id from public.hostels limit 1)) as rent \gset
\echo rent: :rent

-- ---------- Duplicate UTR is blocked ----------
reset role;
set role service_role;
select set_config('test.sa', :'sa', false) \gset
do $$ begin
  perform public.student_pay_bill(current_setting('test.sa')::uuid, 'upi', '4281 9930 1176', 6000, null);
  raise exception 'duplicate UTR should fail';
exception when others then
  if sqlerrm <> 'DUPLICATE_UTR' then raise; end if;
end $$;

-- ---------- Monthly bills + notice ----------
select public.generate_rent_bills(current_date + 40) as made \gset
\echo bills made: :made
do $$ begin
  assert (select count(*) from public.bills where kind = 'rent'
          and tenant_id = (select id from public.tenants where full_name = 'Rahul Sharma')) >= 2, 'next month billed';
end $$;
select public.student_give_notice(:'sa', current_date + 20) as notice \gset
\echo notice: :notice
select (public.student_me(:'sa') -> 'tenant' ->> 'status') as me_status \gset
\echo me status: :me_status

-- ---------- Owner rejects a payment; tenant vacates with deposit refund ----------
set role service_role;
select (public.student_start_session(:'join_code', '+919222222222', 'hashC') ->> 'session_id') as sc \gset
select id as bed204b from public.beds where room_id = :'room204' and label = 'B' \gset
select public.student_hold_bed(:'sc', :'bed204b') is not null as heldc \gset
select public.student_submit_details(:'sc', 'Kiran Rao', '+919988776602', null, 'passport', 'P1234567', 'id/c.jpg', 'ph/c.jpg',
  'Some address 456', null, false, null, true) is not null as dc \gset
select public.student_submit_payment(:'sc', 'bank', 'BANKREF77881', null) is not null as pc \gset
reset role;
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select public.reject_payment((select id from public.payments where utr = 'BANKREF77881'), 'Not in bank statement');
do $$ begin
  assert (select status from public.tenants where full_name = 'Kiran Rao') = 'awaiting_payment', 'back to awaiting payment';
end $$;
select public.mark_vacated((select id from public.tenants where full_name = 'Rahul Sharma'), 500) as vac \gset
\echo vacated: :vac
do $$ begin
  assert (select status from public.tenants where full_name = 'Rahul Sharma') = 'vacated', 'vacated';
  assert (select deposit_refund from public.tenants where full_name = 'Rahul Sharma') = 4500, 'refund = deposit - deduction';
  assert (select status from public.beds where id = (select bed_id from public.tenants where full_name = 'Rahul Sharma')) = 'vacant', 'bed free';
end $$;
reset role;

-- ---------- Expired holds are released ----------
reset role;
insert into public.tenants (hostel_id, phone, status, created_at) values
  ((select id from public.hostels limit 1), '+919111111111', 'draft', now() - interval '1 hour');
update public.beds set status = 'held', held_for = (select id from public.tenants where phone = '+919111111111'),
       held_until = now() - interval '1 minute'
 where room_id = :'room204' and label = 'B';
set role service_role;
select public.release_expired_holds() as released \gset
do $$ begin
  assert (select status from public.beds where label = 'B' and room_id in (select id from public.rooms where room_no='204')) = 'vacant', 'hold released';
  assert (select status from public.tenants where phone = '+919111111111') = 'expired', 'draft expired';
end $$;

-- ---------- Anonymous users get nothing ----------
reset role;
set role anon;
do $$ begin
  begin
    perform 1 from public.tenants limit 1;
    raise exception 'anon should not read tenants';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.student_me(gen_random_uuid());
    raise exception 'anon should not call student functions';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
\echo ALL_TESTS_PASSED
