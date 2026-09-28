-- Quick-log learns which category a merchant belongs to. Every choice bumps a counter, so
-- concurrent choices from several devices can't lose each other (a read-then-write would).
-- security invoker: the caller's row-level security applies, so only household members count.
create function public.record_merchant_category(
    p_household_id uuid,
    p_merchant_key text,
    p_category_id uuid
) returns void
language sql
security invoker
set search_path = ''
as $$
    insert into public.merchant_category_map (household_id, merchant_key, category_id)
    values (p_household_id, p_merchant_key, p_category_id)
    on conflict (household_id, merchant_key, category_id)
    do update set times_used = public.merchant_category_map.times_used + 1, updated_at = now();
$$;

revoke execute on function public.record_merchant_category(uuid, text, uuid) from public, anon;
grant execute on function public.record_merchant_category(uuid, text, uuid) to authenticated;

-- The app loads the household's whole map on sync.
create index merchant_category_map_household_idx on public.merchant_category_map (household_id, updated_at desc);
