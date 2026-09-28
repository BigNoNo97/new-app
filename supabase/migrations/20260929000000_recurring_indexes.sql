-- Each device generates its own user's recurring charges on launch; look them up fast.
create index recurring_rules_user_active_idx on public.recurring_rules (user_id) where is_active;

-- Recurring transactions per rule, for "what did this charge create".
create index transactions_recurring_rule_idx on public.transactions (recurring_rule_id)
    where recurring_rule_id is not null;
