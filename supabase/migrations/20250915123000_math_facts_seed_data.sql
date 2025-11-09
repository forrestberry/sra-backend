-- seed math facts up to 15 for all basic operations

do $$
declare
  var_operand_a int;
  var_operand_b int;
  var_result_value int;
  var_diff_value int;
  var_subtrahend int;
  var_minuend int;
  var_quotient int;
  var_dividend int;
  var_divisor int;
  seed_meta jsonb := jsonb_build_object('seed', 'facts_up_to_15_v1');
begin
  -- addition facts (0..15 operands)
  for var_operand_a in 0..15 loop
    for var_operand_b in 0..15 loop
      var_result_value := var_operand_a + var_operand_b;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('addition', var_operand_a, var_operand_b, var_result_value, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;

  -- subtraction facts (results 0..15, subtrahend 0..15)
  for var_diff_value in 0..15 loop
    for var_subtrahend in 0..15 loop
      var_minuend := var_diff_value + var_subtrahend;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('subtraction', var_minuend, var_subtrahend, var_diff_value, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;

  -- multiplication facts (0..15 operands)
  for var_operand_a in 0..15 loop
    for var_operand_b in 0..15 loop
      var_result_value := var_operand_a * var_operand_b;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('multiplication', var_operand_a, var_operand_b, var_result_value, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;

  -- division facts (quotient 0..15, divisor 1..15)
  for var_quotient in 0..15 loop
    for var_divisor in 1..15 loop
      var_dividend := var_quotient * var_divisor;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('division', var_dividend, var_divisor, var_quotient, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;
end $$;
