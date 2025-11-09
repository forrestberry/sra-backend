-- math fact reporting RPCs

create or replace function public.get_student_math_fact_mastery(
  _student_id uuid default null,
  _unit_id uuid default null,
  _limit int default 100,
  _offset int default 0
)
returns table(
  fact_id uuid,
  operation public.math_fact_operation,
  operand_a smallint,
  operand_b smallint,
  result_value smallint,
  status public.math_fact_mastery_status,
  rolling_accuracy numeric(5,4),
  rolling_avg_response_ms int,
  attempts_count int,
  correct_streak int,
  last_attempt_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _auth uuid := auth.uid();
  _role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
begin
  if _auth is null then
    raise exception 'auth required';
  end if;

  if _student_id is null then
    _student_id := _auth;
  end if;

  if _student_id <> _auth then
    if _role <> 'admin' and not exists (
      select 1
      from public.parent_student_link l
      where l.parent_id = _auth
        and l.student_id = _student_id
    ) then
      raise exception 'not authorized';
    end if;
  end if;

  return query
    select sm.fact_id,
           mf.operation,
           mf.operand_a,
           mf.operand_b,
           mf.result_value,
           sm.status,
           sm.rolling_accuracy,
           sm.rolling_avg_response_ms,
           sm.attempts_count,
           sm.correct_streak,
           sm.last_attempt_at
    from public.student_math_fact_mastery sm
    join public.math_fact mf on mf.id = sm.fact_id
    where sm.student_id = _student_id
      and (
        _unit_id is null
        or exists (
          select 1
          from public.math_fact_unit_member mfum
          where mfum.fact_unit_id = _unit_id
            and mfum.fact_id = sm.fact_id
        )
      )
    order by sm.status desc, sm.last_attempt_at desc nulls last
    limit greatest(_limit, 0)
    offset greatest(_offset, 0);
end;
$$;

create or replace function public.get_student_math_fact_recent_misses(
  _student_id uuid default null,
  _lookback_days int default 7,
  _min_misses int default 2
)
returns table(
  fact_id uuid,
  operation public.math_fact_operation,
  operand_a smallint,
  operand_b smallint,
  result_value smallint,
  miss_count bigint,
  last_missed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _auth uuid := auth.uid();
  _role text := coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '');
  _student uuid;
begin
  if _auth is null then
    raise exception 'auth required';
  end if;

  _student := coalesce(_student_id, _auth);

  if _student <> _auth then
    if _role <> 'admin' and not exists (
      select 1
      from public.parent_student_link l
      where l.parent_id = _auth
        and l.student_id = _student
    ) then
      raise exception 'not authorized';
    end if;
  end if;

  return query
    select ma.fact_id,
           mf.operation,
           mf.operand_a,
           mf.operand_b,
           mf.result_value,
           count(*) as miss_count,
           max(ma.attempted_at) as last_missed_at
    from public.math_attempt ma
    join public.math_fact mf on mf.id = ma.fact_id
    where ma.student_id = _student
      and ma.is_correct = false
      and ma.attempted_at >= now() - make_interval(days => greatest(_lookback_days, 1))
    group by ma.fact_id, mf.operation, mf.operand_a, mf.operand_b, mf.result_value
    having count(*) >= greatest(_min_misses, 1)
    order by last_missed_at desc;
end;
$$;
