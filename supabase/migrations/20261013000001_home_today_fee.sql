-- Home screen: add this month's billed rent and today's dues to hostel_summary.
-- Same function as before, with 5 new keys at the end.
create or replace function public.hostel_summary(p_hostel uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  month_start date := date_trunc('month', private.today())::date;
  month_end date := (date_trunc('month', private.today()) + interval '1 month')::date - 1;
  d date := private.today();
begin
  perform private.assert_owner(p_hostel);
  return jsonb_build_object(
    'beds_total', (select count(*) from public.beds where hostel_id = p_hostel),
    'beds_filled', (select count(*) from public.beds where hostel_id = p_hostel and status in ('occupied', 'offline_occupied')),
    'beds_held', (select count(*) from public.beds where hostel_id = p_hostel and status = 'held' and held_until > now()),
    'rooms', (select count(*) from public.rooms where hostel_id = p_hostel),
    'collected_month', (select coalesce(sum(amount_received), 0) from public.payments
                        where hostel_id = p_hostel and status = 'received' and paid_on >= month_start),
    'pending_amount', (select coalesce(sum(greatest(b.amount - b.paid_amount, 0)), 0) from public.bills b
                       join public.tenants t on t.id = b.tenant_id
                       where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial')
                         and b.due_date <= private.today() and t.status in ('active', 'notice')),
    'pending_tenants', (select count(distinct b.tenant_id) from public.bills b
                        join public.tenants t on t.id = b.tenant_id
                        where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial')
                          and b.due_date <= private.today() and t.status in ('active', 'notice')),
    'payments_to_check', (select count(*) from public.payments where hostel_id = p_hostel and status = 'pending'),
    'joins_to_approve', (select count(*) from public.tenants where hostel_id = p_hostel
                         and status = 'pending_approval' and is_existing),
    'leaving', (select count(*) from public.tenants where hostel_id = p_hostel and status = 'notice'),
    'tenants', (select count(*) from public.tenants where hostel_id = p_hostel and status in ('active', 'notice')),
    'unread_notifications', (select count(*) from public.notifications where hostel_id = p_hostel and read_at is null),
    -- this month's rent bills (for "collected of …" on Home)
    'billed_month', (select coalesce(sum(amount), 0) from public.bills
                     where hostel_id = p_hostel and kind = 'rent' and status <> 'cancelled'
                       and due_date between month_start and month_end),
    -- bills due today (Home: "Today's pending fee")
    'due_today_total', (select coalesce(sum(b.amount), 0) from public.bills b
                        join public.tenants t on t.id = b.tenant_id
                        where b.hostel_id = p_hostel and b.status <> 'cancelled' and b.due_date = d
                          and t.status in ('active', 'notice')),
    'due_today_paid', (select coalesce(sum(least(b.paid_amount, b.amount)), 0) from public.bills b
                       join public.tenants t on t.id = b.tenant_id
                       where b.hostel_id = p_hostel and b.status <> 'cancelled' and b.due_date = d
                         and t.status in ('active', 'notice')),
    'due_today_tenants', (select count(distinct b.tenant_id) from public.bills b
                          join public.tenants t on t.id = b.tenant_id
                          where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial') and b.due_date = d
                            and t.status in ('active', 'notice')),
    'due_today_names', (select coalesce(jsonb_agg(x.full_name), '[]'::jsonb) from (
                          select distinct t.full_name from public.bills b
                          join public.tenants t on t.id = b.tenant_id
                          where b.hostel_id = p_hostel and b.status in ('unpaid', 'partial') and b.due_date = d
                            and t.status in ('active', 'notice') and t.full_name is not null
                          order by t.full_name limit 3) x));
end;
$$;
