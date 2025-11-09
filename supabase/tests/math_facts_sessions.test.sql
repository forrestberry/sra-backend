BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(11);

-- Seed dedicated parent + student for math facts tests
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '11111111-2222-4333-8444-555555555555',
  'math-parent@test.local',
  jsonb_build_object('role','parent','display_name','math-parent')
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
  'math-student@test.local',
  jsonb_build_object('role','student','username','math-student','parent_id','11111111-2222-4333-8444-555555555555')
)
ON CONFLICT (id) DO NOTHING;

-- Operate as the student
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{
  "sub":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "app_metadata": {"role":"student"}
}';

-- 1. Static unit resolves facts
SELECT ok(
  (
    SELECT count(*)
    FROM public.resolve_math_fact_unit(
      (SELECT id FROM public.math_fact_unit WHERE name = 'addition_sum_upto_10'),
      'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
    )
  ) > 0,
  'addition_sum_upto_10 resolves to at least one fact'
);

-- 2. Create a timed-test session (6 facts over 60s -> min_answers_required = 6) and stash the id
SELECT ok(
  set_config(
    'mathfacts.session_success',
    (
      SELECT (
        create_math_fact_session(
          'timed_test',
          60,
          jsonb_build_array(
            jsonb_build_object('unit_id', id, 'count', 6)
          )
        )->>'session_id'
      )
      FROM public.math_fact_unit
      WHERE name = 'addition_sum_upto_10'
    ),
    true
  ) IS NOT NULL,
  'create_math_fact_session returns and stores a session id'
);

-- 3. Session stored expected fact count (6)
SELECT results_eq(
  $$
    SELECT total_facts_requested::bigint
    FROM public.math_session
    WHERE id = current_setting('mathfacts.session_success')::uuid
  $$,
  ARRAY[6::bigint],
  'session persisted requested fact count'
);

-- 4. Submit enough attempts (mark first fact incorrect, rest correct)
WITH session_ref AS (
  SELECT current_setting('mathfacts.session_success')::uuid AS session_id
),
attempt_payload AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'sequence', msf.sequence,
      'fact_id', msf.fact_id,
      'response_text', mf.result_value::text,
      'is_correct', (msf.sequence <> 1),
      'response_ms', CASE WHEN msf.sequence <> 1 THEN 1500 ELSE 5200 END,
      'hint_used', false,
      'flashed_answer', (msf.sequence = 1)
    )
    ORDER BY msf.sequence
  ) AS payload
  FROM public.math_session_fact msf
  JOIN public.math_fact mf ON mf.id = msf.fact_id
  WHERE msf.session_id = (SELECT session_id FROM session_ref)
)
SELECT is(
  (
    SELECT submit_math_fact_session_results(
      (SELECT session_id FROM session_ref),
      (SELECT payload FROM attempt_payload),
      65000
    )->>'status'
  ),
  'submitted',
  'session results count when min_answers_required satisfied'
);

-- 5. Session marked counted
SELECT results_eq(
  $$
    SELECT counted::int
    FROM public.math_session
    WHERE id = current_setting('mathfacts.session_success')::uuid
  $$,
  ARRAY[1::int],
  'session counted flag stored'
);

-- 6. Attempts recorded (6 rows)
SELECT results_eq(
  $$
    SELECT count(*)
    FROM public.math_attempt
    WHERE session_id = current_setting('mathfacts.session_success')::uuid
  $$,
  ARRAY[6::bigint],
  'math_attempt rows written for successful session'
);

-- ensure at least one incorrect attempt exists for dynamic unit coverage
UPDATE public.math_attempt
SET is_correct = false
WHERE session_id = current_setting('mathfacts.session_success')::uuid
  AND session_fact_sequence = 1;

-- 7. Dynamic recent-miss unit picks up the incorrect fact (set min_misses = 1 for test)
SET LOCAL request.jwt.claims = '{
  "sub":"admin-math-facts-test",
  "app_metadata": {"role":"admin"}
}';

UPDATE public.math_fact_unit
  SET rule_config = jsonb_set(coalesce(rule_config,'{}'::jsonb), '{min_misses}', '1', true)
  WHERE name = 'recent_misses_twice_7_days';

SET LOCAL request.jwt.claims = '{
  "sub":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  "app_metadata": {"role":"student"}
}';

WITH recent AS (
  SELECT count(*) AS c
  FROM public.resolve_math_fact_unit(
    (SELECT id FROM public.math_fact_unit WHERE name = 'recent_misses_twice_7_days'),
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
  )
)
SELECT ok(
  (SELECT c FROM recent) > 0,
  'recent_misses dynamic unit returns facts after logged misses'
);

-- 8. Create second session (duration 100s -> min_answers_required=10) and store its id
SELECT ok(
  set_config(
    'mathfacts.session_fail',
    (
      SELECT (
        create_math_fact_session(
          'timed_test',
          100,
          jsonb_build_array(
            jsonb_build_object('unit_id', id, 'count', 10)
          )
        )->>'session_id'
      )
      FROM public.math_fact_unit
      WHERE name = 'addition_sum_upto_10'
    ),
    true
  ) IS NOT NULL,
  'second session id stored for failure scenario'
);

WITH session_ref AS (
  SELECT current_setting('mathfacts.session_fail')::uuid AS session_id
),
attempt_payload AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'sequence', msf.sequence,
      'fact_id', msf.fact_id,
      'response_text', mf.result_value::text,
      'is_correct', true,
      'response_ms', 1500,
      'hint_used', false,
      'flashed_answer', false
    )
    ORDER BY msf.sequence
  ) AS payload
  FROM (
    SELECT *
    FROM public.math_session_fact
    WHERE session_id = (SELECT session_id FROM session_ref)
    ORDER BY sequence
    LIMIT 2
  ) msf
  JOIN public.math_fact mf ON mf.id = msf.fact_id
)
SELECT is(
  (
    SELECT submit_math_fact_session_results(
      (SELECT session_id FROM session_ref),
      (SELECT payload FROM attempt_payload),
      20000
    )->>'status'
  ),
  'discarded',
  'session discarded when min_answers_required not met'
);

-- 9. Wasted time logged as at least scheduled duration (100s -> 100000 ms)
SELECT results_eq(
  $$
    SELECT wasted_ms::bigint
    FROM public.math_session
    WHERE id = current_setting('mathfacts.session_fail')::uuid
  $$,
  ARRAY[100000::bigint],
  'wasted_ms equals scheduled duration when insufficient answers submitted'
);

-- 10. Mastery rows created for attempted facts
SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.student_math_fact_mastery
    WHERE student_id = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
      AND fact_id IN (
        SELECT fact_id
        FROM public.math_session_fact
        WHERE session_id = current_setting('mathfacts.session_success')::uuid
        LIMIT 1
      )
  ),
  'mastery tracking rows created after submissions'
);

SELECT * FROM finish();
ROLLBACK;
