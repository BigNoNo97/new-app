-- Merchant → category map: members of the household build it; nobody else can read or write it.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-00000000000a', 'avi@example.com', '{"full_name": "Avi"}'),
    ('00000000-0000-0000-0000-00000000000b', 'bella@example.com', '{"full_name": "Bella"}'),
    ('00000000-0000-0000-0000-00000000000c', 'carmel@example.com', '{"full_name": "Carmel"}');

create temp table ids as
select (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000a') as household,
       '50000000-0000-0000-0000-000000000001'::uuid as coffee;
grant select on ids to authenticated, anon;

insert into household_members (household_id, user_id, role)
select household, '00000000-0000-0000-0000-00000000000b', 'member' from ids;

insert into categories (id, household_id, name, emoji, color)
select coffee, household, 'קפה', '☕', '#A16207' from ids;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);

select lives_ok(
    $$select record_merchant_category(household, 'aroma', coffee) from ids$$,
    'member records a choice'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);

select lives_ok(
    $$select record_merchant_category(household, 'aroma', coffee) from ids$$,
    'partner records the same choice'
);
select is(
    (select times_used from merchant_category_map where merchant_key = 'aroma'), 2,
    'the second choice bumps the counter instead of adding a row'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "role": "authenticated"}', true);

select is((select count(*)::int from merchant_category_map), 0, 'outsider cannot read the map');
select throws_ok(
    $$select record_merchant_category(household, 'aroma', coffee) from ids$$,
    '42501', null, 'outsider cannot write to the map'
);

reset role;
set local role anon;
select throws_ok(
    $$select record_merchant_category(household, 'aroma', coffee) from ids$$,
    '42501', null, 'signed-out callers cannot run the function'
);

reset role;
select is((select times_used from merchant_category_map where merchant_key = 'aroma'), 2, 'counter unchanged by outsiders');

select * from finish();
rollback;
