-- Add room screen: per-day rent and day-wise deposit for each room (day-wise stays).
alter table public.rooms add column if not exists rent_day int
  check (rent_day is null or (rent_day > 0 and rent_day <= 50000));
alter table public.rooms add column if not exists deposit_day int
  check (deposit_day is null or (deposit_day >= 0 and deposit_day <= 1000000));

-- the owner saves them right after add_room (and can change them later)
grant update (rent_day, deposit_day) on public.rooms to authenticated;
