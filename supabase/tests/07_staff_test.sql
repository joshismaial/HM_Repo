-- Staff page (owner only): add with job duties, change duties, typed duties, checklist, remove.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, phone, raw_user_meta_data) values
  ('77777777-0000-7777-7777-777777777707', '+919848000707', '{"full_name":"Staff Owner"}');
insert into public.hostels (id, owner_id, name, type, address, city, pincode, contact_phone)
values ('f7f7f7f7-0000-0000-0000-000000000001', '77777777-0000-7777-7777-777777777707',
        'Staff PG', 'mens', 'Road 7, Area', 'Hyderabad', '500007', '+919848000707');
set role authenticated;
set request.jwt.claim.sub = '77777777-0000-7777-7777-777777777707';
do $$
declare h uuid := 'f7f7f7f7-0000-0000-0000-000000000001'; m uuid; c uuid; l jsonb;
begin
  -- manager added with the job's duties (p_duties null)
  m := public.save_staff(h, null, 'Ramesh Kumar', '+919848011223', 'manager', null, null, '[]', 'Lock gate 10:30 PM');
  assert (select duties from public.staff where id = m) = array['rent', 'approve', 'rooms', 'complaints', 'leaving', 'checklist'], 'manager duties';
  c := public.save_staff(h, null, 'Sunita', '+919000055667', 'cleaning', null, null, '[]', null);
  assert (select duties from public.staff where id = c) = array['complaints', 'checklist'], 'cleaning duties';
  -- owner changes duties and adds his own duty
  perform public.save_staff(h, c, 'Sunita Lakshmi', '+919000055667', 'cleaning', null, array['complaints'],
    '[{"name":"Buy cleaning items","on":true}]', 'Bathrooms 8 AM');
  assert (select name from public.staff where id = c) = 'Sunita Lakshmi', 'name changed';
  assert (select custom_duties->0->>'name' from public.staff where id = c) = 'Buy cleaning items', 'typed duty saved';
  l := public.staff_list(h);
  assert jsonb_array_length(l) = 2 and l->0->>'name' = 'Ramesh Kumar', 'list in order added';
  -- same phone twice
  begin perform public.save_staff(h, null, 'Copy', '+919848011223', 'cook', null, null, '[]', null); raise exception 'x';
  exception when others then if sqlerrm <> 'STAFF_EXISTS' then raise; end if; end;
  begin perform public.save_staff(h, null, 'Bad', '+91123', 'cook', null, null, '[]', null); raise exception 'x';
  exception when others then if sqlerrm <> 'BAD_PHONE' then raise; end if; end;
  begin perform public.save_staff(h, null, 'Bad duty', '+919876543210', 'cook', null, array['fly'], '[]', null); raise exception 'x';
  exception when others then if sqlerrm <> 'BAD_DUTY' then raise; end if; end;
  perform public.remove_staff(c);
  assert jsonb_array_length(public.staff_list(h)) = 1, 'removed';
end $$;
reset role;
-- another owner can't see or change this staff
insert into auth.users (id, phone) values ('77777777-0000-7777-7777-777777777708', '+919848000708');
set role authenticated;
set request.jwt.claim.sub = '77777777-0000-7777-7777-777777777708';
do $$ begin
  perform public.staff_list('f7f7f7f7-0000-0000-0000-000000000001'); raise exception 'x';
exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end $$;
do $$ begin
  perform public.save_staff('f7f7f7f7-0000-0000-0000-000000000001', null, 'Intruder', '+919812345678', 'cook', null, null, '[]', null);
  raise exception 'x';
exception when others then if sqlerrm <> 'NOT_ALLOWED' then raise; end if; end $$;
do $$ begin
  assert (select count(*) from public.staff) = 0, 'other owner sees no staff rows';
end $$;
reset role;
\echo STAFF_TESTS_PASSED
