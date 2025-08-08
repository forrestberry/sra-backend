-- Cleanup deprecated tables after migrating to attempts/responses model

do $$ begin
  if to_regclass('public.answers') is not null then
    execute 'drop table public.answers cascade';
  end if;
  if to_regclass('public.unit_grades') is not null then
    execute 'drop table public.unit_grades cascade';
  end if;
end $$;

-- Optional: drop legacy column if present and migrated
-- Uncomment after verifying no code depends on it
-- alter table public.questions drop column if exists correct_answer;

