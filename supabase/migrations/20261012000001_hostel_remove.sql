-- "Remove" a hostel from My hostels without losing its data.
-- The app sets archived_at (and is_open = false, so no new joins) instead of
-- deleting the row; tenants, rooms and payment history stay as they are.
alter table public.hostels add column if not exists archived_at timestamptz;

comment on column public.hostels.archived_at is
  'Set when the owner removes the hostel from My hostels. Null = shown.';
