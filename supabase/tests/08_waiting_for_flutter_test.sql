-- 22 Oct 2026 "move to Flutter": notices, ads, complaints, Done – I have paid, cash plans, Not received
-- messages (stay until OK), vacate notice on the next fee date + cancel, Home extras, permissions.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, phone, raw_user_meta_data) values
  ('88888888-0000-8888-8888-888888888801', '+919848000801', '{"full_name":"Wait Owner"}'),
  ('88888888-0000-8888-8888-888888888802', '+919848000802', '{"full_name":"Other Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone, accept_cash)
values ('f8f8f8f8-0000-0000-0000-000000000001', '88888888-0000-8888-8888-888888888801',
        'Sai Residency Ladies PG', 'womens', 'Road 8, Dilsukhnagar', 'Hyderabad', '500060', '+919848000801', true);
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888801';
select public.add_room('f8f8f8f8-0000-0000-0000-000000000001', '201', 2, 2, 6500, 6500, '{}', false, 0) as room \gset
reset role;
insert into public.tenants (id, hostel_id, full_name, phone, status, bed_id, rent_month, joining_date)
values ('e8e8e8e8-0000-0000-0000-000000000001', 'f8f8f8f8-0000-0000-0000-000000000001', 'Priya Sharma', '+919000000801',
        'active', (select id from public.beds where room_id = :'room' order by label limit 1), 6500, current_date - 10);
update public.beds set status = 'occupied' where id = (select bed_id from public.tenants where id = 'e8e8e8e8-0000-0000-0000-000000000001');
insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
values ('f8f8f8f8-0000-0000-0000-000000000001', 'e8e8e8e8-0000-0000-0000-000000000001', 'rent', 'Rent',
        current_date - 10, current_date + 19, 6500, current_date - 10),
       ('f8f8f8f8-0000-0000-0000-000000000001', 'e8e8e8e8-0000-0000-0000-000000000001', 'rent', 'Rent',
        current_date + 20, current_date + 49, 6500, current_date + 20);
insert into public.student_sessions (id, hostel_id, phone, tenant_id, token_hash)
values ('a8a8a8a8-0000-0000-0000-000000000001', 'f8f8f8f8-0000-0000-0000-000000000001', '+919000000801',
        'e8e8e8e8-0000-0000-0000-000000000001', 'hash-wait-1');
insert into public.student_ads (shop, offer, city) values ('Sri Tiffins', '10% off for students', 'Hyderabad');
insert into public.student_ads (shop, offer, city) values ('Far Away Shop', 'Not here', 'Chennai');

-- ---------- owner: notices, Home extras ----------
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888801';
select public.post_owner_notice('f8f8f8f8-0000-0000-0000-000000000001', 'water', 'Water off', 'Tomorrow 10 AM – 1 PM') as n1 \gset
do $$
declare x jsonb := public.hostel_summary_extra('f8f8f8f8-0000-0000-0000-000000000001');
begin
  assert (x->>'open_complaints')::int = 0, 'no complaints yet';
  assert (x->>'rooms_with_free')::int = 1, 'room 201 has a free bed';
  assert (select count(*) from public.owner_notices) = 1, 'owner sees his notice';
end $$;
reset role;

-- ---------- student: Home data ----------
do $$
declare
  s uuid := 'a8a8a8a8-0000-0000-0000-000000000001';
  x jsonb := public.student_me_extra(s);
begin
  assert jsonb_array_length(x->'notices') = 1 and x->'notices'->0->>'title' = 'Water off', 'notice on student Home';
  assert x->'ad'->>'shop' = 'Sri Tiffins', 'only the ad for this city';
  assert (x->>'next_fee_date')::date = current_date + 20, 'next fee date';
  assert x->'cash_plan' = 'null'::jsonb or x->'cash_plan' is null, 'no cash plan yet';
end $$;

-- ---------- student: Report issue → owner Complaints ----------
select public.student_report_issue('a8a8a8a8-0000-0000-0000-000000000001', 'water', 'No water in bathroom') as issue \gset
do $$ begin
  assert (select count(*) from public.notifications where kind = 'issue') = 1, 'owner told about the issue';
end $$;
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888801';
do $$
declare c uuid := (select id from public.complaints limit 1);
begin
  assert (public.hostel_summary_extra('f8f8f8f8-0000-0000-0000-000000000001')->>'open_complaints')::int = 1, 'open complaint counted';
  perform public.update_complaint(c, 'in_progress', 'Plumber coming at 5 PM');
end $$;
reset role;
do $$
declare
  s uuid := 'a8a8a8a8-0000-0000-0000-000000000001';
  i jsonb := public.student_me_extra(s)->'issues'->0;
begin
  assert i->>'status' = 'in_progress' and i->>'owner_reply' = 'Plumber coming at 5 PM', 'student sees the owner reply';
  assert (i->>'unread')::boolean, 'number on the Report issue tab';
  perform public.student_read_issue(s, (i->>'id')::uuid);
  assert not (public.student_me_extra(s)->'issues'->0->>'unread')::boolean, 'read';
end $$;

-- ---------- Done – I have paid (no UTR), part payment, Not received → message until OK ----------
do $$
declare s uuid := 'a8a8a8a8-0000-0000-0000-000000000001'; r jsonb;
begin
  r := public.student_pay_bill(s, 'upi', null, 3000, null);
  assert (select utr is null and amount_claimed = 3000 and status = 'pending' from public.payments where id = (r->>'payment_id')::uuid),
    'UPI without UTR is a payment to check';
  begin perform public.student_pay_bill(s, 'upi', 'ab', 100, null); raise exception 'x';
  exception when others then if sqlerrm <> 'UTR_REQUIRED' then raise; end if; end;
end $$;
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888801';
select public.reject_payment((select id from public.payments where method = 'upi' limit 1), 'Not in bank');
reset role;
do $$
declare s uuid := 'a8a8a8a8-0000-0000-0000-000000000001'; m jsonb;
begin
  m := public.student_me_extra(s)->'messages';
  assert jsonb_array_length(m) = 1 and m->0->>'kind' = 'payment_not_received', 'red message for the student';
  assert (m->0->'params'->>'amount')::int = 3000, 'amount in the message';
  perform public.student_ack_message(s, (m->0->>'id')::uuid);
  assert jsonb_array_length(public.student_me_extra(s)->'messages') = 0, 'gone after OK';
end $$;

-- ---------- cash plan: tell the owner, replace, cancel, owner confirms ----------
do $$
declare s uuid := 'a8a8a8a8-0000-0000-0000-000000000001'; x jsonb;
begin
  perform public.student_cash_plan(s, 'today', 6500);
  perform public.student_cash_plan(s, 'tomorrow', 4000);
  assert (select count(*) from public.payments where method = 'cash' and status = 'pending') = 1, 'one cash plan at a time';
  x := public.student_me_extra(s)->'cash_plan';
  assert x->>'plan' = 'tomorrow' and (x->>'amount')::int = 4000, 'cash plan shown in Fees';
  assert (select count(*) from public.notifications where kind = 'cash') = 2, 'owner told each time';
  perform public.student_cancel_cash_plan(s);
  assert (select count(*) from public.payments where method = 'cash' and status = 'pending') = 0, 'cancelled';
  perform public.student_cash_plan(s, 'paid', 6500);
  begin perform public.student_cash_plan(s, 'someday', 10); raise exception 'x';
  exception when others then if sqlerrm <> 'BAD_PLAN' then raise; end if; end;
end $$;
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888801';
select public.confirm_payment((select id from public.payments where method = 'cash' and status = 'pending'), 6500) is not null as ok \gset
reset role;
do $$ begin
  assert (select status from public.bills where tenant_id = 'e8e8e8e8-0000-0000-0000-000000000001'
          and due_date = current_date - 10) = 'paid', 'cash received pays the bill';
  assert public.student_me_extra('a8a8a8a8-0000-0000-0000-000000000001')->'cash_plan' = 'null'::jsonb
      or public.student_me_extra('a8a8a8a8-0000-0000-0000-000000000001')->'cash_plan' is null, 'plan closed after Cash received';
end $$;

-- ---------- vacate notice: next fee date, then cancel ----------
do $$
declare s uuid := 'a8a8a8a8-0000-0000-0000-000000000001'; r jsonb;
begin
  r := public.student_give_notice(s, null);
  assert (r->>'leaving_date')::date = current_date + 20, 'leaving date = next fee date';
  assert (select status from public.tenants where id = 'e8e8e8e8-0000-0000-0000-000000000001') = 'notice', 'on notice';
  perform public.student_cancel_notice(s);
  assert (select status = 'active' and leaving_date is null from public.tenants where id = 'e8e8e8e8-0000-0000-0000-000000000001'),
    'notice cancelled';
  assert (select count(*) from public.notifications where kind = 'notice' and title = 'Notice cancelled') = 1, 'owner told';
end $$;

-- ---------- another owner can't see or change anything ----------
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888802';
do $$ begin
  assert (select count(*) from public.owner_notices) = 0, 'other owner: no notices';
  assert (select count(*) from public.complaints) = 0, 'other owner: no complaints';
  begin perform public.post_owner_notice('f8f8f8f8-0000-0000-0000-000000000001', 'other', 'Hi', null); raise exception 'x';
  exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end;
  begin perform public.update_complaint((select id from public.complaints limit 1), 'resolved', null); raise exception 'x';
  exception when others then if sqlerrm not in ('NOT_ALLOWED', 'NOT_FOUND') then raise; end if; end;
end $$;
-- owners can't call student functions or read ads
do $$ begin
  begin perform public.student_me_extra('a8a8a8a8-0000-0000-0000-000000000001'); raise exception 'x';
  exception when insufficient_privilege then null; end;
  begin perform count(*) from public.student_ads; raise exception 'x';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
-- owner removes his notice
set role authenticated;
set request.jwt.claim.sub = '88888888-0000-8888-8888-888888888801';
select public.remove_owner_notice(:'n1');
reset role;
do $$ begin assert (select count(*) from public.owner_notices) = 0, 'notice removed'; end $$;
\echo WAITING_FOR_FLUTTER_TESTS_PASSED
