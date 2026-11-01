-- Rent tab (rent_overview v2) and reminder targets. Run after the migrations on a fresh test database.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, phone, raw_user_meta_data) values
  ('33333333-3333-3333-3333-333333333333', '+919848000033', '{"full_name":"Rent Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone)
values ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
        'Rent Test Hostel', 'mens', 'Road 1, Area', 'Hyderabad', '500001', '+919848000033');
-- five tenants: late, due today, upcoming, paid, plus a vacated one that must not show
insert into public.tenants (id, hostel_id, full_name, phone, status, rent_month) values
  ('b0000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Late Larry',  '+919000000101', 'active', 8000),
  ('b0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Due Dina',    '+919000000102', 'active', 6500),
  ('b0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'Up Uma',      '+919000000103', 'notice', 5500),
  ('b0000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001', 'Paid Pavan',  '+919000000104', 'active', 6500),
  ('b0000000-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000001', 'Gone Gopi',   '+919000000105', 'vacated', 6000);
do $$
declare h uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; d date := private.today();
  m_end date := (date_trunc('month', d) + interval '1 month')::date - 1;
begin
  insert into public.bills (hostel_id, tenant_id, kind, label, amount, paid_amount, due_date, status) values
    (h, 'b0000000-0000-0000-0000-000000000001', 'rent', 'Rent', 8000, 0,    d - 8, 'unpaid'),
    (h, 'b0000000-0000-0000-0000-000000000002', 'rent', 'Rent', 6500, 1000, d,     'partial'),
    (h, 'b0000000-0000-0000-0000-000000000003', 'rent', 'Rent', 5500, 0,    least(d + 2, m_end), 'unpaid'),
    (h, 'b0000000-0000-0000-0000-000000000004', 'rent', 'Rent', 6500, 6500, d,     'paid'),
    (h, 'b0000000-0000-0000-0000-000000000005', 'rent', 'Rent', 6000, 0,    d - 3, 'unpaid');
  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, amount_received, paid_on, status, created_by) values
    (h, 'b0000000-0000-0000-0000-000000000004', 'cash', 6500, 6500, d, 'received', 'owner'),
    (h, 'b0000000-0000-0000-0000-000000000002', 'upi',  1000, 1000, d, 'received', 'owner');
end $$;

set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$
declare r jsonb := public.rent_overview('aaaaaaaa-0000-0000-0000-000000000001');
begin
  assert jsonb_array_length(r->'rows') = 4, 'vacated tenant hidden';
  assert r->'rows'->0->>'status' = 'late' and (r->'rows'->0->>'days_late')::int = 8, 'late first';
  assert r->'rows'->1->>'status' = 'due' and (r->'rows'->1->>'amount')::int = 5500, 'due today, part paid';
  assert (select count(*) from jsonb_array_elements(r->'rows') e where e->>'status' = 'paid' and e->>'method' = 'cash') = 1, 'paid with method';
  assert (r->>'late_amount')::int = 8000 and (r->>'late_count')::int = 1, 'late metrics';
  assert (r->>'today_collected')::int = 7500 and (r->>'today_paid_count')::int = 2, 'today collected';
  assert (r->>'today_to_pay')::int = 5500 and (r->>'today_to_pay_count')::int = 1, 'today still to pay';
  assert (r->>'today_due_count')::int = 2, 'two tenants due today';
  assert (r->>'to_pay')::int = 5500 + 5500, 'month still to pay (due + upcoming)';
  assert (r->>'to_pay_count')::int = 2, 'two still to pay';
  assert (r->>'paid_count')::int = 1, 'one paid';
  assert (r->>'auto_remind')::boolean, 'auto remind default on';
  assert jsonb_array_length(r->'pending') = 2, 'old pending list kept';
  assert (select count(*) from public.rent_reminder_targets('aaaaaaaa-0000-0000-0000-000000000001')) = 2, 'remind only due today or late';
