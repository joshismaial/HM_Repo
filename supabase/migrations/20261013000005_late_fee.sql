-- Late fee per day (owner switch + amount in the Rent tab).
-- Fee = days late × amount per day, for every unpaid rent bill, counted from the rent day
-- (or from the last time a fee was charged / waived) until the payment date.
-- When a payment is recorded / confirmed, the fee so far becomes a separate "Late fee" bill,
-- unless the owner ticks "Waive late fee".
-- Also: "Send reminder to all" now only reminds tenants whose rent is due today or late.

alter table public.hostels add column if not exists late_fee_on boolean not null default false;
alter table public.hostels add column if not exists late_fee_per_day int not null default 0
  check (late_fee_per_day between 0 and 10000);
alter table public.bills add column if not exists late_fee_from date;

-- Late fee for one tenant up to a date (0 when the hostel has it switched off).
create or replace function private.late_fee(p_tenant uuid, p_until date)
returns table (days int, fee int, per_day int)
language sql stable security definer set search_path = '' as $$
  select coalesce(max(p_until - b.due_date), 0)::int,
         coalesce(sum(greatest(p_until - greatest(b.due_date, coalesce(b.late_fee_from, b.due_date)), 0)), 0)::int
           * coalesce(max(h.late_fee_per_day), 0),
         coalesce(max(h.late_fee_per_day), 0)
  from public.tenants t
  join public.hostels h on h.id = t.hostel_id and h.late_fee_on and h.late_fee_per_day > 0
  join public.bills b on b.tenant_id = t.id and b.kind = 'rent'
   and b.status in ('unpaid', 'partial') and b.due_date < p_until
  where t.id = p_tenant;
$$;

-- Turn the late fee so far into a bill (or drop it when waived) and restart counting from p_until.
create or replace function private.charge_late_fee(p_tenant uuid, p_until date, p_waive boolean default false)
returns int language plpgsql security definer set search_path = '' as $$
declare
  lf record;
  t public.tenants;
begin
  select * into lf from private.late_fee(p_tenant, p_until);
  if lf.fee is null or lf.fee <= 0 then return 0; end if;
  select * into t from public.tenants where id = p_tenant;
  if not p_waive then
    insert into public.bills (hostel_id, tenant_id, kind, label, amount, due_date)
    values (t.hostel_id, t.id, 'other', 'Late fee (' || lf.days || ' days × Rs.' || lf.per_day || ')', lf.fee, p_until);
  end if;
  update public.bills set late_fee_from = p_until
   where tenant_id = p_tenant and kind = 'rent' and status in ('unpaid', 'partial') and due_date < p_until;
  return case when p_waive then 0 else lf.fee end;
end;
$$;

