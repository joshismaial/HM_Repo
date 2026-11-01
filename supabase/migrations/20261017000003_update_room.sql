-- Hostel settings → "Change room details": the owner types a room number and changes its
-- number, sharing and rent. Beds follow the sharing (empty beds are added or removed; it can't go
-- below the people staying). New rent is for new students; people staying keep their rent.
create or replace function public.update_room(p_room uuid, p_room_no text, p_sharing int, p_rent int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.rooms;
  no text := trim(coalesce(p_room_no, ''));
begin
  select * into r from public.rooms where id = p_room;
  perform private.assert_owner(r.hostel_id);
  if length(no) not between 1 and 20 then raise exception 'BAD_ROOM_NO'; end if;
  if no ~* '^g' then no := 'G' || substr(no, 2); end if;
  if lower(no) <> lower(r.room_no) then
    -- ground floor rooms are G + a number; rooms on other floors can't start with G
    if r.floor = 0 and no !~ '^G[0-9]{1,4}$' then raise exception 'BAD_GROUND_ROOM'; end if;
    if r.floor > 0 and no ~ '^G' then raise exception 'BAD_GROUND_ROOM'; end if;
    if exists (select 1 from public.rooms where hostel_id = r.hostel_id and lower(room_no) = lower(no) and id <> r.id) then
      raise exception 'ROOM_EXISTS';
    end if;
    update public.rooms set room_no = no where id = p_room;
  end if;
  -- sharing (beds) and rent; the room counts as checked by the owner from now on
  perform private.confirm_room(p_room, r.floor, p_sharing, p_rent, r.deposit_month);
end;
$$;

revoke execute on function public.update_room(uuid, text, int, int) from public, anon;
grant execute on function public.update_room(uuid, text, int, int) to authenticated;
