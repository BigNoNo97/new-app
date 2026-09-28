-- Recurring rules: visible to the household, written only by their owner; generated
-- occurrences can't be duplicated.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-00000000000a', 'avi@example.com', '{"full_name": "Avi"}'),
    ('00000000-0000-0000-0000-00000000000b', 'bella@example.com', '{"full_name": "Bella"}');

create temp table ids as
select (select active_household_id from profiles where id = '00000000-0000-0000-0000-00000000000a') as household;
grant select on ids to authenticated;

insert into household_members (household_id, user_id, role)
select household, '00000000-0000-0000-0000-00000000000b', 'member' from ids;

insert into recurring_rules (id, household_id, user_id, amount, currency, frequency, starts_on)
select '40000000-0000-0000-0000-000000000001', household, '00000000-0000-0000-0000-00000000000a', 50, 'ILS', 'monthly', '2026-01-15'
from ids;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);

select is((select count(*)::int from recurring_rules), 1, 'partner sees the household''s recurring rules');
update recurring_rules set amount = 1 where id = '40000000-0000-0000-0000-000000000001';
select throws_ok(
    $$insert into recurring_rules (household_id, user_id, amount, currency, frequency, starts_on)
      select household, '00000000-0000-0000-0000-00000000000a', 10, 'ILS', 'weekly', '2026-01-01' from ids$$,
    '42501', null, 'partner cannot create a rule for someone else'
);
select lives_ok(
    $$insert into recurring_rules (household_id, amount, currency, frequency, starts_on)
      select household, 10, 'ILS', 'weekly', '2026-01-01' from ids$$,
    'partner creates their own rule'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);

select lives_ok(
    $$insert into transactions (household_id, original_amount, original_currency, amount, currency, source, external_id, recurring_rule_id)
      select household, 50, 'ILS', 50, 'ILS', 'recurring', 'rule-40000000-0000-0000-0000-000000000001-2026-09-15', '40000000-0000-0000-0000-000000000001' from ids$$,
    'owner generates an occurrence'
);
select throws_ok(
    $$insert into transactions (household_id, original_amount, original_currency, amount, currency, source, external_id, recurring_rule_id)
      select household, 50, 'ILS', 50, 'ILS', 'recurring', 'rule-40000000-0000-0000-0000-000000000001-2026-09-15', '40000000-0000-0000-0000-000000000001' from ids$$,
    '23505', null, 'the same occurrence cannot be created twice'
);
select lives_ok(
    $$update recurring_rules set last_generated_on = '2026-09-15' where id = '40000000-0000-0000-0000-000000000001'$$,
    'owner records the last generated day'
);

reset role;
select is((select amount::numeric from recurring_rules where id = '40000000-0000-0000-0000-000000000001'), 50::numeric,
    'partner could not change the owner''s rule');

select * from finish();
rollback;
