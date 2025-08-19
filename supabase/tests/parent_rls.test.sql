BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);

-- Seed parent users
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '25192763-82C8-405D-8B06-D39115B1E7FA',
  'parent1@test.com',
  jsonb_build_object('role','parent','display_name','first')
),
(
  '6DE97FE3-0711-4EAD-92A0-83F819CF9FAA',
  'parent2@test.com',
  jsonb_build_object('role','parent','display_name','second')
),
(
  '7DE97FE3-0711-4EAD-92A0-83F819CF9FAA',
  'parent3@test.com',
  jsonb_build_object('role','parent','display_name','third', 'parent_id','6DE97FE3-0711-4EAD-92A0-83F819CF9FAA')
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

-- Set user as parent 1
set local role authenticated;
set local request.jwt.claim.sub = '25192763-82C8-405D-8B06-D39115B1E7FA';

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
set local request.jwt.claim.sub = '6DE97FE3-0711-4EAD-92A0-83F819CF9FAA';

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

-- Set user as student 1
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = 'B827564E-51D2-4BEC-B0C3-A877DD91C304';

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
SET LOCAL request.jwt.claim.sub = '23D636A5-FC3B-465A-82BC-25BA13D3C608';

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

-- TODO: Seed some unit and question data in the migration before creating:
-- TODO: in migration, create a trigger that creates all book progess rows for each student when a student is created

-- Test: Student should be able to submit answer

-- Test: Student should be able to view their own answers

-- Test: Parent should be able to view their student answers

-- Test: Student should be able to see book progress

-- Test: Parent should be able to see their student book progress


SELECT * FROM finish();
ROLLBACK;
