BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(17);

-- ---------- SEED USERS ----------

-- Seed admin
INSERT INTO auth.users (id, email, raw_user_meta_data)
  VALUES (
    'D6843197-E49F-4B02-B443-3B8AD7101948',
    'admin@pgtap.test',
    jsonb_build_object('role', 'admin')
  )
  ON CONFLICT (id) DO NOTHING;

-- Seed parents
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '25192763-82C8-405D-8B06-D39115B1E7FA',
  'parent1@test.com',
  jsonb_build_object('role','parent','display_name','parent1')
),
(
  '6DE97FE3-0711-4EAD-92A0-83F819CF9FAA',
  'parent2@test.com',
  jsonb_build_object('role','parent','display_name','parent2')
),
(
  '7DE97FE3-0711-4EAD-92A0-83F819CF9FAA',
  'parent3@test.com',
  jsonb_build_object('role','parent','display_name','parent3', 'parent_id','6DE97FE3-0711-4EAD-92A0-83F819CF9FAA')
)
ON CONFLICT (id) DO NOTHING;

-- Seed student users
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  'B827564E-51D2-4BEC-B0C3-A877DD91C304',
  'student1@sra.local',
  jsonb_build_object('role','student','username','student1', 'parent_id','25192763-82C8-405D-8B06-D39115B1E7FA')
),
(
  '23D636A5-FC3B-465A-82BC-25BA13D3C608',
  'student2@sra.local',
  jsonb_build_object('role','student','username','student2', 'parent_id','6DE97FE3-0711-4EAD-92A0-83F819CF9FAA')
),
(
  '13D636A5-FC3B-465A-82BC-25BA13D3C608',
  'student3@sra.local',
  jsonb_build_object('role','student','username','student3', 'parent_id','6DE97FE3-0711-4EAD-92A0-83F819CF9FAA')
)
ON CONFLICT (id) DO NOTHING;

-- ---------- TEST ADMIN ACTIONS ----------

-- Set user as admin
set local role authenticated;
set local request.jwt.claims = '{
  "sub":"D6843197-E49F-4B02-B443-3B8AD7101948",
  "app_metadata": {"role":"admin"}
}';

-- Test: admin should be able to insert units
SELECT results_eq(
  $$
    INSERT INTO public.unit (book_id, unit_number)
    VALUES (
      (SELECT id 
        FROM public.book 
        WHERE title = 'Picture - Working Within Words'
        LIMIT 1),
      999
    )
    RETURNING unit_number
  $$,
  ARRAY[999],
  'retrieved the test unit tied to that existing book'
);

-- Test: admin should be able to insert questions
SELECT results_eq(
  $$
    INSERT INTO public.question (unit_id, question_number, answer_key)
    VALUES (
      (SELECT id
        FROM public.unit 
        WHERE unit_number = 999 
        LIMIT 1),
      888,
      'ZZ'
    )
    RETURNING question_number
  $$,
  ARRAY[888],
  'retrieved the test question tied to that existing unit'
);

-- ---------- TEST PARENT ACTIONS ----------

-- Set user as parent 1
set local role authenticated;
set local request.jwt.claims = '{
  "sub":"25192763-82C8-405D-8B06-D39115B1E7FA",
  "app_metadata": {"role":"parent"}
}';

-- Non-admin cannot insert unit
SELECT throws_ok(
  $$
  insert into public.unit (book_id, unit_number)
    values ((select id from public.book limit 1), 998);
  $$,
  '42501' -- insufficient_privilege
);

-- Non-admin cannot insert question
SELECT throws_ok(
  $$
    INSERT INTO public.question (unit_id, question_number, answer_key)
    VALUES (
      (SELECT id
        FROM public.unit 
        WHERE unit_number = 999 
        LIMIT 1),
      887,
      'ZZ'
    )
  $$,
  '42501' -- insufficient_privilege
);

-- Test: parent should only see their own row
SELECT results_eq(
  'select count(id) FROM public.parent',
  ARRAY[1::bigint],
  'Parent 1 should only see their own data'
);

-- Test: parent should see books
SELECT results_eq(
  'select count(id) FROM public.book',
  ARRAY[90::bigint],
  'Parent 1 should see all 90 books'
);

