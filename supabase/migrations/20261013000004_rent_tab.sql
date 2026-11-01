-- Rent tab redesign: month and today metrics, one list of every tenant with a status,
-- Auto-remind switch per hostel, and "Send reminder to all" (SMS through the rent-reminders function).

alter table public.hostels add column if not exists auto_remind boolean not null default true;

-- Every reminder SMS that was sent (manual = owner tapped "Send reminder to all", auto = daily job).
create table if not exists public.rent_reminders (
  id         uuid primary key default gen_random_uuid(),
  hostel_id  uuid not null references public.hostels (id) on delete cascade,
  tenant_id  uuid not null references public.tenants (id) on delete cascade,
  kind       text not null check (kind in ('manual', 'auto')),
  sent_at    timestamptz not null default now()
);
create index if not exists rent_reminders_tenant_idx on public.rent_reminders (tenant_id, sent_at desc);
alter table public.rent_reminders enable row level security;
create policy "own hostels: read reminders" on public.rent_reminders for select to authenticated
  using (private.owns_hostel(hostel_id));

-- ---------------------------------------------------------------------------
-- Rent tab data.
-- status per tenant: late (a bill due before today is unpaid), due (unpaid bill due today),
-- upcoming (unpaid bill due later this month), paid (this month's bills are paid).
-- ---------------------------------------------------------------------------
create or replace function public.rent_overview(p_hostel uuid, p_month date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  d date := private.today();
  m_start date := date_trunc('month', coalesce(p_month, d))::date;
  m_end date := (date_trunc('month', coalesce(p_month, d)) + interval '1 month')::date - 1;
  res jsonb;
begin
  perform private.assert_owner(p_hostel);

  with b as (
    select bl.*, greatest(bl.amount - bl.paid_amount, 0) as left_amt,
           bl.status in ('unpaid', 'partial') as open
    from public.bills bl
    where bl.hostel_id = p_hostel and bl.status <> 'cancelled' and bl.due_date <= m_end
  ),
  per as (
    select t.id as tenant_id, t.full_name, t.phone, r.room_no, bd.label as bed_label,
           coalesce(sum(b.amount) filter (where b.due_date >= m_start), 0)::int as month_amount,
           coalesce(sum(b.left_amt) filter (where b.open and b.due_date < d), 0)::int as late_left,
           coalesce(sum(b.left_amt) filter (where b.open and b.due_date >= d and b.due_date >= m_start), 0)::int as month_left,
           coalesce(sum(b.left_amt) filter (where b.open and b.due_date = d), 0)::int as today_left,
           min(b.due_date) filter (where b.open and b.due_date < d) as first_late,
           min(b.due_date) filter (where b.open and b.due_date >= d) as next_due
    from public.tenants t
    join b on b.tenant_id = t.id
    left join public.beds bd on bd.id = t.bed_id
    left join public.rooms r on r.id = bd.room_id
    where t.hostel_id = p_hostel and t.status in ('active', 'notice')
    group by t.id, t.full_name, t.phone, r.room_no, bd.label
  ),
  tr as (
    select p.*,
           case when p.late_left > 0 then 'late'
                when p.today_left > 0 then 'due'
                when p.month_left > 0 then 'upcoming'
                when p.month_amount > 0 then 'paid' end as status,
           (p.late_left + p.month_left) as due,
           coalesce(d - p.first_late, 0) as days_late,
           lp.paid_on, lp.method
    from per p
    left join lateral (
      select pm.paid_on, pm.method from public.payments pm
      where pm.tenant_id = p.tenant_id and pm.status = 'received' and pm.paid_on between m_start and m_end
      order by pm.paid_on desc, pm.created_at desc limit 1
    ) lp on true
  ),
  listed as (select * from tr where status is not null)
  select jsonb_build_object(
    'month_start', m_start,
    'is_current', d between m_start and m_end,
    'today', d,
    'billed', (select coalesce(sum(amount), 0) from public.bills
               where hostel_id = p_hostel and status <> 'cancelled' and due_date between m_start and m_end),
    'collected', (select coalesce(sum(amount_received), 0) from public.payments
                  where hostel_id = p_hostel and status = 'received' and paid_on between m_start and m_end),
    'paid_count', (select count(*) from listed where status = 'paid'),
    'to_pay', (select coalesce(sum(month_left), 0) from listed where status <> 'late'),
    'to_pay_count', (select count(*) from listed where status in ('due', 'upcoming')),
    'late_amount', (select coalesce(sum(late_left), 0) from listed),
    'late_count', (select count(*) from listed where status = 'late'),
    -- today (always about the real today)
    'today_collected', (select coalesce(sum(amount_received), 0) from public.payments
                        where hostel_id = p_hostel and status = 'received' and paid_on = d),
    'today_paid_count', (select count(distinct tenant_id) from public.payments
                         where hostel_id = p_hostel and status = 'received' and paid_on = d),
    'today_to_pay', (select coalesce(sum(greatest(bl.amount - bl.paid_amount, 0)), 0) from public.bills bl
                     join public.tenants t on t.id = bl.tenant_id
                     where bl.hostel_id = p_hostel and bl.due_date = d and bl.status in ('unpaid', 'partial')
                       and t.status in ('active', 'notice')),
    'today_to_pay_count', (select count(distinct bl.tenant_id) from public.bills bl
                           join public.tenants t on t.id = bl.tenant_id
                           where bl.hostel_id = p_hostel and bl.due_date = d and bl.status in ('unpaid', 'partial')
                             and t.status in ('active', 'notice')),
    'today_due_count', (select count(distinct bl.tenant_id) from public.bills bl
                        join public.tenants t on t.id = bl.tenant_id
                        where bl.hostel_id = p_hostel and bl.due_date = d and bl.status <> 'cancelled'
                          and t.status in ('active', 'notice')),
    'late_now', (select coalesce(sum(greatest(bl.amount - bl.paid_amount, 0)), 0) from public.bills bl
                 join public.tenants t on t.id = bl.tenant_id
                 where bl.hostel_id = p_hostel and bl.due_date < d and bl.status in ('unpaid', 'partial')
                   and t.status in ('active', 'notice')),
    'late_now_count', (select count(distinct bl.tenant_id) from public.bills bl
                       join public.tenants t on t.id = bl.tenant_id
                       where bl.hostel_id = p_hostel and bl.due_date < d and bl.status in ('unpaid', 'partial')
                         and t.status in ('active', 'notice')),
    'to_check', (select count(*) from public.payments where hostel_id = p_hostel and status = 'pending'),
    'auto_remind', (select auto_remind from public.hostels where id = p_hostel),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tenant_id', tenant_id, 'full_name', full_name, 'phone', phone,
               'room_no', room_no, 'bed_label', bed_label, 'status', status,
               'amount', case when status = 'paid' then month_amount else due end,
               'due', due, 'days_late', days_late, 'next_due', next_due,
               'paid_on', paid_on, 'method', method)
             order by case status when 'late' then 0 when 'due' then 1 when 'upcoming' then 2 else 3 end,
                      days_late desc, next_due, full_name)
      from listed), '[]'::jsonb),
    -- kept for older app versions
    'pending', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tenant_id', tenant_id, 'full_name', full_name, 'phone', phone,
               'room_no', room_no, 'bed_label', bed_label, 'due', late_left + today_left,
               'days_late', days_late) order by days_late desc)
      from listed where status in ('late', 'due')), '[]'::jsonb)
  ) into res;
  return res;