-- Record payment screen: rent due now + late fee so far.
create or replace function public.owner_late_fee(p_tenant uuid, p_until date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  t public.tenants;
  h public.hostels;
  d date := coalesce(p_until, private.today());
  lf record;
begin
  select * into t from public.tenants where id = p_tenant;
  perform private.assert_owner(t.hostel_id);
  select * into h from public.hostels where id = t.hostel_id;
  select * into lf from private.late_fee(p_tenant, d);
  return jsonb_build_object(
    'late_fee_on', h.late_fee_on and h.late_fee_per_day > 0,
    'per_day', h.late_fee_per_day,
    'days', coalesce(lf.days, 0),
    'fee', coalesce(lf.fee, 0),
    'rent_due', (select coalesce(sum(greatest(amount - paid_amount, 0)), 0) from public.bills
                 where tenant_id = p_tenant and status in ('unpaid', 'partial') and due_date <= d));
end;
$$;

-- Record payment: late fee is charged first unless waived.
drop function if exists public.record_payment(uuid, int, public.pay_method, date, text);
create or replace function public.record_payment(
  p_tenant uuid, p_amount int, p_method public.pay_method, p_paid_on date, p_note text default null,
  p_waive_late_fee boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t public.tenants;
  pid uuid;
begin
  select * into t from public.tenants where id = p_tenant;
  perform private.assert_owner(t.hostel_id);
  if t.status not in ('active', 'notice', 'pending_approval', 'vacated') then raise exception 'NOT_ACTIVE'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000 then raise exception 'BAD_AMOUNT'; end if;
  if p_paid_on is null or p_paid_on > private.today() then raise exception 'BAD_DATE'; end if;
  perform private.charge_late_fee(t.id, p_paid_on, coalesce(p_waive_late_fee, false));
  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, amount_received, paid_on,
                               status, note, created_by, recorded_by, decided_at)
  values (t.hostel_id, t.id, p_method, p_amount, p_amount, p_paid_on, 'received', p_note, 'owner', auth.uid(), now())
  returning id into pid;
  perform private.allocate_payments(t.id);
  return pid;
end;
$$;

-- Student payment confirmed by the owner: late fee up to the payment date is charged.
create or replace function public.confirm_payment(p_payment uuid, p_amount_received int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare p public.payments;
begin
  select * into p from public.payments where id = p_payment for update;
  perform private.assert_owner(p.hostel_id);
  if p.status <> 'pending' then raise exception 'ALREADY_DECIDED'; end if;
  if p_amount_received is null or p_amount_received <= 0 then raise exception 'BAD_AMOUNT'; end if;
  update public.payments
     set status = 'received', amount_received = p_amount_received, decided_at = now(), recorded_by = auth.uid()
   where id = p_payment;
  perform private.activate_tenant(p.tenant_id);   -- no-op if already active
  perform private.charge_late_fee(p.tenant_id, least(p.paid_on, private.today()));
  perform private.allocate_payments(p.tenant_id);
  return jsonb_build_object('tenant_id', p.tenant_id, 'part_payment', p_amount_received < p.amount_claimed);
end;
$$;

-- Rent tab data, now with the late fee.
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
    select p.*, coalesce(lf.fee, 0) as late_fee,
           case when p.late_left > 0 then 'late'
                when p.today_left > 0 then 'due'
                when p.month_left > 0 then 'upcoming'
                when p.month_amount > 0 then 'paid' end as status,
           (p.late_left + p.month_left) as due,
           coalesce(d - p.first_late, 0) as days_late,
           lp.paid_on, lp.method
    from per p
    left join lateral (select * from private.late_fee(p.tenant_id, d)) lf on true
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
    'late_amount', (select coalesce(sum(late_left + late_fee), 0) from listed),
    'late_fee_total', (select coalesce(sum(late_fee), 0) from listed),
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
                   and t.status in ('active', 'notice'))
               + (select coalesce(sum(lf.fee), 0) from public.tenants t
                  cross join lateral private.late_fee(t.id, d) lf
                  where t.hostel_id = p_hostel and t.status in ('active', 'notice')),
    'late_now_count', (select count(distinct bl.tenant_id) from public.bills bl
                       join public.tenants t on t.id = bl.tenant_id
                       where bl.hostel_id = p_hostel and bl.due_date < d and bl.status in ('unpaid', 'partial')
                         and t.status in ('active', 'notice')),
    'to_check', (select count(*) from public.payments where hostel_id = p_hostel and status = 'pending'),
    'auto_remind', (select auto_remind from public.hostels where id = p_hostel),
    'late_fee_on', (select late_fee_on from public.hostels where id = p_hostel),
    'late_fee_per_day', (select late_fee_per_day from public.hostels where id = p_hostel),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tenant_id', tenant_id, 'full_name', full_name, 'phone', phone,
               'room_no', room_no, 'bed_label', bed_label, 'status', status,
               'amount', case when status = 'paid' then month_amount else due + late_fee end,
               'due', due, 'late_fee', late_fee, 'days_late', days_late, 'next_due', next_due,
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


-- "Send reminder to all": only tenants whose rent is due today or late (amount includes the late fee).
create or replace function public.rent_reminder_targets(p_hostel uuid)
returns table (tenant_id uuid, phone text, full_name text, due int, due_date date)
language plpgsql stable security definer set search_path = '' as $$
declare
  d date := private.today();
begin
  perform private.assert_owner(p_hostel);
  return query
    select x.id, x.phone, x.full_name, (x.due + coalesce((select lf.fee from private.late_fee(x.id, d) lf), 0))::int, x.due_date
    from (
      select t.id, t.phone, t.full_name, sum(greatest(b.amount - b.paid_amount, 0))::int as due, min(b.due_date) as due_date
      from public.bills b
      join public.tenants t on t.id = b.tenant_id
      where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial') and b.due_date <= d
        and t.status in ('active', 'notice')
        and not exists (select 1 from public.rent_reminders rr
                        where rr.tenant_id = t.id and rr.sent_at > now() - interval '12 hours')
      group by t.id, t.phone, t.full_name
      having sum(greatest(b.amount - b.paid_amount, 0)) > 0
    ) x;
end;
$$;

-- Student app: late fee so far (shown on "Your bill" and added to Pay now).
create or replace function public.student_me_extra(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  lf record;
begin
  if s.tenant_id is not null then select * into t from public.tenants where id = s.tenant_id;
  else t := private.session_tenant(s); end if;
  if t.id is null then raise exception 'NO_BOOKING'; end if;
  select * into lf from private.late_fee(t.id, private.today());
  return jsonb_build_object('org_name', t.org_name, 'has_photo', t.photo_key is not null,
    'late_fee', coalesce(lf.fee, 0), 'late_days', coalesce(lf.days, 0), 'late_fee_per_day', coalesce(lf.per_day, 0));
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
revoke execute on function private.late_fee(uuid, date), private.charge_late_fee(uuid, date, boolean)
  from public, anon, authenticated;
revoke execute on function public.owner_late_fee(uuid, date),
  public.record_payment(uuid, int, public.pay_method, date, text, boolean)
  from public, anon;
grant execute on function public.owner_late_fee(uuid, date),
  public.record_payment(uuid, int, public.pay_method, date, text, boolean)
  to authenticated;
