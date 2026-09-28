-- SnaPay initial schema.
--
-- Data is owned by a household. Every user gets a personal household on sign-up; a shared
-- household (couple / family) is the same thing with more than one member. Members see all of
-- the household's data; each member creates, edits and deletes only their own transactions.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type public.entry_kind as enum ('expense', 'income');
create type public.transaction_source as enum ('manual', 'apple_pay', 'import', 'receipt', 'recurring', 'open_banking');
create type public.household_role as enum ('owner', 'member');
create type public.invite_status as enum ('pending', 'accepted', 'declined', 'revoked');
create type public.recurrence_frequency as enum ('weekly', 'monthly', 'yearly', 'every_days', 'every_months');

create domain public.currency_code as char(3) check (value ~ '^[A-Z]{3}$');
create domain public.money_amount as numeric(14, 2);

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.households (
    id uuid primary key default gen_random_uuid(),
    name text not null default '',
    is_shared boolean not null default false,
    created_by uuid references auth.users (id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    full_name text not null default '' check (char_length(full_name) <= 80),
    main_currency public.currency_code not null default 'ILS',
    -- Day the financial month starts on (1–31; short months start on their last day).
    month_start_day smallint not null default 1 check (month_start_day between 1 and 31),
    -- Card issuer's foreign-currency conversion fee, in percent.
    card_fx_fee_percent numeric(5, 2) not null default 0 check (card_fx_fee_percent between 0 and 20),
    quick_log_enabled boolean not null default true,
    onboarding_completed boolean not null default false,
    active_household_id uuid references public.households (id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.household_members (
    household_id uuid not null references public.households (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    role public.household_role not null default 'member',
    joined_at timestamptz not null default now(),
    primary key (household_id, user_id)
);
create index household_members_user_idx on public.household_members (user_id);

create table public.household_invites (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    email text not null check (email = lower(email) and email like '%_@_%'),
    invited_by uuid references auth.users (id) on delete set null default auth.uid(),
    status public.invite_status not null default 'pending',
    created_at timestamptz not null default now(),
    responded_at timestamptz
);
create unique index household_invites_one_pending_idx
    on public.household_invites (household_id, email) where status = 'pending';
create index household_invites_email_idx on public.household_invites (email) where status = 'pending';

create table public.categories (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    name text not null check (char_length(name) between 1 and 40),
    emoji text not null check (char_length(emoji) between 1 and 16),
    color text not null default '#2FB36D' check (color ~ '^#[0-9A-Fa-f]{6}$'),
    kind public.entry_kind not null default 'expense',
    sort_order integer not null default 0,
    is_archived boolean not null default false,
    -- Travel categories: expenses default to the trip's currency while the trip is on.
    trip_currency public.currency_code,
    trip_starts_on date,
    trip_ends_on date,
    created_by uuid references auth.users (id) on delete set null default auth.uid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, household_id),
    check (trip_ends_on is null or trip_starts_on is null or trip_ends_on >= trip_starts_on)
);
create index categories_household_idx on public.categories (household_id, sort_order);

create table public.recurring_rules (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade default auth.uid(),
    category_id uuid,
    kind public.entry_kind not null default 'expense',
    amount public.money_amount not null check (amount > 0),
    currency public.currency_code not null,
    merchant text check (char_length(merchant) <= 120),
    note text check (char_length(note) <= 500),
    frequency public.recurrence_frequency not null,
    interval_count integer not null default 1 check (interval_count between 1 and 366),
    starts_on date not null,
    ends_on date check (ends_on is null or ends_on >= starts_on),
    last_generated_on date,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    foreign key (category_id, household_id)
        references public.categories (id, household_id) on delete set null (category_id)
);

create table public.transactions (
    -- Clients may supply the id so entries made offline sync idempotently.
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade default auth.uid(),
    category_id uuid,
    kind public.entry_kind not null default 'expense',
    -- What was actually paid, in the currency it was paid in.
    original_amount public.money_amount not null check (original_amount >= 0),
    original_currency public.currency_code not null,
    exchange_rate numeric(18, 8) not null default 1 check (exchange_rate > 0),
    -- Card conversion fee, in the main currency.
    fee_amount public.money_amount not null default 0 check (fee_amount >= 0),
    -- What it costs in the user's main currency, fee included.
    amount public.money_amount not null check (amount >= 0),
    currency public.currency_code not null,
    merchant text check (char_length(merchant) <= 120),
    note text check (char_length(note) <= 500),
    occurred_at timestamptz not null default now(),
    source public.transaction_source not null default 'manual',
    -- Id from the source system (Apple Pay automation, bank, open banking) for de-duplication.
    external_id text,
    recurring_rule_id uuid references public.recurring_rules (id) on delete set null,
    receipt_path text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    foreign key (category_id, household_id)
        references public.categories (id, household_id) on delete set null (category_id),
    unique (household_id, source, external_id)
);
create index transactions_household_date_idx on public.transactions (household_id, occurred_at desc);
create index transactions_user_idx on public.transactions (user_id);
create index transactions_category_idx on public.transactions (category_id);

create table public.budgets (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    category_id uuid not null,
    amount public.money_amount not null check (amount > 0),
    currency public.currency_code not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (household_id, category_id),
    foreign key (category_id, household_id)
        references public.categories (id, household_id) on delete cascade
);

create table public.goals (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    created_by uuid references auth.users (id) on delete set null default auth.uid(),
    name text not null check (char_length(name) between 1 and 60),
    emoji text not null default '🎯' check (char_length(emoji) between 1 and 16),
    target_amount public.money_amount not null check (target_amount > 0),
    currency public.currency_code not null,
    target_date date,
    monthly_auto_deposit public.money_amount check (monthly_auto_deposit > 0),
    is_archived boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (id, household_id)
);

create table public.goal_contributions (
    id uuid primary key default gen_random_uuid(),
    goal_id uuid not null,
    household_id uuid not null,
    user_id uuid not null references auth.users (id) on delete cascade default auth.uid(),
    -- Positive for a deposit, negative for a withdrawal.
    amount public.money_amount not null check (amount <> 0),
    note text check (char_length(note) <= 200),
    occurred_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    foreign key (goal_id, household_id) references public.goals (id, household_id) on delete cascade
);
create index goal_contributions_goal_idx on public.goal_contributions (goal_id);

-- Learns which category a merchant belongs to, for quick-log suggestions.
create table public.merchant_category_map (
    household_id uuid not null references public.households (id) on delete cascade,
    merchant_key text not null check (char_length(merchant_key) between 1 and 120),
    category_id uuid not null,
    times_used integer not null default 1 check (times_used > 0),
    updated_at timestamptz not null default now(),
    primary key (household_id, merchant_key, category_id),
    foreign key (category_id, household_id)
        references public.categories (id, household_id) on delete cascade
);

-- Daily reference rates, written by the update-exchange-rates function (service role).
-- rate = value of one unit of `quote` in `base` (base ILS, quote USD, rate 3.70).
create table public.exchange_rates (
    base public.currency_code not null,
    quote public.currency_code not null,
    rate numeric(18, 8) not null check (rate > 0),
    rate_date date not null,
    source text not null,
    fetched_at timestamptz not null default now(),
    primary key (base, quote, rate_date)
);

create table public.device_tokens (
    token text primary key,
    user_id uuid not null references auth.users (id) on delete cascade default auth.uid(),
    environment text not null default 'production' check (environment in ('sandbox', 'production')),
    updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

-- ---------------------------------------------------------------------------
-- Helper functions (security definer so RLS policies can use them without recursion)
-- ---------------------------------------------------------------------------

create function public.is_household_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.household_members m
        where m.household_id = target_household and m.user_id = (select auth.uid())
    );
$$;

create function public.is_household_owner(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.household_members m
        where m.household_id = target_household
          and m.user_id = (select auth.uid())
          and m.role = 'owner'
    );
$$;

create function public.shares_household_with(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.household_members mine
        join public.household_members theirs on theirs.household_id = mine.household_id
        where mine.user_id = (select auth.uid()) and theirs.user_id = other_user
    );
$$;

revoke execute on function public.is_household_member(uuid) from public, anon;
revoke execute on function public.is_household_owner(uuid) from public, anon;
revoke execute on function public.shares_household_with(uuid) from public, anon;
grant execute on function public.is_household_member(uuid) to authenticated;
grant execute on function public.is_household_owner(uuid) to authenticated;
grant execute on function public.shares_household_with(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger households_updated_at before update on public.households
    for each row execute function public.set_updated_at();
create trigger profiles_updated_at before update on public.profiles
    for each row execute function public.set_updated_at();
create trigger categories_updated_at before update on public.categories
    for each row execute function public.set_updated_at();
create trigger recurring_rules_updated_at before update on public.recurring_rules
    for each row execute function public.set_updated_at();
create trigger transactions_updated_at before update on public.transactions
    for each row execute function public.set_updated_at();
create trigger budgets_updated_at before update on public.budgets
    for each row execute function public.set_updated_at();
create trigger goals_updated_at before update on public.goals
    for each row execute function public.set_updated_at();

-- New auth user → profile + personal household (owner). Name and main currency come from the
-- sign-up metadata sent by the app: { "full_name": "...", "main_currency": "ILS" }.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    display_name text := left(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), 80);
    requested_currency text := upper(coalesce(new.raw_user_meta_data ->> 'main_currency', ''));
    new_household uuid;
begin
    if requested_currency !~ '^[A-Z]{3}$' then
        requested_currency := 'ILS';
    end if;

    insert into public.households (name, created_by)
    values (display_name, new.id)
    returning id into new_household;

    insert into public.household_members (household_id, user_id, role)
    values (new_household, new.id, 'owner');

    insert into public.profiles (id, full_name, main_currency, active_household_id)
    values (new.id, display_name, requested_currency::public.currency_code, new_household);

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- When a member leaves (or their account is deleted): an empty household is deleted with all
-- its data; a household left without an owner gets its longest-standing member as owner.
create function public.handle_member_removed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (select 1 from public.household_members where household_id = old.household_id) then
        delete from public.households where id = old.household_id;
    elsif not exists (
        select 1 from public.household_members where household_id = old.household_id and role = 'owner'
    ) then
        update public.household_members
        set role = 'owner'
        where (household_id, user_id) = (
            select household_id, user_id from public.household_members
            where household_id = old.household_id
            order by joined_at, user_id
            limit 1
        );
    end if;
    return null;
end;
$$;

create trigger on_household_member_removed
    after delete on public.household_members
    for each row execute function public.handle_member_removed();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.households enable row level security;
alter table public.profiles enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
alter table public.categories enable row level security;
alter table public.recurring_rules enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.goals enable row level security;
alter table public.goal_contributions enable row level security;
alter table public.merchant_category_map enable row level security;
alter table public.exchange_rates enable row level security;
alter table public.device_tokens enable row level security;

-- Households: members read; owners rename / toggle sharing. Created by the sign-up trigger only.
create policy "members read household" on public.households
    for select to authenticated using (public.is_household_member(id));
create policy "owners update household" on public.households
    for update to authenticated
    using (public.is_household_owner(id)) with check (public.is_household_owner(id));

-- Profiles: your own, plus the people you share a household with (read only).
create policy "read own and partners' profiles" on public.profiles
    for select to authenticated
    using (id = (select auth.uid()) or public.shares_household_with(id));
create policy "update own profile" on public.profiles
    for update to authenticated
    using (id = (select auth.uid()))
    with check (
        id = (select auth.uid())
        and (active_household_id is null or public.is_household_member(active_household_id))
    );

-- Members: see who is in your households; leave yourself, or remove someone if you own it.
-- Joining happens through invites (accept function, added with the family stage).
create policy "members read membership" on public.household_members
    for select to authenticated using (public.is_household_member(household_id));
create policy "leave or remove members" on public.household_members
    for delete to authenticated
    using (user_id = (select auth.uid()) or public.is_household_owner(household_id));

-- Invites: members invite and see their household's invites; invitees see invites to their email.
create policy "read invites" on public.household_invites
    for select to authenticated
    using (
        public.is_household_member(household_id)
        or email = lower((select auth.jwt()) ->> 'email')
    );
create policy "members invite" on public.household_invites
    for insert to authenticated
    with check (
        public.is_household_member(household_id)
        and invited_by = (select auth.uid())
        and status = 'pending'
    );
create policy "members revoke invites" on public.household_invites
    for update to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id) and status in ('pending', 'revoked'));

-- Shared household data: every member reads and edits.
create policy "members manage categories" on public.categories
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));
create policy "members manage budgets" on public.budgets
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));
create policy "members manage goals" on public.goals
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));
create policy "members manage merchant map" on public.merchant_category_map
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));

