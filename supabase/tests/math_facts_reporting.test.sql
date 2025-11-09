BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

-- seed parent + student
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  'BBBBBBBB-1111-2222-3333-444444444444',
  'report-parent@test.local',
  jsonb_build_object('role','parent','display_name','report-parent')
) ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  'CCCCCCCC-5555-6666-7777-888888888888',
  'report-student@test.local',
  jsonb_build_object('role','student','username','report-student','parent_id','BBBBBBBB-1111-2222-3333-444444444444')
) ON CONFLICT (id) DO NOTHING;

-- act as student to create mastery + misses
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{
  "sub":"CCCCCCCC-5555-6666-7777-888888888888",
  "app_metadata":{"role":"student"}
}';

SELECT ok(
  set_config(
    'mathfacts.reporting_session',
    (
      SELECT (
        create_math_fact_session(
          'timed_test',
          45,
          jsonb_build_array(jsonb_build_object('unit_id', id, 'count', 5))
        )->>'session_id'
      )
      FROM public.math_fact_unit
      WHERE name = 'addition_sum_upto_10'
    ),
    true
  ) IS NOT NULL,
  'created math facts session for reporting tests'
);

WITH session_ref AS (
  SELECT current_setting('mathfacts.reporting_session')::uuid AS session_id
),
attempt_payload AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'sequence', msf.sequence,
      'fact_id', msf.fact_id,
      'response_text', mf.result_value::text,
      'is_correct', (msf.sequence <> 1),
      'response_ms', CASE WHEN msf.sequence <> 1 THEN 1200 ELSE 6000 END,
      'hint_used', false,
      'flashed_answer', (msf.sequence = 1)
    ) ORDER BY msf.sequence
  ) AS payload
  FROM public.math_session_fact msf
  JOIN public.math_fact mf ON mf.id = msf.fact_id
  WHERE msf.session_id = (SELECT session_id FROM session_ref)
)
SELECT ok(
  (
    SELECT submit_math_fact_session_results(
      (SELECT session_id FROM session_ref),
      (SELECT payload FROM attempt_payload),
      50000
    )->>'status'
  ) = 'submitted',
  'submitted reporting session'
);

-- 1. student sees mastery rows
SELECT ok(
  (
    SELECT count(*)
    FROM public.get_student_math_fact_mastery()
  ) > 0,
  'student retrieves mastery rows'
);

-- 2. unit filter reduces set but returns data
SELECT ok(
  (
    SELECT count(*)
    FROM public.get_student_math_fact_mastery(
      null,
      (SELECT id FROM public.math_fact_unit WHERE name = 'addition_sum_upto_10')
    )
  ) > 0,
  'unit filter returns scoped mastery rows'
);

-- 3. recent misses return at least the incorrect fact
SELECT ok(
  (
    SELECT count(*)
    FROM public.get_student_math_fact_recent_misses(null, 7, 1)
  ) > 0,
  'recent misses returns entries for student'
);

-- switch to parent claim
SET LOCAL request.jwt.claims = '{
  "sub":"BBBBBBBB-1111-2222-3333-444444444444",
  "app_metadata":{"role":"parent"}
}';

-- 4. parent can fetch child mastery
SELECT ok(
  (
    SELECT count(*)
    FROM public.get_student_math_fact_mastery('CCCCCCCC-5555-6666-7777-888888888888')
  ) > 0,
  'parent can read child mastery'
);

-- 5. parent can fetch child recent misses
SELECT ok(
  (
    SELECT count(*)
    FROM public.get_student_math_fact_recent_misses('CCCCCCCC-5555-6666-7777-888888888888', 7, 1)
  ) > 0,
  'parent can read child recent misses'
);

-- 6. unauthorized other student blocked
SET LOCAL request.jwt.claims = '{
  "sub":"EEEEEEEE-9999-aaaa-bbbb-cccccccccccc",
  "app_metadata":{"role":"student"}
}';

SELECT throws_ok(
  $$
    SELECT * FROM public.get_student_math_fact_mastery('CCCCCCCC-5555-6666-7777-888888888888')
  $$,
  'P0001',
  'not authorized'
);

SET LOCAL request.jwt.claims = '{
  "sub":"EEEEEEEE-9999-aaaa-bbbb-cccccccccccc",
  "app_metadata":{"role":"student"}
}';

SELECT throws_ok(
  $$
    SELECT * FROM public.get_student_math_fact_recent_misses('CCCCCCCC-5555-6666-7777-888888888888')
  $$,
  'P0001',
  'not authorized'
);

-- 8. admin override allowed
SET LOCAL request.jwt.claims = '{
  "sub":"00000000-0000-0000-0000-000000000999",
  "app_metadata":{"role":"admin"}
}';

SELECT ok(
  (
    SELECT count(*)
    FROM public.get_student_math_fact_mastery('CCCCCCCC-5555-6666-7777-888888888888')
  ) > 0,
  'admin can read mastery for any student'
);

SELECT * FROM finish();
ROLLBACK;