end $$;
-- the owner can switch Auto-remind off
update public.hostels set auto_remind = false where id = 'aaaaaaaa-0000-0000-0000-000000000001';
-- another owner cannot read this hostel's rent
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
  begin
    perform public.rent_overview('aaaaaaaa-0000-0000-0000-000000000001');
    raise exception 'other owner read rent';
  exception when others then
    if sqlerrm = 'other owner read rent' then raise; end if;
  end;
end $$;
reset role;
do $$ begin
  assert not (select auto_remind from public.hostels where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'switched off';
  assert (select count(*) from public.auto_reminder_targets() where hostel_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'no auto when off';
  update public.hostels set auto_remind = true where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  -- auto: due today (Dina) only; Uma is due in 2 days, Larry is late
  assert (select count(*) from public.auto_reminder_targets() where hostel_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 1, 'auto targets';
  insert into public.rent_reminders (hostel_id, tenant_id, kind) values
    ('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'auto');
  assert (select count(*) from public.auto_reminder_targets() where hostel_id = 'aaaaaaaa-0000-0000-0000-000000000001') = 0, 'not twice a day';
end $$;

-- ---------- Late fee ----------
update public.hostels set late_fee_on = true, late_fee_per_day = 50 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$
declare r jsonb := public.rent_overview('aaaaaaaa-0000-0000-0000-000000000001');
  q jsonb := public.owner_late_fee('b0000000-0000-0000-0000-000000000001');
begin
  assert (r->'rows'->0->>'late_fee')::int = 400, 'late fee 8 days x 50';
  assert (r->'rows'->0->>'amount')::int = 8400, 'amount includes fee';
  assert (r->>'late_amount')::int = 8400, 'late now includes fee';
  assert (q->>'fee')::int = 400 and (q->>'days')::int = 8 and (q->>'rent_due')::int = 8000, 'record payment quote';
  assert (select due from public.rent_reminder_targets('aaaaaaaa-0000-0000-0000-000000000001') where full_name = 'Late Larry') = 8400, 'reminder includes fee';
end $$;
-- Larry pays rent + fee: a Late fee bill is created and both are paid
select public.record_payment('b0000000-0000-0000-0000-000000000001', 8400, 'cash', (select (r->>'today')::date from (select public.rent_overview('aaaaaaaa-0000-0000-0000-000000000001') r) x)) is not null as p1 \gset
do $$
declare r jsonb := public.rent_overview('aaaaaaaa-0000-0000-0000-000000000001');
begin
  assert (select count(*) from jsonb_array_elements(r->'rows') e where e->>'full_name' = 'Late Larry' and e->>'status' = 'paid') = 1, 'larry paid incl fee';
  assert (public.owner_late_fee('b0000000-0000-0000-0000-000000000001')->>'fee')::int = 0, 'no more fee';
end $$;
reset role;
do $$ begin
  assert (select amount from public.bills where tenant_id = 'b0000000-0000-0000-0000-000000000001' and kind = 'other') = 400, 'late fee bill';
  assert (select count(*) from public.bills where tenant_id = 'b0000000-0000-0000-0000-000000000001' and status = 'paid') = 2, 'rent + fee paid';
end $$;
-- waived: no fee bill, counting restarts
insert into public.bills (hostel_id, tenant_id, kind, label, amount, due_date)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'rent', 'Old rent', 3000, current_date - 5);
set role authenticated;
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ begin
  assert (public.owner_late_fee('b0000000-0000-0000-0000-000000000002')->>'fee')::int > 0, 'dina has fee';
end $$;
select public.record_payment('b0000000-0000-0000-0000-000000000002', 1000, 'upi', current_date, null, true) is not null as p2 \gset
do $$ begin
  assert (public.owner_late_fee('b0000000-0000-0000-0000-000000000002')->>'fee')::int = 0, 'waived fee gone';
end $$;
reset role;
do $$ begin
  assert (select count(*) from public.bills where tenant_id = 'b0000000-0000-0000-0000-000000000002' and kind = 'other') = 0, 'no fee bill when waived';
  -- switched off: no fee
  update public.hostels set late_fee_on = false where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  assert (select fee from private.late_fee('b0000000-0000-0000-0000-000000000002', current_date + 10)) = 0, 'off = no fee';
end $$;
\echo RENT_TAB_TESTS_PASSED