-- Personal entries in a shared household: everyone reads, only the author writes.
create policy "members read transactions" on public.transactions
    for select to authenticated using (public.is_household_member(household_id));
create policy "insert own transactions" on public.transactions
    for insert to authenticated
    with check (user_id = (select auth.uid()) and public.is_household_member(household_id));
create policy "update own transactions" on public.transactions
    for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()) and public.is_household_member(household_id));
create policy "delete own transactions" on public.transactions
    for delete to authenticated using (user_id = (select auth.uid()));

create policy "members read recurring rules" on public.recurring_rules
    for select to authenticated using (public.is_household_member(household_id));
create policy "insert own recurring rules" on public.recurring_rules
    for insert to authenticated
    with check (user_id = (select auth.uid()) and public.is_household_member(household_id));
create policy "update own recurring rules" on public.recurring_rules
    for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()) and public.is_household_member(household_id));
create policy "delete own recurring rules" on public.recurring_rules
    for delete to authenticated using (user_id = (select auth.uid()));

create policy "members read goal contributions" on public.goal_contributions
    for select to authenticated using (public.is_household_member(household_id));
create policy "insert own goal contributions" on public.goal_contributions
    for insert to authenticated
    with check (user_id = (select auth.uid()) and public.is_household_member(household_id));
create policy "update own goal contributions" on public.goal_contributions
    for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()) and public.is_household_member(household_id));
create policy "delete own goal contributions" on public.goal_contributions
    for delete to authenticated using (user_id = (select auth.uid()));

-- Reference data: readable by signed-in users, written only by the service role.
create policy "signed-in users read rates" on public.exchange_rates
    for select to authenticated using (true);

create policy "manage own device tokens" on public.device_tokens
    for all to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- The anonymous role never touches app data.
revoke all on all tables in schema public from anon;
