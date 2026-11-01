-- "Move to Flutter" (22 Oct 2026): database side of everything decided 20–22 Oct in the prototype.
--  * hostel photo (private Supabase Storage, key checked in the Edge Functions)
--  * Payment options → Instant online pay switch (gateway itself comes later)
--  * small student photo thumbnails for lists
--  * Fees: "Done – I have paid" (UPI app / bank, no UTR), Pay by cash → "When will you pay?" (tell the owner),
--    part payments (any amount), owner "Not received" → red message in the student's Fees
--  * owner notices to students (+ default message in the app), local ads (added by the app admin only)
--  * Report issue (student) / Complaints (owner)
--  * student messages stay until the student taps OK
--  * vacate notice: leaving date is always the next fee date; student can cancel
--  * owner Home: open complaints and rooms with a free bed

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
alter table public.hostels add column if not exists photo_key text
  check (photo_key is null or length(photo_key) <= 200);
alter table public.hostels add column if not exists accept_online boolean not null default false;
alter table public.tenants add column if not exists photo_thumb_key text
  check (photo_thumb_key is null or length(photo_thumb_key) <= 200);
grant select (photo_thumb_key) on public.tenants to authenticated;
alter table public.payments add column if not exists cash_plan text
  check (cash_plan is null or cash_plan in ('today', 'tomorrow', 'paid'));

-- ---------------------------------------------------------------------------
-- Student messages: more kinds, and they stay until the student taps OK
-- ---------------------------------------------------------------------------
alter table public.student_messages add column if not exists acked_at timestamptz;
alter table public.student_messages drop constraint if exists student_messages_kind_check;
alter table public.student_messages add constraint student_messages_kind_check check (kind in (
  'sharing_change', 'rent_date_change', 'notice_change',
  'payment_not_received', 'cash_not_received', 'payment_received', 'issue_update'));

-- ---------------------------------------------------------------------------
-- Owner notices to students (Home → "Notice")
-- ---------------------------------------------------------------------------
create table if not exists public.owner_notices (
  id         uuid primary key default gen_random_uuid(),
  hostel_id  uuid not null references public.hostels (id) on delete cascade,
  icon       text not null default 'other' check (icon in ('water', 'power', 'cleaning', 'rent', 'food', 'other')),
  title      text not null check (length(trim(title)) between 1 and 80),
  body       text check (body is null or length(body) <= 300),
  created_at timestamptz not null default now()
);
create index if not exists owner_notices_hostel_idx on public.owner_notices (hostel_id, created_at desc);
alter table public.owner_notices enable row level security;
create policy "own notices: read" on public.owner_notices for select to authenticated
  using (private.owns_hostel(hostel_id));
revoke insert, update, delete on public.owner_notices from authenticated, anon;

