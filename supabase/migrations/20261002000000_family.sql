-- Stage 7: shared households (joining by invite, leaving, removing a member) and partner
-- notifications.
--
-- One household per user: joining a household moves the user's own transactions and recurring
-- rules into it (categories are matched by name, missing ones are copied) and leaves the old one
-- (deleted by handle_member_removed when it's left empty). Leaving, or being removed, does the
-- reverse into a new personal household with a copy of the categories.

-- ---------------------------------------------------------------------------
-- Notification preferences and once-only partner notifications
-- ---------------------------------------------------------------------------

alter table public.profiles
    add column notify_partner_activity boolean not null default true,
    add column notify_budget boolean not null default true,
    add column notify_monthly_recap boolean not null default true,
    add column notify_pending_capture boolean not null default true,
    add column notify_tips boolean not null default false;

-- Set by the notify-partners function (service role) the first time it notifies about a row.
alter table public.transactions add column partners_notified_at timestamptz;

-- ---------------------------------------------------------------------------
-- Moving a member's own data between households (internal, not callable by users)
-- ---------------------------------------------------------------------------

-- Moves p_user's transactions and recurring rules from p_from to p_to. Their categories are
-- matched in p_to by name and kind; missing ones are copied over. With p_copy_all every category
-- of p_from is copied (a new personal household starts with the shared household's categories).
create function public._move_member_data(p_user uuid, p_from uuid, p_to uuid, p_copy_all boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.categories (household_id, name, emoji, color, kind, sort_order, is_archived,
                                   trip_currency, trip_starts_on, trip_ends_on)
    select p_to, c.name, c.emoji, c.color, c.kind, c.sort_order, c.is_archived,
           c.trip_currency, c.trip_starts_on, c.trip_ends_on
    from public.categories c
    where c.household_id = p_from
      and (
          p_copy_all
          or c.id in (select category_id from public.transactions where user_id = p_user and household_id = p_from)
          or c.id in (select category_id from public.recurring_rules where user_id = p_user and household_id = p_from)
      )
      and not exists (
          select 1 from public.categories t
          where t.household_id = p_to and lower(t.name) = lower(c.name) and t.kind = c.kind
      );

    update public.transactions tx
    set household_id = p_to,
        category_id = (
            select t.id from public.categories c
            join public.categories t on t.household_id = p_to and lower(t.name) = lower(c.name) and t.kind = c.kind
            where c.id = tx.category_id
            order by t.is_archived, t.sort_order
            limit 1
        )
    where tx.user_id = p_user and tx.household_id = p_from;

    update public.recurring_rules r
    set household_id = p_to,
        category_id = (
            select t.id from public.categories c
            join public.categories t on t.household_id = p_to and lower(t.name) = lower(c.name) and t.kind = c.kind
            where c.id = r.category_id
            order by t.is_archived, t.sort_order
            limit 1
        )
    where r.user_id = p_user and r.household_id = p_from;
end;
$$;

-- Takes p_user out of p_household into a new personal household, with their own data.
create function public._split_member(p_user uuid, p_household uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    new_household uuid;
    display_name text;
begin
    select full_name into display_name from public.profiles where id = p_user;

    insert into public.households (name, created_by)
    values (coalesce(display_name, ''), p_user)
    returning id into new_household;

    insert into public.household_members (household_id, user_id, role)
    values (new_household, p_user, 'owner');

    perform public._move_member_data(p_user, p_household, new_household, true);

    update public.profiles set active_household_id = new_household where id = p_user;
    delete from public.household_members where household_id = p_household and user_id = p_user;

    -- Nobody left to share with: the remaining household is personal again.
    update public.households h
    set is_shared = (select count(*) > 1 from public.household_members m where m.household_id = h.id)
    where h.id = p_household;

    return new_household;
end;
$$;

revoke execute on function public._move_member_data(uuid, uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public._split_member(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Invites
-- ---------------------------------------------------------------------------

-- Joins the household of a pending invite addressed to the caller's email. Returns its id.
create function public.accept_household_invite(p_invite uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    caller_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
    target uuid;
    previous uuid;
begin
    if caller is null then
        raise exception 'not_authenticated' using errcode = '42501';
    end if;

    select household_id into target
    from public.household_invites
    where id = p_invite and status = 'pending' and email = caller_email
    for update;
    if target is null then
        raise exception 'invite_not_found' using errcode = 'P0002';
    end if;

    select active_household_id into previous from public.profiles where id = caller;

    if not exists (select 1 from public.household_members where household_id = target and user_id = caller) then
        insert into public.household_members (household_id, user_id, role)
        values (target, caller, 'member');
    end if;

    if previous is not null and previous <> target then
        perform public._move_member_data(caller, previous, target, false);
    end if;

    update public.household_invites set status = 'accepted', responded_at = now() where id = p_invite;
    update public.profiles set active_household_id = target where id = caller;
    update public.households set is_shared = true where id = target;

    -- One household per user: leave the old one (deleted with what's left if now empty).
    if previous is not null and previous <> target then
        delete from public.household_members where household_id = previous and user_id = caller;
    end if;

    return target;
end;
$$;

create function public.decline_household_invite(p_invite uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.household_invites
    set status = 'declined', responded_at = now()
    where id = p_invite
      and status = 'pending'
      and email = lower(coalesce(auth.jwt() ->> 'email', ''));
    if not found then
        raise exception 'invite_not_found' using errcode = 'P0002';
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaving and removing
-- ---------------------------------------------------------------------------

-- Leaves the caller's shared household for a new personal one. Returns the new household id.
create function public.leave_household()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    current_household uuid;
begin
    select active_household_id into current_household from public.profiles where id = caller;
    if current_household is null
       or (select count(*) from public.household_members where household_id = current_household) < 2 then
        raise exception 'not_shared' using errcode = 'P0001';
    end if;
    return public._split_member(caller, current_household);
end;
$$;

-- The owner removes a member, who moves to a personal household with their own data.
create function public.remove_household_member(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_household uuid;
begin
    select active_household_id into current_household from public.profiles where id = auth.uid();
    if current_household is null or not public.is_household_owner(current_household) then
        raise exception 'not_owner' using errcode = '42501';
    end if;
    if p_user = auth.uid()
       or not exists (select 1 from public.household_members where household_id = current_household and user_id = p_user) then
        raise exception 'not_a_member' using errcode = 'P0002';
    end if;
    perform public._split_member(p_user, current_household);
end;
$$;

revoke execute on function public.accept_household_invite(uuid) from public, anon;
revoke execute on function public.decline_household_invite(uuid) from public, anon;
revoke execute on function public.leave_household() from public, anon;
revoke execute on function public.remove_household_member(uuid) from public, anon;
grant execute on function public.accept_household_invite(uuid) to authenticated;
grant execute on function public.decline_household_invite(uuid) to authenticated;
grant execute on function public.leave_household() to authenticated;
grant execute on function public.remove_household_member(uuid) to authenticated;

-- Pending invites to my email, with who invited me (the inviter's profile isn't otherwise
-- readable before joining).
create function public.my_pending_invites()
returns table (id uuid, household_id uuid, inviter_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
    select i.id, i.household_id, coalesce(p.full_name, ''), i.created_at
    from public.household_invites i
    left join public.profiles p on p.id = i.invited_by
    where i.status = 'pending' and i.email = lower(coalesce(auth.jwt() ->> 'email', ''))
    order by i.created_at desc
$$;

revoke execute on function public.my_pending_invites() from public, anon;
grant execute on function public.my_pending_invites() to authenticated;
