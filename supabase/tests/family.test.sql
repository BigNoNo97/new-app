-- Shared households: joining by invite, declining, leaving and removing members.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(26);

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-00000000000a', 'avi@example.com', '{"full_name": "Avi"}'),
    ('00000000-0000-0000-0000-00000000000b', 'bella@example.com', '{"full_name": "Bella"}'),
    ('00000000-0000-0000-0000-00000000000c', 'carmel@example.com', '{"full_name": "Carmel"}'),
    ('00000000-0000-0000-0000-00000000000d', 'dana@example.com', '{"full_name": "Dana"}');

create temp table ids as
select (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000a') as avi_home,
       (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000b') as bella_home,
       (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000d') as dana_home;
grant select on ids to authenticated, anon;

-- Avi has "קפה"; Bella has "קפה" and "ספורט" and one transaction in each.
insert into categories (id, household_id, name, emoji, color)
select '60000000-0000-0000-0000-000000000001', avi_home, 'קפה', '☕', '#A0522D' from ids;
insert into categories (id, household_id, name, emoji, color)
select '60000000-0000-0000-0000-000000000002', bella_home, 'קפה', '☕', '#A0522D' from ids;
insert into categories (id, household_id, name, emoji, color)
select '60000000-0000-0000-0000-000000000003', bella_home, 'ספורט', '🏋️', '#3B82F6' from ids;
insert into transactions (id, household_id, user_id, category_id, original_amount, original_currency, amount, currency)
select '70000000-0000-0000-0000-000000000001', bella_home, '00000000-0000-0000-0000-00000000000b',
       '60000000-0000-0000-0000-000000000002', 18, 'ILS', 18, 'ILS' from ids;
insert into transactions (id, household_id, user_id, category_id, original_amount, original_currency, amount, currency)
select '70000000-0000-0000-0000-000000000002', bella_home, '00000000-0000-0000-0000-00000000000b',
       '60000000-0000-0000-0000-000000000003', 120, 'ILS', 120, 'ILS' from ids;

set local role authenticated;

-- Avi invites Bella and Dana.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "email": "avi@example.com", "role": "authenticated"}', true);
select lives_ok(
    $$insert into household_invites (id, household_id, email, invited_by)
      select '80000000-0000-0000-0000-000000000001', avi_home, 'bella@example.com', '00000000-0000-0000-0000-00000000000a' from ids$$,
    'member invites by email'
);
insert into household_invites (id, household_id, email, invited_by)
select '80000000-0000-0000-0000-000000000002', avi_home, 'dana@example.com', '00000000-0000-0000-0000-00000000000a' from ids;

-- Carmel can't use Bella's invite.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "email": "carmel@example.com", "role": "authenticated"}', true);
select throws_ok(
    $$select accept_household_invite('80000000-0000-0000-0000-000000000001')$$,
    'P0002', 'invite_not_found', 'an invite only works for its email'
);
select is((select count(*)::int from my_pending_invites()), 0, 'Carmel has no invites');

-- Bella sees and accepts.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "email": "bella@example.com", "role": "authenticated"}', true);
select is((select inviter_name from my_pending_invites()), 'Avi', 'invitee sees who invited them');
select is(
    (select accept_household_invite('80000000-0000-0000-0000-000000000001')),
    (select avi_home from ids),
    'accepting returns the joined household'
);
select is(
    (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000b'),
    (select avi_home from ids),
    'the joined household becomes active'
);
select is((select count(*)::int from transactions where user_id = '00000000-0000-0000-0000-00000000000b'), 2,
    'Bella sees her own transactions');
select is(
    (select category_id from transactions where id = '70000000-0000-0000-0000-000000000001'),
    '60000000-0000-0000-0000-000000000001'::uuid,
    'a category with the same name is reused'
);
select is(
    (select c.name from transactions t join categories c on c.id = t.category_id where t.id = '70000000-0000-0000-0000-000000000002'),
    'ספורט',
    'a missing category is copied'
);
select is((select count(*)::int from transactions), 2, 'Bella sees the shared household (no other data yet)');

reset role;
select is((select count(*)::int from households where id = (select bella_home from ids)), 0,
    'the old, now empty, household is deleted');
select is((select is_shared from households where id = (select avi_home from ids)), true, 'the household is marked shared');
select is((select status::text from household_invites where id = '80000000-0000-0000-0000-000000000001'), 'accepted',
    'the invite is marked accepted');
select is((select role::text from household_members where user_id = '00000000-0000-0000-0000-00000000000b'), 'member',
    'the invitee joins as a member');
set local role authenticated;

-- Accepting twice fails.
select throws_ok(
    $$select accept_household_invite('80000000-0000-0000-0000-000000000001')$$,
    'P0002', 'invite_not_found', 'an invite can be used once'
);

-- Bella (a member) can't remove Avi.
select throws_ok(
    $$select remove_household_member('00000000-0000-0000-0000-00000000000a')$$,
    '42501', 'not_owner', 'only the owner removes members'
);

-- Internal helpers are not callable.
select throws_ok(
    $$select _split_member('00000000-0000-0000-0000-00000000000a', (select avi_home from ids))$$,
    '42501', null, 'internal functions are not exposed'
);

-- Dana declines.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000d", "email": "dana@example.com", "role": "authenticated"}', true);
select lives_ok($$select decline_household_invite('80000000-0000-0000-0000-000000000002')$$, 'invitee declines');
select is(
    (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000d'),
    (select dana_home from ids),
    'declining keeps the own household'
);

-- Bella leaves with her data.
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "email": "bella@example.com", "role": "authenticated"}', true);
select lives_ok($$select leave_household()$$, 'member leaves');
select isnt(
    (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000b'),
    (select avi_home from ids),
    'leaving moves to a new household'
);
select is((select count(*)::int from transactions), 2, 'the leaver keeps their transactions');
select is((select count(*)::int from categories where name = 'קפה'), 1, 'the new household gets the categories');

reset role;
select is((select is_shared from households where id = (select avi_home from ids)), false,
    'the household left behind is personal again');

-- Carmel joins, then Avi (owner) removes her.
insert into household_invites (id, household_id, email, invited_by)
select '80000000-0000-0000-0000-000000000003', avi_home, 'carmel@example.com', '00000000-0000-0000-0000-00000000000a' from ids;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "email": "carmel@example.com", "role": "authenticated"}', true);
select accept_household_invite('80000000-0000-0000-0000-000000000003');
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "email": "avi@example.com", "role": "authenticated"}', true);
select lives_ok($$select remove_household_member('00000000-0000-0000-0000-00000000000c')$$, 'owner removes a member');
reset role;
select isnt(
    (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000c'),
    (select avi_home from ids),
    'the removed member gets their own household'
);

select * from finish();
rollback;