create or replace function public.post_owner_notice(p_hostel uuid, p_icon text, p_title text, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare nid uuid;
begin
  perform private.assert_owner(p_hostel);
  insert into public.owner_notices (hostel_id, icon, title, body)
  values (p_hostel, coalesce(p_icon, 'other'), trim(p_title), nullif(trim(coalesce(p_body, '')), ''))
  returning id into nid;
  return nid;
end;
$$;

create or replace function public.remove_owner_notice(p_notice uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare hid uuid;
begin
  select hostel_id into hid from public.owner_notices where id = p_notice;
  if hid is null then raise exception 'NOT_FOUND'; end if;
  perform private.assert_owner(hid);
  delete from public.owner_notices where id = p_notice;
end;
$$;

-- ---------------------------------------------------------------------------
-- Local ads on the student Home – added only by the app admin (Supabase dashboard / admin panel later).
-- Never shown on payment or ID screens (the app only shows them on Home).
-- ---------------------------------------------------------------------------
create table if not exists public.student_ads (
  id           uuid primary key default gen_random_uuid(),
  shop         text not null check (length(trim(shop)) between 1 and 80),
  offer        text not null check (length(trim(offer)) between 1 and 160),
  icon         text,
  button_kind  text not null default 'call' check (button_kind in ('call', 'link')),
  button_value text check (button_value is null or length(button_value) <= 300),
  city         text,                 -- null = every city
  hostel_ids   uuid[],               -- null = every hostel (in the city)
  starts_on    date not null default current_date,
  ends_on      date,
  is_live      boolean not null default true,
  views        int not null default 0,
  clicks       int not null default 0,
  created_at   timestamptz not null default now()
);
alter table public.student_ads enable row level security; -- no policies: only the server reads it
revoke all on public.student_ads from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Report issue (student) / Complaints (owner)
-- ---------------------------------------------------------------------------
create table if not exists public.complaints (
  id              uuid primary key default gen_random_uuid(),
  hostel_id       uuid not null references public.hostels (id) on delete cascade,
  tenant_id       uuid not null references public.tenants (id) on delete cascade,
  category        text not null check (category in
                    ('water', 'electricity', 'wifi', 'cleaning', 'food', 'furniture', 'plumbing', 'security', 'other')),
  body            text not null check (length(trim(body)) between 3 and 500),
  status          text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  owner_reply     text check (owner_reply is null or length(owner_reply) <= 300),
  student_unread  boolean not null default false, -- owner changed it; number on the student's Report issue tab
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists complaints_hostel_idx on public.complaints (hostel_id, status, created_at desc);
create index if not exists complaints_tenant_idx on public.complaints (tenant_id, created_at desc);
alter table public.complaints enable row level security;
create policy "own complaints: read" on public.complaints for select to authenticated
  using (private.owns_hostel(hostel_id));
revoke insert, update, delete on public.complaints from authenticated, anon;

create or replace function public.update_complaint(p_complaint uuid, p_status text, p_reply text)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.complaints;
begin
  select * into c from public.complaints where id = p_complaint;
  if c.id is null then raise exception 'NOT_FOUND'; end if;
  perform private.assert_owner(c.hostel_id);
  if p_status is not null and p_status not in ('open', 'in_progress', 'resolved') then raise exception 'BAD_STATUS'; end if;
  update public.complaints set
    status = coalesce(p_status, status),
    owner_reply = coalesce(nullif(trim(coalesce(p_reply, '')), ''), owner_reply),
    student_unread = true,
    updated_at = now()
  where id = p_complaint;
end;
$$;

create or replace function public.student_report_issue(p_session uuid, p_category text, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  cid uuid;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status not in ('active', 'notice') then raise exception 'NOT_ACTIVE'; end if;
  if (select count(*) from public.complaints where tenant_id = t.id and created_at > now() - interval '1 day') >= 5 then
    raise exception 'TOO_MANY_ISSUES';
  end if;
  insert into public.complaints (hostel_id, tenant_id, category, body)
  values (t.hostel_id, t.id, p_category, trim(coalesce(p_body, '')))
  returning id into cid;
  perform private.notify(t.hostel_id, 'issue', 'New complaint',
    coalesce(t.full_name, 'Tenant') || ' · ' || initcap(p_category) || ': ' || left(trim(p_body), 80), cid);
  return cid;
end;
$$;

-- the student opened an issue the owner changed: the number on the tab goes down by one
create or replace function public.student_read_issue(p_session uuid, p_issue uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  tid uuid := coalesce(s.tenant_id, (private.session_tenant(s)).id);
begin
  update public.complaints set student_unread = false where id = p_issue and tenant_id = tid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Student payments: "Done – I have paid" (no UTR for now), part payments, cash plans
-- ---------------------------------------------------------------------------
-- p_utr is optional again for UPI / bank (decided 20 Oct 2026); when given it must be valid and unused.
create or replace function public.student_pay_bill(
  p_session uuid, p_method public.pay_method, p_utr text, p_amount int, p_paid_on date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  v_utr text := nullif(upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g')), '');
  pid uuid;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status not in ('active', 'notice') then raise exception 'NOT_ACTIVE'; end if;
  if p_method not in ('upi', 'bank', 'cash') then raise exception 'BAD_METHOD'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000 then raise exception 'BAD_AMOUNT'; end if;
  if v_utr is not null and v_utr !~ '^[A-Z0-9]{6,30}$' then raise exception 'UTR_REQUIRED'; end if;
  if v_utr is not null and exists (select 1 from public.payments
      where hostel_id = t.hostel_id and upper(payments.utr) = v_utr and status <> 'rejected') then
    raise exception 'DUPLICATE_UTR';
  end if;
  if (select count(*) from public.payments where tenant_id = t.id and status = 'pending') >= 3 then
    raise exception 'TOO_MANY_PENDING';
  end if;

  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, utr, payment_note, paid_on, created_by)
  values (t.hostel_id, t.id, p_method, p_amount, case when p_method = 'cash' then null else v_utr end,
          private.payment_note(t.id), coalesce(p_paid_on, private.today()), 'student')
  returning id into pid;

  perform private.notify(t.hostel_id, 'payment', 'Payment to check',
    coalesce(t.full_name, 'Tenant') || ' · ₹' || p_amount || ' · ' || upper(p_method::text) ||
    coalesce(' · UTR ' || v_utr, ' · look for the amount and note ' || private.payment_note(t.id)), pid);
  return jsonb_build_object('payment_id', pid);
end;
$$;

-- Pay by cash → "When will you pay?" Today / Tomorrow / Already paid → Tell owner.
-- One open cash plan per student: a new plan replaces the old one.
create or replace function public.student_cash_plan(p_session uuid, p_plan text, p_amount int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  h public.hostels;
  pid uuid;
  say text;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status not in ('active', 'notice') then raise exception 'NOT_ACTIVE'; end if;
  select * into h from public.hostels where id = t.hostel_id;
  if not h.accept_cash then raise exception 'BAD_METHOD'; end if;
  if p_plan not in ('today', 'tomorrow', 'paid') then raise exception 'BAD_PLAN'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000 then raise exception 'BAD_AMOUNT'; end if;
  delete from public.payments
   where tenant_id = t.id and method = 'cash' and status = 'pending' and created_by = 'student';
  insert into public.payments (hostel_id, tenant_id, method, amount_claimed, payment_note, paid_on, created_by, cash_plan)
  values (t.hostel_id, t.id, 'cash', p_amount, private.payment_note(t.id),
          private.today() + case when p_plan = 'tomorrow' then 1 else 0 end, 'student', p_plan)
  returning id into pid;
  say := case p_plan when 'paid' then 'says he paid' when 'tomorrow' then 'will pay tomorrow' else 'will pay today' end;
  perform private.notify(t.hostel_id, 'cash', 'Cash payment',
    coalesce(t.full_name, 'Tenant') || ' ' || say || ' ₹' || p_amount || ' cash', pid);
  return jsonb_build_object('payment_id', pid, 'plan', p_plan);
end;
$$;

create or replace function public.student_cancel_cash_plan(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  tid uuid := coalesce(s.tenant_id, (private.session_tenant(s)).id);
begin
  delete from public.payments
   where tenant_id = tid and method = 'cash' and status = 'pending' and created_by = 'student';
end;
$$;

-- Owner "Not received" on a student payment (UPI / bank / cash): the payment is rejected and the student
-- gets a red message in Fees that stays until he taps OK.
create or replace function private.after_payment_rejected()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'rejected' and old.status = 'pending' and new.created_by = 'student' then
    perform private.message_student(new.tenant_id,
      case when new.method = 'cash' then 'cash_not_received' else 'payment_not_received' end,
      jsonb_build_object('amount', new.amount_claimed, 'method', new.method, 'date', new.paid_on));
  end if;
  return new;
end;
$$;
drop trigger if exists payments_after_rejected on public.payments;
create trigger payments_after_rejected after update of status on public.payments
  for each row execute function private.after_payment_rejected();

create or replace function public.student_ack_message(p_session uuid, p_message uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  tid uuid := coalesce(s.tenant_id, (private.session_tenant(s)).id);
begin
  update public.student_messages set acked_at = now() where id = p_message and tenant_id = tid and acked_at is null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vacate notice: the leaving date is always the next fee date (no date picker); the student can cancel.
-- ---------------------------------------------------------------------------
create or replace function public.student_give_notice(p_session uuid, p_leaving_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  h public.hostels;
  leave_on date;
  days int;
  again boolean;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status not in ('active', 'notice') then raise exception 'NOT_ACTIVE'; end if;
  select * into h from public.hostels where id = t.hostel_id;
  leave_on := coalesce(p_leaving_date, private.next_fee_date(t.id), private.today() + h.notice_days);
  if leave_on < private.today() then raise exception 'BAD_DATE'; end if;
  again := t.status = 'notice';
  days := leave_on - private.today();
  update public.tenants set status = 'notice', notice_given_at = coalesce(case when again then notice_given_at end, now()),
    leaving_date = leave_on where id = t.id;
  perform private.notify(t.hostel_id, 'notice', case when again then 'Leaving date changed' else 'Leaving notice' end,
    coalesce(t.full_name, 'Tenant') || ' will leave on ' || to_char(leave_on, 'DD Mon') ||
    ' (' || days || ' days'' notice)', t.id);
  return jsonb_build_object('days', days, 'leaving_date', leave_on,
    'enough_notice', days >= h.notice_days, 'notice_days', h.notice_days);
end;
$$;

create or replace function public.student_cancel_notice(p_session uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
begin
  select * into t from public.tenants where id = coalesce(s.tenant_id, (private.session_tenant(s)).id);
  if t.id is null or t.status <> 'notice' then raise exception 'NOT_ACTIVE'; end if;
  update public.tenants set status = 'active', notice_given_at = null, leaving_date = null where id = t.id;
  perform private.notify(t.hostel_id, 'notice', 'Notice cancelled',
    coalesce(t.full_name, 'Tenant') || ' is staying – vacate notice cancelled', t.id);
end;
$$;

-- small photo for lists (made on the phone at upload, ~100×100)
create or replace function public.student_set_thumb(p_session uuid, p_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  tid uuid := coalesce(s.tenant_id, (private.session_tenant(s)).id);
begin
  if tid is null then raise exception 'NO_BED_HELD'; end if;
  update public.tenants set photo_thumb_key = p_key where id = tid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Everything extra the student app shows (Home, Fees, Report issue, Settings).
-- ---------------------------------------------------------------------------
create or replace function public.student_me_extra(p_session uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  s public.student_sessions := private.session_row(p_session);
  t public.tenants;
  h public.hostels;
  lf record;
begin
  if s.tenant_id is not null then select * into t from public.tenants where id = s.tenant_id;
  else t := private.session_tenant(s); end if;
  if t.id is null then raise exception 'NO_BOOKING'; end if;
  select * into h from public.hostels where id = t.hostel_id;
  select * into lf from private.late_fee(t.id, private.today());
  return jsonb_build_object('org_name', t.org_name, 'has_photo', t.photo_key is not null,
    'parent_name', t.parent_name, 'reference_name', t.reference_name,
    'room_floor', (select r.floor from public.beds b join public.rooms r on r.id = b.room_id where b.id = t.bed_id),
    'wifi', private.tenant_wifi(t.id),
    'late_fee', coalesce(lf.fee, 0), 'late_days', coalesce(lf.days, 0), 'late_fee_per_day', coalesce(lf.per_day, 0),
    'notice_days', h.notice_days,
    'next_fee_date', private.next_fee_date(t.id),
    'house_rules', h.house_rules,
    'accept_online', h.accept_online,
    'extra_charges', h.extra_charges,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'params', m.params, 'at', m.created_at)
                       order by m.created_at desc)
      from (select * from public.student_messages
            where tenant_id = t.id and acked_at is null and created_at > now() - interval '30 days'
            order by created_at desc limit 10) m), '[]'::jsonb),
    'notices', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.id, 'icon', n.icon, 'title', n.title, 'body', n.body, 'at', n.created_at)
                       order by n.created_at desc)
      from (select * from public.owner_notices where hostel_id = t.hostel_id
            and created_at > now() - interval '30 days' order by created_at desc limit 5) n), '[]'::jsonb),
    'issues', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'category', c.category, 'body', c.body, 'status', c.status,
                       'owner_reply', c.owner_reply, 'unread', c.student_unread, 'at', c.created_at)
                       order by c.created_at desc)
      from (select * from public.complaints where tenant_id = t.id order by created_at desc limit 20) c), '[]'::jsonb),
    'cash_plan', (select jsonb_build_object('id', p.id, 'plan', p.cash_plan, 'amount', p.amount_claimed, 'date', p.paid_on)
                  from public.payments p where p.tenant_id = t.id and p.method = 'cash' and p.status = 'pending'
                    and p.created_by = 'student' order by p.created_at desc limit 1),
    'ad', (select jsonb_build_object('id', a.id, 'shop', a.shop, 'offer', a.offer, 'icon', a.icon,
                    'button_kind', a.button_kind, 'button_value', a.button_value)
           from public.student_ads a
           where a.is_live and a.starts_on <= private.today() and (a.ends_on is null or a.ends_on >= private.today())
             and (a.city is null or lower(a.city) = lower(h.city))
             and (a.hostel_ids is null or h.id = any (a.hostel_ids))
           order by random() limit 1));
end;
$$;

-- hostel photo key for the Edge Function (it turns the key into a short-lived link and drops the key)
create or replace function public.student_hostel_photo_key(p_session uuid)
returns text language sql stable security definer set search_path = '' as $$
  select h.photo_key from public.hostels h where h.id = (private.session_row(p_session)).hostel_id;
$$;

-- ad shown / tapped (counts for the admin)
create or replace function public.student_ad_event(p_session uuid, p_ad uuid, p_click boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.session_row(p_session);
  update public.student_ads set views = views + case when p_click then 0 else 1 end,
                                clicks = clicks + case when p_click then 1 else 0 end
   where id = p_ad;
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner Home: open complaints, rooms with a free bed
-- ---------------------------------------------------------------------------
create or replace function public.hostel_summary_extra(p_hostel uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.assert_owner(p_hostel);
  return jsonb_build_object(
    'open_complaints', (select count(*) from public.complaints where hostel_id = p_hostel and status <> 'resolved'),
    'rooms_with_free', (select count(distinct room_id) from public.beds where hostel_id = p_hostel and status = 'vacant'),
    'cash_to_check', (select count(*) from public.payments where hostel_id = p_hostel and status = 'pending' and method = 'cash'));
end;
$$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
revoke execute on function
  public.post_owner_notice(uuid, text, text, text),
  public.remove_owner_notice(uuid),
  public.update_complaint(uuid, text, text),
  public.hostel_summary_extra(uuid),
  public.student_report_issue(uuid, text, text),
  public.student_read_issue(uuid, uuid),
  public.student_pay_bill(uuid, public.pay_method, text, int, date),
  public.student_cash_plan(uuid, text, int),
  public.student_cancel_cash_plan(uuid),
  public.student_ack_message(uuid, uuid),
  public.student_give_notice(uuid, date),
  public.student_cancel_notice(uuid),
  public.student_set_thumb(uuid, text),
  public.student_me_extra(uuid),
  public.student_hostel_photo_key(uuid),
  public.student_ad_event(uuid, uuid, boolean)
from public, anon;

grant execute on function
  public.post_owner_notice(uuid, text, text, text),
  public.remove_owner_notice(uuid),
  public.update_complaint(uuid, text, text),
  public.hostel_summary_extra(uuid)
to authenticated;

revoke execute on function
  public.student_report_issue(uuid, text, text),
  public.student_read_issue(uuid, uuid),
  public.student_pay_bill(uuid, public.pay_method, text, int, date),
  public.student_cash_plan(uuid, text, int),
  public.student_cancel_cash_plan(uuid),
  public.student_ack_message(uuid, uuid),
  public.student_give_notice(uuid, date),
  public.student_cancel_notice(uuid),
  public.student_set_thumb(uuid, text),
  public.student_me_extra(uuid),
  public.student_hostel_photo_key(uuid),
  public.student_ad_event(uuid, uuid, boolean)
from authenticated;

grant execute on function
  public.student_report_issue(uuid, text, text),
  public.student_read_issue(uuid, uuid),
  public.student_pay_bill(uuid, public.pay_method, text, int, date),
  public.student_cash_plan(uuid, text, int),
  public.student_cancel_cash_plan(uuid),
  public.student_ack_message(uuid, uuid),
  public.student_give_notice(uuid, date),
  public.student_cancel_notice(uuid),
  public.student_set_thumb(uuid, text),
  public.student_me_extra(uuid),
  public.student_hostel_photo_key(uuid),
  public.student_ad_event(uuid, uuid, boolean)
to service_role;
