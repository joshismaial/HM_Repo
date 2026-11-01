-- Staff (decided 18 Oct 2026), part 1: the owner's Staff page.
-- Each staff member has a job, duties (what they may do in the app, switched on/off by the owner),
-- duties the owner typed himself ("+ Add duty") and a daily jobs checklist.
-- Part 2 (next): staff log in with their own mobile number and the database checks their duties.
-- Owner only.

create table if not exists public.staff (
  id            uuid primary key default gen_random_uuid(),
  hostel_id     uuid not null references public.hostels (id) on delete cascade,
  name          text not null check (length(trim(name)) between 2 and 80),
  phone         text not null check (phone ~ '^\+91[6-9][0-9]{9}$'),
  job           text not null default 'other' check (job in ('manager', 'cleaning', 'security', 'cook', 'other')),
  job_other     text check (job_other is null or length(trim(job_other)) between 1 and 40),
  -- rent, approve, rooms, complaints, leaving, reminders, reports, ids, checklist
  duties        text[] not null default '{}',
  -- duties the owner typed: [{"name": "Buy vegetables", "on": true}]
  custom_duties jsonb not null default '[]',
  checklist     text check (checklist is null or length(checklist) <= 500),
  user_id       uuid references public.profiles (id) on delete set null,   -- filled when they log in (part 2)
  invited_at    timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  unique (hostel_id, phone)
);
create index if not exists staff_hostel_idx on public.staff (hostel_id);
alter table public.staff enable row level security;
create policy "own staff: read" on public.staff for select to authenticated using (private.owns_hostel(hostel_id));
revoke all on public.staff from anon;
revoke insert, update, delete on public.staff from authenticated;

create or replace function private.staff_duty_codes()
returns text[] language sql immutable set search_path = '' as $$
  select array['rent', 'approve', 'rooms', 'complaints', 'leaving', 'reminders', 'reports', 'ids', 'checklist'];
$$;

-- Duties switched on when a job is picked (the owner can change them after adding).
create or replace function public.staff_job_duties(p_job text)
returns text[] language sql immutable set search_path = '' as $$
  select case p_job
    when 'manager'  then array['rent', 'approve', 'rooms', 'complaints', 'leaving', 'checklist']
    when 'cleaning' then array['complaints', 'checklist']
    when 'security' then array['leaving', 'checklist']
    else array['checklist'] end;
$$;

create or replace function public.staff_list(p_hostel uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.assert_owner(p_hostel);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'phone', s.phone, 'job', s.job,
      'job_other', s.job_other, 'duties', to_jsonb(s.duties), 'custom_duties', s.custom_duties,
      'checklist', s.checklist, 'logged_in', s.user_id is not null) order by s.created_at)
    from public.staff s where s.hostel_id = p_hostel), '[]'::jsonb);
end;
$$;

-- Add (p_id null) or change a staff member. Returns the id.
create or replace function public.save_staff(
  p_hostel uuid, p_id uuid, p_name text, p_phone text, p_job text, p_job_other text,
  p_duties text[], p_custom jsonb, p_checklist text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  sid uuid;
  d text;
  c jsonb;
  custom jsonb := coalesce(p_custom, '[]'::jsonb);
begin
  perform private.assert_owner(p_hostel);
  if length(trim(coalesce(p_name, ''))) not between 2 and 80 then raise exception 'BAD_NAME'; end if;
  if coalesce(p_phone, '') !~ '^\+91[6-9][0-9]{9}$' then raise exception 'BAD_PHONE'; end if;
  if coalesce(p_job, '') not in ('manager', 'cleaning', 'security', 'cook', 'other') then raise exception 'BAD_JOB'; end if;
  foreach d in array coalesce(p_duties, '{}') loop
    if not d = any (private.staff_duty_codes()) then raise exception 'BAD_DUTY'; end if;
  end loop;
  if jsonb_typeof(custom) <> 'array' or jsonb_array_length(custom) > 20 then raise exception 'BAD_DUTY'; end if;
  for c in select * from jsonb_array_elements(custom) loop
    if length(trim(coalesce(c->>'name', ''))) not between 1 and 60 then raise exception 'BAD_DUTY'; end if;
  end loop;
  if exists (select 1 from public.staff where hostel_id = p_hostel and phone = p_phone and id is distinct from p_id) then
    raise exception 'STAFF_EXISTS';
  end if;
  if p_id is null then
    insert into public.staff (hostel_id, name, phone, job, job_other, duties, custom_duties, checklist)
    values (p_hostel, trim(p_name), p_phone, p_job, nullif(trim(coalesce(p_job_other, '')), ''),
            coalesce(p_duties, public.staff_job_duties(p_job)), custom, nullif(trim(coalesce(p_checklist, '')), ''))
    returning id into sid;
  else
    update public.staff set name = trim(p_name), phone = p_phone, job = p_job,
      job_other = nullif(trim(coalesce(p_job_other, '')), ''), duties = coalesce(p_duties, '{}'),
      custom_duties = custom, checklist = nullif(trim(coalesce(p_checklist, '')), '')
    where id = p_id and hostel_id = p_hostel
    returning id into sid;
    if sid is null then raise exception 'NOT_FOUND'; end if;
  end if;
  return sid;
end;
$$;

create or replace function public.remove_staff(p_staff uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  hid uuid;
begin
  select hostel_id into hid from public.staff where id = p_staff;
  perform private.assert_owner(hid);
  delete from public.staff where id = p_staff;
end;
$$;

revoke execute on function public.staff_list(uuid) from public, anon;
grant execute on function public.staff_list(uuid) to authenticated;
revoke execute on function public.save_staff(uuid, uuid, text, text, text, text, text[], jsonb, text) from public, anon;
grant execute on function public.save_staff(uuid, uuid, text, text, text, text, text[], jsonb, text) to authenticated;
revoke execute on function public.remove_staff(uuid) from public, anon;
grant execute on function public.remove_staff(uuid) to authenticated;
revoke execute on function public.staff_job_duties(text) from public, anon;
grant execute on function public.staff_job_duties(text) to authenticated;
