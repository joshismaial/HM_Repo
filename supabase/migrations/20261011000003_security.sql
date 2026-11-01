-- My Hostel – security rules
-- Owners only ever see rows of their own hostels (row-level security).
-- Students never talk to the database directly: everything goes through Edge Functions.

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.profiles         enable row level security;
alter table public.hostels          enable row level security;
alter table public.rooms            enable row level security;
alter table public.beds             enable row level security;
alter table public.tenants          enable row level security;
alter table public.student_sessions enable row level security;
alter table public.otp_codes        enable row level security;
alter table public.bills            enable row level security;
alter table public.payments         enable row level security;
alter table public.notifications    enable row level security;
alter table public.id_reveal_log    enable row level security;

-- profiles: own row only
create policy "own profile: read"   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "own profile: update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- hostels: owner can do everything with their own hostels
alter table public.hostels alter column owner_id set default auth.uid();
create policy "own hostels: read"   on public.hostels for select to authenticated using (owner_id = (select auth.uid()));
create policy "own hostels: add"    on public.hostels for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "own hostels: update" on public.hostels for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "own hostels: delete" on public.hostels for delete to authenticated using (owner_id = (select auth.uid()));

-- rooms: read + edit own (adding goes through add_room, deleting through delete_room)
create policy "own rooms: read"   on public.rooms for select to authenticated using (private.owns_hostel(hostel_id));
create policy "own rooms: update" on public.rooms for update to authenticated
  using (private.owns_hostel(hostel_id)) with check (private.owns_hostel(hostel_id));

-- beds, bills, payments, notifications, reveal log: read only (changes go through functions)
create policy "own beds: read"          on public.beds          for select to authenticated using (private.owns_hostel(hostel_id));
create policy "own bills: read"         on public.bills         for select to authenticated using (private.owns_hostel(hostel_id));
create policy "own payments: read"      on public.payments      for select to authenticated using (private.owns_hostel(hostel_id));
create policy "own notifications: read" on public.notifications for select to authenticated using (private.owns_hostel(hostel_id));
create policy "own reveal log: read"    on public.id_reveal_log for select to authenticated
  using (exists (select 1 from public.tenants t where t.id = tenant_id and private.owns_hostel(t.hostel_id)));

-- tenants: owners read their tenants and may correct a few details
create policy "own tenants: read"   on public.tenants for select to authenticated using (private.owns_hostel(hostel_id));
create policy "own tenants: update" on public.tenants for update to authenticated
  using (private.owns_hostel(hostel_id)) with check (private.owns_hostel(hostel_id));

-- student_sessions, otp_codes: no policies => no access for anon/authenticated.

-- ---------------------------------------------------------------------------
-- Column-level protection
-- ---------------------------------------------------------------------------
-- Owners must never read the encrypted ID number directly (use reveal_id_number, which is logged).
revoke select on public.tenants from authenticated;
grant select (id, hostel_id, bed_id, phone, full_name, parent_phone, reference_phone, id_type, id_last4,
              id_file_key, photo_key, home_address, office_address, joining_date, is_existing, stay_type,
              rent_month, deposit, status, consent_at, notice_given_at, leaving_date, vacated_at,
              deposit_deduction, deposit_refund, files_purged_at, created_at, updated_at)
  on public.tenants to authenticated;
revoke update on public.tenants from authenticated;
grant update (full_name, parent_phone, reference_phone, home_address, office_address, rent_month)
  on public.tenants to authenticated;

revoke update on public.rooms from authenticated;
grant update (room_no, floor, rent_month, deposit_month, features, separate_meter) on public.rooms to authenticated;

revoke update on public.profiles from authenticated;
grant update (full_name, language) on public.profiles to authenticated;

revoke insert, update, delete on public.beds, public.bills, public.payments, public.notifications,
  public.id_reveal_log, public.student_sessions, public.otp_codes from authenticated, anon;
revoke all on public.student_sessions, public.otp_codes from anon, authenticated;
-- anonymous visitors never touch tables (students go through Edge Functions)
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

-- ---------------------------------------------------------------------------
-- Function permissions
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;
-- helpers used inside row-level security checks
grant execute on function private.owns_hostel(uuid) to authenticated;
-- default value of hostels.join_code
grant execute on function private.gen_join_code() to authenticated;

-- owner functions
grant execute on function
  public.add_room(uuid, text, int, int, int, int, text[], boolean, int),
  public.delete_room(uuid),
  public.set_bed_offline(uuid, boolean),
  public.confirm_payment(uuid, int),
  public.reject_payment(uuid, text),
  public.approve_tenant(uuid),
  public.reject_tenant(uuid),
  public.record_payment(uuid, int, public.pay_method, date, text),
  public.reveal_id_number(uuid),
  public.mark_vacated(uuid, int),
  public.hostel_summary(uuid),
  public.rent_overview(uuid, date),
  public.mark_notifications_read(uuid),
  public.request_account_deletion(),
  public.cancel_account_deletion()
to authenticated;

-- student + scheduled functions: server only
grant execute on function
  public.student_start_session(text, text, text),
  public.student_session_by_hash(text),
  public.student_hostel(uuid),
  public.student_rooms(uuid),
  public.student_hold_bed(uuid, uuid),
  public.student_quote(uuid),
  public.student_submit_details(uuid, text, text, text, public.id_type, text, text, text, text, text, boolean, date, boolean),
  public.student_submit_payment(uuid, public.pay_method, text, date),
  public.student_me(uuid),
  public.student_pay_bill(uuid, public.pay_method, text, int, date),
  public.student_give_notice(uuid, date),
  public.release_expired_holds(),
  public.generate_rent_bills(date),
  public.files_to_purge(),
  public.mark_files_purged(uuid[]),
  public.accounts_to_delete()
to service_role;

-- new functions are not executable by default
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Scheduled jobs (pg_cron). Enable "pg_cron" in Supabase → Database → Extensions first.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('release-expired-holds', '* * * * *', 'select public.release_expired_holds()');
    perform cron.schedule('generate-rent-bills', '30 0 * * *', 'select public.generate_rent_bills()'); -- 06:00 IST
  end if;
end;
$$;
