-- seed math facts up to 15 for all basic operations

do $$
declare
  operand_a int;
  operand_b int;
  result_value int;
  diff_value int;
  subtrahend int;
  minuend int;
  quotient int;
  dividend int;
  divisor int;
  seed_meta jsonb := jsonb_build_object('seed', 'facts_up_to_15_v1');
begin
  -- addition facts (0..15 operands)
  for operand_a in 0..15 loop
    for operand_b in 0..15 loop
      result_value := operand_a + operand_b;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('addition', operand_a, operand_b, result_value, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;

  -- subtraction facts (results 0..15, subtrahend 0..15)
  for diff_value in 0..15 loop
    for subtrahend in 0..15 loop
      minuend := diff_value + subtrahend;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('subtraction', minuend, subtrahend, diff_value, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;

  -- multiplication facts (0..15 operands)
  for operand_a in 0..15 loop
    for operand_b in 0..15 loop
      result_value := operand_a * operand_b;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('multiplication', operand_a, operand_b, result_value, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;

  -- division facts (quotient 0..15, divisor 1..15)
  for quotient in 0..15 loop
    for divisor in 1..15 loop
      dividend := quotient * divisor;
      insert into public.math_fact (operation, operand_a, operand_b, result_value, metadata)
      values ('division', dividend, divisor, quotient, seed_meta)
      on conflict (operation, operand_a, operand_b) do update
        set result_value = excluded.result_value,
            metadata = coalesce(math_fact.metadata, '{}'::jsonb) || seed_meta,
            updated_at = now();
    end loop;
  end loop;
end $$;