-- Test: parent should see their student
SELECT results_eq(
  'select count(id) FROM public.student',
  ARRAY[1::bigint],
  'Parent 1 should only see their own student data'
);

-- Set user as parent 2
set local role authenticated;
set local request.jwt.claims = '{
  "sub":"6DE97FE3-0711-4EAD-92A0-83F819CF9FAA",
  "app_metadata": {"role":"parent"}
}';

-- Test: parent should see their student
SELECT results_eq(
  'select count(id) FROM public.student',
  ARRAY[2::bigint],
  'Parent 2 should only see both of their student data'
);

-- Test: parent should see their linked parent
SELECT results_eq(
  'select count(parent_id) FROM public.parent_parent_link',
  ARRAY[2::bigint],
  'Parent 2 should see their linked parent and inverse link'
);

-- Test: Parent should be able to see their student book progress
SELECT results_eq(
  'select count(id) from public.student_book_progress where student_id = ''23D636A5-FC3B-465A-82BC-25BA13D3C608''',
  ARRAY[90::bigint],
  'Parent 2 should be able to see their student book progress'
);

-- ---------- TEST STUDENT ACTIONS ----------

-- Set user as student 1
SET LOCAL role authenticated;
set local request.jwt.claims = '{
  "sub":"B827564E-51D2-4BEC-B0C3-A877DD91C304",
  "app_metadata": {"role":"student"}
}';

-- Test: student should see their parent link
SELECT is(
  (select parent_id 
    FROM public.parent_student_link 
    WHERE student_id = 'B827564E-51D2-4BEC-B0C3-A877DD91C304'),
  '25192763-82C8-405D-8B06-D39115B1E7FA',
  'Student 1 should see their parent id'
);

-- Set user as student 2
SET LOCAL role authenticated;
set local request.jwt.claims = '{
  "sub":"23D636A5-FC3B-465A-82BC-25BA13D3C608",
  "app_metadata": {"role":"parent"}
}';

-- Test: student should see their primary parent link
select results_eq(
  'select count(parent_id) from public.parent_student_link where student_id = ''23D636A5-FC3B-465A-82BC-25BA13D3C608''',
  ARRAY[2::bigint],
  'Student 2 should see their parent links'
);

-- Test: student should be able to view self
SELECT results_eq(
  'select count(id) from public.student where id = ''23D636A5-FC3B-465A-82BC-25BA13D3C608''',
  ARRAY[1::bigint],
  'Student 2 should be able to view their own data'
);

-- Test: Student should be able to submit answer
SELECT results_eq(
  $$
    INSERT INTO public.answer (student_id, question_id, response_text, attempt_number)
    VALUES (
      '23D636A5-FC3B-465A-82BC-25BA13D3C608',
      (SELECT id FROM public.question WHERE question_number = 888 LIMIT 1),
      'ZZZ',
      777
    )
    RETURNING attempt_number
  $$,
  ARRAY[777],
  'Student 2 should be able to submit an answer'
);

-- Test: Student should be able to view their own answers
SELECT results_eq(
  'select count(id) from public.answer where student_id = ''23D636A5-FC3B-465A-82BC-25BA13D3C608''',
  ARRAY[1::bigint],
  'Student 2 should be able to view their own answers'
);

-- Test: Student should be able to see book progress
SELECT results_eq(
  'select count(id) from public.student_book_progress where student_id = ''23D636A5-FC3B-465A-82BC-25BA13D3C608''',
  ARRAY[90::bigint],
  'Student 2 should be able to see their book progress'
);

-- ---------- TEST PARENT VIEWING STUDENT DATA ----------

-- Set user as parent 1
set local role authenticated;
set local request.jwt.claims = '{
  "sub":"25192763-82C8-405D-8B06-D39115B1E7FA",
  "app_metadata": {"role":"parent"}
}';

-- Test: Parent should be able to view their student answers
SELECT results_eq(
  'select count(id) from public.answer where student_id = ''B827564E-51D2-4BEC-B0C3-A877DD91C304''',
  ARRAY[0::bigint],
  'Parent 1 should not see student 1 answers'
);

SELECT * FROM finish();
ROLLBACK;
