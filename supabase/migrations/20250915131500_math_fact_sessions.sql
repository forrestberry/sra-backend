-- math fact session helpers, RPCs, and mastery updates

create or replace function public.resolve_math_fact_unit(
  _unit_id uuid,
  _student_id uuid default null
)
returns table(fact_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _unit record;
  _type text;
  _operation text;
  _max_sum int;
  _min_product int;
  _focus_operand int;
  _lookback_days int;
  _min_misses int;
begin
  select * into _unit
  from public.math_fact_unit
  where id = _unit_id;

  if not found then
    return;
  end if;

  if not coalesce(_unit.is_dynamic, false) then
    if exists (
      select 1 from public.math_fact_unit_member where fact_unit_id = _unit_id
    ) then
      return query
        select mfum.fact_id
        from public.math_fact_unit_member mfum
        where mfum.fact_unit_id = _unit_id;
    end if;
  end if;

  _type := coalesce(_unit.rule_config->>'type', 'dynamic');

  if _type = 'recent_misses' then
    if _student_id is null then
      return;
    end if;

    _lookback_days := coalesce((_unit.rule_config->>'lookback_days')::int, 7);
    _min_misses := greatest(coalesce((_unit.rule_config->>'min_misses')::int, 2), 1);

    return query
      select ma.fact_id
      from public.math_attempt ma
      where ma.student_id = _student_id
        and ma.is_correct = false
        and ma.attempted_at >= now() - (_lookback_days::text || ' days')::interval
      group by ma.fact_id
      having count(*) >= _min_misses;

  elsif _type = 'static_filter' then
    _operation := _unit.rule_config->>'operation';
    _max_sum := (_unit.rule_config->>'max_sum')::int;
    _min_product := (_unit.rule_config->>'min_product')::int;
    _focus_operand := (_unit.rule_config->>'focus_operand')::int;

    return query
      select mf.id
      from public.math_fact mf
      where (_operation is null or mf.operation = (_operation)::public.math_fact_operation)
        and (_max_sum is null or mf.operand_a + mf.operand_b <= _max_sum)
        and (_min_product is null or mf.operand_a * mf.operand_b >= _min_product)
        and (
          _focus_operand is null
          or mf.operand_a = _focus_operand
          or mf.operand_b = _focus_operand
        );
  end if;
end;
$$;

create or replace function public.update_math_fact_mastery(
  _student_id uuid,
  _fact_id uuid,
  _is_correct boolean,
  _response_ms int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  _current public.student_math_fact_mastery%rowtype;
  _attempts int;
  _correct_total numeric;
  _new_accuracy numeric;
  _new_avg_response numeric;
  _new_streak int;
  _new_status public.math_fact_mastery_status;
begin
  select * into _current
  from public.student_math_fact_mastery
  where student_id = _student_id
    and fact_id = _fact_id
  for update;

  if not found then
    _current.attempts_count := 0;
    _current.rolling_accuracy := 0;
    _current.rolling_avg_response_ms := 0;
    _current.correct_streak := 0;
    _current.status := 'training';
  end if;

  _attempts := coalesce(_current.attempts_count, 0) + 1;
  _correct_total := coalesce(_current.rolling_accuracy, 0) * coalesce(_current.attempts_count, 0)
    + case when coalesce(_is_correct, false) then 1 else 0 end;
  _new_accuracy := _correct_total / _attempts;
  _new_avg_response := (coalesce(_current.rolling_avg_response_ms, 0) * coalesce(_current.attempts_count, 0)
    + coalesce(_response_ms, 0)) / _attempts;
  _new_streak := case when coalesce(_is_correct, false) then coalesce(_current.correct_streak, 0) + 1 else 0 end;

  if _new_accuracy >= 0.95 and _new_avg_response <= 2000 then
    _new_status := 'mastered';
  elsif _current.status = 'mastered' and (_new_accuracy < 0.95 or _new_avg_response > 2000) then
    _new_status := 'needs_review';
  else
    _new_status := 'training';
  end if;

  if found then
    update public.student_math_fact_mastery
    set attempts_count = _attempts,
        rolling_accuracy = _new_accuracy,
        rolling_avg_response_ms = round(_new_avg_response)::int,
        correct_streak = _new_streak,
        last_attempt_at = now(),
        status = _new_status,
        updated_at = now()
    where id = _current.id;
  else
    insert into public.student_math_fact_mastery (
      student_id,
      fact_id,
      rolling_accuracy,
      rolling_avg_response_ms,
      attempts_count,
      correct_streak,
      last_attempt_at,
      status
    ) values (
      _student_id,
      _fact_id,
      _new_accuracy,
      round(_new_avg_response)::int,
      _attempts,
      _new_streak,
      now(),
      _new_status
    );
  end if;
end;
$$;

create or replace function public.create_math_fact_session(
  _mode public.math_session_mode,
  _requested_duration_seconds int,
  _unit_requests jsonb,
  _config jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  _student_id uuid := auth.uid();
  _session_id uuid;
  _unit_rec record;
  _fact_rec record;
  _seq int := 0;
  _min_answers_required int;
  _unit_requests_array jsonb := coalesce(_unit_requests, '[]'::jsonb);
  _facts jsonb := '[]'::jsonb;
  _unit_count int;
  _config_payload jsonb := coalesce(_config, '{}'::jsonb);
begin
  if _student_id is null then
    raise exception 'auth required';
  end if;

  if coalesce(_requested_duration_seconds, 0) <= 0 then
    raise exception 'requested_duration_seconds must be > 0';
  end if;

  if jsonb_typeof(_unit_requests_array) <> 'array' or jsonb_array_length(_unit_requests_array) = 0 then
    raise exception 'unit_requests must be a non-empty array of {unit_id, count}';
  end if;

  _min_answers_required := greatest(1, ceil(_requested_duration_seconds::numeric / 10)::int);

  for _unit_rec in
    select unit_id, count
    from jsonb_to_recordset(_unit_requests_array) as r(unit_id uuid, count int)
  loop
    if _unit_rec.unit_id is null or coalesce(_unit_rec.count, 0) <= 0 then
      raise exception 'each unit request requires unit_id and positive count';
    end if;

    _unit_count := 0;
    for _fact_rec in
      select fact_id
      from public.resolve_math_fact_unit(_unit_rec.unit_id, _student_id)
      order by random()
      limit _unit_rec.count
    loop
      _seq := _seq + 1;
      _unit_count := _unit_count + 1;
      _facts := _facts || jsonb_build_array(jsonb_build_object(
        'sequence', _seq,
        'fact_id', _fact_rec.fact_id,
        'unit_id', _unit_rec.unit_id
      ));
    end loop;

    if _unit_count < _unit_rec.count then
      raise exception 'unit % lacks enough facts (% requested, % available)', _unit_rec.unit_id, _unit_rec.count, _unit_count;
    end if;
  end loop;

  if _seq = 0 then
    raise exception 'no facts resolved for requested units';
  end if;

  insert into public.math_session (
    student_id,
    mode,
    status,
    requested_duration_seconds,
    total_facts_requested,
    config,
    min_answers_required
  ) values (
    _student_id,
    _mode,
    'issued',
    _requested_duration_seconds,
    _seq,
    _config_payload || jsonb_build_object('unit_requests', _unit_requests_array),
    _min_answers_required
  )
  returning id into _session_id;

  insert into public.math_session_fact (session_id, fact_id, sequence, metadata)
  select _session_id,
         (fact_elem->>'fact_id')::uuid,
         (fact_elem->>'sequence')::int,
         jsonb_build_object('unit_id', fact_elem->>'unit_id')
  from jsonb_array_elements(_facts) as fact_elem;

  return (
    select jsonb_build_object(
      'session_id', _session_id,
      'mode', _mode,
      'requested_duration_seconds', _requested_duration_seconds,
      'min_answers_required', _min_answers_required,
      'facts', jsonb_agg(
        jsonb_build_object(
          'sequence', msf.sequence,
          'fact_id', msf.fact_id,
          'unit_id', (msf.metadata->>'unit_id')::uuid,
          'operand_a', mf.operand_a,
          'operand_b', mf.operand_b,
          'operation', mf.operation,
          'result_value', mf.result_value
        )
        order by msf.sequence
      )
    )
    from public.math_session_fact msf
    join public.math_fact mf on mf.id = msf.fact_id
    where msf.session_id = _session_id
  );
end;
$$;

create or replace function public.submit_math_fact_session_results(
  _session_id uuid,
  _attempts jsonb,
  _elapsed_ms int,
  _ended_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  _student_id uuid := auth.uid();
  _session public.math_session%rowtype;
  _attempt_rec record;
  _attempts_array jsonb := coalesce(_attempts, '[]'::jsonb);
  _answers int := 0;
  _counted boolean := false;
  _status public.math_session_status := 'submitted';
  _wasted_ms int := 0;
  _discarded_reason text := null;
  _elapsed_ms_sanitized int := greatest(0, coalesce(_elapsed_ms, 0));
  _fact_exists boolean;
  _result jsonb;
begin
  if _student_id is null then
    raise exception 'auth required';
  end if;

  select * into _session
  from public.math_session
  where id = _session_id;

  if not found or _session.student_id <> _student_id then
    raise exception 'session not found';
  end if;

  if _session.status <> 'issued' then
    raise exception 'session already submitted';
  end if;

  if jsonb_typeof(_attempts_array) <> 'array' then
    raise exception 'attempts must be an array payload';
  end if;

  for _attempt_rec in
    select sequence,
           fact_id,
           response_text,
           coalesce(is_correct, false) as is_correct,
           coalesce(response_ms, 0) as response_ms,
           coalesce(hint_used, false) as hint_used,
           coalesce(flashed_answer, false) as flashed_answer,
           coalesce(attempted_at, _ended_at) as attempted_at
    from jsonb_to_recordset(_attempts_array) as r(
      sequence int,
      fact_id uuid,
      response_text text,
      is_correct boolean,
      response_ms int,
      hint_used boolean,
      flashed_answer boolean,
      attempted_at timestamptz
    )
  loop
    select exists(
      select 1
      from public.math_session_fact
      where session_id = _session_id
        and sequence = coalesce(_attempt_rec.sequence, -1)
        and fact_id = _attempt_rec.fact_id
    ) into _fact_exists;

    if not coalesce(_fact_exists, false) then
      raise exception 'attempt references fact not in session (seq %, fact %)', _attempt_rec.sequence, _attempt_rec.fact_id;
    end if;

    insert into public.math_attempt (
      session_id,
      student_id,
      fact_id,
      session_fact_sequence,
      response_text,
      is_correct,
      response_ms,
      hint_used,
      flashed_answer,
      attempted_at
    ) values (
      _session_id,
      _student_id,
      _attempt_rec.fact_id,
      _attempt_rec.sequence,
      coalesce(_attempt_rec.response_text, ''),
      _attempt_rec.is_correct,
      _attempt_rec.response_ms,
      _attempt_rec.hint_used,
      _attempt_rec.flashed_answer,
      _attempt_rec.attempted_at
    )
    on conflict (session_id, session_fact_sequence) do update
      set response_text = excluded.response_text,
          is_correct = excluded.is_correct,
          response_ms = excluded.response_ms,
          hint_used = excluded.hint_used,
          flashed_answer = excluded.flashed_answer,
          attempted_at = excluded.attempted_at,
          updated_at = now();

    perform public.update_math_fact_mastery(
      _student_id,
      _attempt_rec.fact_id,
      _attempt_rec.is_correct,
      _attempt_rec.response_ms
    );

    _answers := _answers + 1;
  end loop;

  if _answers >= _session.min_answers_required then
    _counted := true;
    _status := 'submitted';
    _wasted_ms := 0;
  else
    _counted := false;
    _status := 'discarded';
    _discarded_reason := 'min_answers_not_met';
    _wasted_ms := greatest(_elapsed_ms_sanitized, _session.requested_duration_seconds * 1000);
  end if;

  update public.math_session
  set status = _status,
      submitted_at = _ended_at,
      answers_submitted = _answers,
      elapsed_ms = _elapsed_ms_sanitized,
      wasted_ms = _wasted_ms,
      counted = _counted,
      discarded_reason = _discarded_reason,
      updated_at = now()
  where id = _session_id;

  _result := jsonb_build_object(
    'session_id', _session_id,
    'answers_submitted', _answers,
    'min_answers_required', _session.min_answers_required,
    'counted', _counted,
    'status', _status,
    'wasted_ms', _wasted_ms
  );

  return _result;
end;
$$;
