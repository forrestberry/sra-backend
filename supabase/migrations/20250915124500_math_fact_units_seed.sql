-- seed canonical math fact units and dynamic collections

do $$
declare
  addition_unit_id uuid;
  twos_over_ten_unit_id uuid;
  recent_misses_unit_id uuid;
  addition_name constant text := 'addition_sum_upto_10';
  twos_name constant text := 'multiplication_two_table_over_10';
  recent_name constant text := 'recent_misses_twice_7_days';
  addition_rule jsonb := jsonb_build_object('type', 'static_filter', 'operation', 'addition', 'max_sum', 10);
  twos_rule jsonb := jsonb_build_object('type', 'static_filter', 'operation', 'multiplication', 'focus_operand', 2, 'min_product', 11);
  recent_rule jsonb := jsonb_build_object('type', 'recent_misses', 'lookback_days', 7, 'min_misses', 2);
begin
  -- Addition sums up to 10
  insert into public.math_fact_unit (name, description, is_dynamic, rule_config)
  values (addition_name, 'Addition facts where operand_a + operand_b ≤ 10', false, addition_rule)
  on conflict (name) do update
    set description = excluded.description,
        rule_config = excluded.rule_config,
        updated_at = now()
  returning id into addition_unit_id;

  delete from public.math_fact_unit_member where fact_unit_id = addition_unit_id;

  insert into public.math_fact_unit_member (fact_unit_id, fact_id, weight)
  select addition_unit_id, id, 1
  from public.math_fact
  where operation = 'addition'
    and operand_a + operand_b <= 10
  on conflict (fact_unit_id, fact_id) do nothing;

  -- Multiplication 2× table products > 10
  insert into public.math_fact_unit (name, description, is_dynamic, rule_config)
  values (twos_name, 'Multiplication facts in the 2× table with products > 10', false, twos_rule)
  on conflict (name) do update
    set description = excluded.description,
        rule_config = excluded.rule_config,
        updated_at = now()
  returning id into twos_over_ten_unit_id;

  delete from public.math_fact_unit_member where fact_unit_id = twos_over_ten_unit_id;

  insert into public.math_fact_unit_member (fact_unit_id, fact_id, weight)
  select twos_over_ten_unit_id, id, 1
  from public.math_fact
  where operation = 'multiplication'
    and (operand_a = 2 or operand_b = 2)
    and operand_a * operand_b > 10
  on conflict (fact_unit_id, fact_id) do nothing;

  -- Dynamic unit for recent misses
  insert into public.math_fact_unit (name, description, is_dynamic, rule_config)
  values (recent_name, 'Dynamic collection: facts missed ≥2 times in the past 7 days', true, recent_rule)
  on conflict (name) do update
    set description = excluded.description,
        is_dynamic = excluded.is_dynamic,
        rule_config = excluded.rule_config,
        updated_at = now()
  returning id into recent_misses_unit_id;
end $$;
