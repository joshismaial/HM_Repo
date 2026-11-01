-- Removed hostels (hostels.archived_at set) must stay quiet:
-- no new rent bills, no "New joiner waiting" notifications, no automatic rent SMS.
-- Housekeeping (release-expired-holds) keeps running for every hostel.
-- Restoring a hostel (archived_at = null) makes these jobs pick it up again;
-- rent bills for the removed period are then created by the next daily run.

create or replace function public.generate_rent_bills(p_today date default null::date)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  today date := coalesce(p_today, private.today());
  t record;
  last_end date;
  s_d date;
  e_d date;
  n int := 0;
begin
  for t in select * from public.tenants tn
            where tn.status in ('active', 'notice') and tn.stay_type = 'monthly'
              and not exists (select 1 from public.hostels h
                               where h.id = tn.hostel_id and h.archived_at is not null) loop
    select max(period_end) into last_end from public.bills where tenant_id = t.id and kind = 'rent';
    if last_end is null then continue; end if;
    loop
      s_d := last_end + 1;
      exit when s_d > today + 3;
      exit when t.status = 'notice' and t.leaving_date is not null and s_d > t.leaving_date;
      e_d := (s_d + interval '1 month')::date - 1;
      insert into public.bills (hostel_id, tenant_id, kind, label, period_start, period_end, amount, due_date)
      values (t.hostel_id, t.id, 'rent', 'Rent ' || to_char(s_d, 'DD Mon') || ' – ' || to_char(e_d, 'DD Mon'),
              s_d, e_d, t.rent_month, s_d)
      on conflict do nothing;
      n := n + 1;
      last_end := e_d;
    end loop;
    perform private.allocate_payments(t.id);
  end loop;
  return n;
end;
$function$;

create or replace function private.remind_pending_joiners()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  n int := 0;
begin
  for r in
    select t.id, t.hostel_id, t.full_name from public.tenants t
     where t.status = 'pending_approval' and not t.is_existing and t.owner_reminded_at is null
       and exists (select 1 from public.payments p
                    where p.tenant_id = t.id and p.status = 'pending' and p.created_at < now() - interval '2 hours')
       and not exists (select 1 from public.hostels h
                        where h.id = t.hostel_id and h.archived_at is not null)
       for update of t skip locked
  loop
    update public.tenants set owner_reminded_at = now() where id = r.id;
    perform private.notify(r.hostel_id, 'reminder', 'New joiner waiting',
      coalesce(r.full_name, 'A new student') || ' paid more than 2 hours ago. Confirm or reject the booking.', r.id);
    n := n + 1;
  end loop;
  return n;
end;
$function$;

create or replace function public.auto_reminder_targets()
returns table(hostel_id uuid, hostel_name text, tenant_id uuid, phone text, full_name text, due integer, due_date date)
language sql
stable security definer
set search_path to ''
as $function$
  select h.id, h.name, t.id, t.phone, t.full_name,
         sum(greatest(b.amount - b.paid_amount, 0))::int, min(b.due_date)
  from public.bills b
  join public.tenants t on t.id = b.tenant_id
  join public.hostels h on h.id = b.hostel_id
  where h.auto_remind and h.archived_at is null and b.status in ('unpaid', 'partial')
    and b.due_date in (private.today(), private.today() + 3)
    and t.status in ('active', 'notice')
    and not exists (select 1 from public.rent_reminders rr
                    where rr.tenant_id = t.id and rr.sent_at > now() - interval '20 hours')
  group by h.id, h.name, t.id, t.phone, t.full_name
  having sum(greatest(b.amount - b.paid_amount, 0)) > 0
  limit 5000;
$function$;
