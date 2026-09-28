-- Row level security and sign-up trigger tests. Run with `supabase test db`
-- (or scripts/db-test-local.sh without Docker).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(26);

-- Users: Avi and Bella share a household; Carmel is a stranger.
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-00000000000a', 'avi@example.com', '{"full_name": "Avi Cohen", "main_currency": "ILS"}'),
    ('00000000-0000-0000-0000-00000000000b', 'bella@example.com', '{"full_name": "Bella Levi", "main_currency": "usd"}'),
    ('00000000-0000-0000-0000-00000000000c', 'carmel@example.com', '{"full_name": "Carmel", "main_currency": "not-a-currency"}');

-- Sign-up trigger ---------------------------------------------------------------

select is(
    (select full_name from profiles where id = '00000000-0000-0000-0000-00000000000a'),
    'Avi Cohen', 'profile created with the sign-up name'
);
select is(
    (select main_currency::text from profiles where id = '00000000-0000-0000-0000-00000000000b'),
    'USD', 'main currency is upper-cased'
);
select is(
    (select main_currency::text from profiles where id = '00000000-0000-0000-0000-00000000000c'),
    'ILS', 'invalid currency falls back to ILS'
);
select is(
    (select m.role::text from household_members m
     join profiles p on p.active_household_id = m.household_id and p.id = m.user_id
     where p.id = '00000000-0000-0000-0000-00000000000a'),
    'owner', 'user owns their personal household'
);

-- Fixtures (as the table owner): Bella joins Avi's household; data in both households.
create temp table ids as
select
    (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000a') as avi_household,
    (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000c') as carmel_household;
grant select on ids to authenticated;

insert into household_members (household_id, user_id, role)
select avi_household, '00000000-0000-0000-0000-00000000000b', 'member' from ids;

insert into categories (id, household_id, name, emoji, created_by)
select '10000000-0000-0000-0000-000000000001', avi_household, 'אוכל', '🍔', '00000000-0000-0000-0000-00000000000a' from ids;
insert into categories (id, household_id, name, emoji, created_by)
select '10000000-0000-0000-0000-000000000002', carmel_household, 'קניות', '🛍️', '00000000-0000-0000-0000-00000000000c' from ids;

insert into transactions (id, household_id, user_id, category_id, original_amount, original_currency, amount, currency, merchant)
select '20000000-0000-0000-0000-000000000001', avi_household, '00000000-0000-0000-0000-00000000000a',
       '10000000-0000-0000-0000-000000000001', 48.90, 'ILS', 48.90, 'ILS', 'ארומה'
from ids;

-- Bella (shared household member) ---------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "email": "bella@example.com", "role": "authenticated"}', true);

select is((select count(*)::int from transactions where id = '20000000-0000-0000-0000-000000000001'), 1,
    'partner sees the other partner''s transaction');
select is((select count(*)::int from profiles where id = '00000000-0000-0000-0000-00000000000a'), 1,
    'partner sees the other partner''s profile');
select is((select count(*)::int from categories where household_id = (select avi_household from ids)), 1,
    'partner sees shared categories');

update transactions set amount = 1 where id = '20000000-0000-0000-0000-000000000001';
delete from transactions where id = '20000000-0000-0000-0000-000000000001';
select is((select amount::numeric from transactions where id = '20000000-0000-0000-0000-000000000001'), 48.90::numeric,
    'partner cannot edit or delete the other partner''s transaction');

select throws_ok(
    $$insert into transactions (household_id, user_id, original_amount, original_currency, amount, currency)
      select avi_household, '00000000-0000-0000-0000-00000000000a', 10, 'ILS', 10, 'ILS' from ids$$,
    '42501', null, 'partner cannot log a transaction as someone else'
);
select lives_ok(
    $$insert into transactions (id, household_id, original_amount, original_currency, amount, currency, category_id)
      select '20000000-0000-0000-0000-000000000002', avi_household, 20, 'ILS', 20, 'ILS', '10000000-0000-0000-0000-000000000001' from ids$$,
    'partner logs their own transaction in the shared household (user_id defaults to them)'
);
select lives_ok(
    $$update categories set emoji = '🍕' where id = '10000000-0000-0000-0000-000000000001'$$,
    'partner can edit a shared category'
);
update profiles set full_name = 'hacked' where id = '00000000-0000-0000-0000-00000000000a';
select lives_ok(
    $$update profiles set month_start_day = 10 where id = '00000000-0000-0000-0000-00000000000b'$$,
    'user updates their own profile'
);
select throws_ok(
    $$update profiles set active_household_id = (select carmel_household from ids) where id = '00000000-0000-0000-0000-00000000000b'$$,
    '42501', null, 'user cannot point their profile at a household they are not in'
);

-- Carmel (stranger) -------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "email": "carmel@example.com", "role": "authenticated"}', true);

select is((select count(*)::int from transactions where household_id = (select avi_household from ids)), 0,
    'stranger sees no transactions of another household');
select is((select count(*)::int from profiles where id in ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b')), 0,
    'stranger sees no other profiles');
select is((select count(*)::int from households where id = (select avi_household from ids)), 0,
    'stranger does not see the household');
select throws_ok(
    $$insert into transactions (household_id, original_amount, original_currency, amount, currency)
      select avi_household, 10, 'ILS', 10, 'ILS' from ids$$,
    '42501', null, 'stranger cannot write into another household'
);
select throws_ok(
    $$insert into categories (household_id, name, emoji) select avi_household, 'x', 'x' from ids$$,
    '42501', null, 'stranger cannot add categories to another household'
);
select throws_ok(
    $$insert into exchange_rates (base, quote, rate, rate_date, source) values ('ILS', 'USD', 3.7, current_date, 'test')$$,
    '42501', null, 'users cannot write exchange rates'
);
select is((select count(*)::int from household_members), 1,
    'stranger only sees their own membership');

-- Anonymous role ----------------------------------------------------------------

reset role;
set local role anon;
select throws_ok('select count(*) from transactions', '42501', null, 'anon cannot read transactions');

-- Integrity and cleanup (as the table owner) ------------------------------------

reset role;

select is((select full_name from profiles where id = '00000000-0000-0000-0000-00000000000a'), 'Avi Cohen',
    'partner cannot edit the other partner''s profile');

select throws_ok(
    $$insert into transactions (household_id, user_id, category_id, original_amount, original_currency, amount, currency)
      select avi_household, '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000002', 5, 'ILS', 5, 'ILS' from ids$$,
    '23503', null, 'a transaction cannot use another household''s category'
);

delete from categories where id = '10000000-0000-0000-0000-000000000001';
select is((select count(*)::int from transactions where household_id = (select avi_household from ids) and category_id is null), 2,
    'deleting a category keeps its transactions, uncategorized');

delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select is(
    (select m.role::text from household_members m, ids where m.household_id = ids.avi_household
       and m.user_id = '00000000-0000-0000-0000-00000000000b'),
    'owner', 'when the owner deletes their account, the remaining partner becomes owner'
);

delete from auth.users where id = '00000000-0000-0000-0000-00000000000c';
select is((select count(*)::int from households, ids where households.id = ids.carmel_household), 0,
    'deleting the last member deletes the household and its data');

select * from finish();
rollback;