end;
$$;

-- Tenants to remind now: anyone with unpaid rent due up to the end of this month,
-- not already reminded in the last 12 hours.
create or replace function public.rent_reminder_targets(p_hostel uuid)
returns table (tenant_id uuid, phone text, full_name text, due int, due_date date)
language plpgsql stable security definer set search_path = '' as $$
declare
  d date := private.today();
  m_end date := (date_trunc('month', d) + interval '1 month')::date - 1;
begin
  perform private.assert_owner(p_hostel);
  return query
    select t.id, t.phone, t.full_name, sum(greatest(b.amount - b.paid_amount, 0))::int, min(b.due_date)
    from public.bills b
    join public.tenants t on t.id = b.tenant_id
    where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial') and b.due_date <= m_end
      and t.status in ('active', 'notice')
      and not exists (select 1 from public.rent_reminders rr
                      where rr.tenant_id = t.id and rr.sent_at > now() - interval '12 hours')
    group by t.id, t.phone, t.full_name
    having sum(greatest(b.amount - b.paid_amount, 0)) > 0;
end;
$$;

-- Daily automatic reminders (hostels with Auto-remind on): rent due in 3 days or today, not reminded today.
create or replace function public.auto_reminder_targets()
returns table (hostel_id uuid, hostel_name text, tenant_id uuid, phone text, full_name text, due int, due_date date)
language sql stable security definer set search_path = '' as $$
  select h.id, h.name, t.id, t.phone, t.full_name,
         sum(greatest(b.amount - b.paid_amount, 0))::int, min(b.due_date)
  from public.bills b
  join public.tenants t on t.id = b.tenant_id
  join public.hostels h on h.id = b.hostel_id
  where h.auto_remind and b.status in ('unpaid', 'partial')
    and b.due_date in (private.today(), private.today() + 3)
    and t.status in ('active', 'notice')
    and not exists (select 1 from public.rent_reminders rr
                    where rr.tenant_id = t.id and rr.sent_at > now() - interval '20 hours')
  group by h.id, h.name, t.id, t.phone, t.full_name
  having sum(greatest(b.amount - b.paid_amount, 0)) > 0
  limit 5000;
$$;

revoke execute on function public.rent_reminder_targets(uuid), public.auto_reminder_targets()
  from public, anon, authenticated;
grant execute on function public.rent_reminder_targets(uuid) to authenticated;
grant execute on function public.auto_reminder_targets() to service_role;
grant select on public.rent_reminders to authenticated;
grant select, insert on public.rent_reminders to service_role;
