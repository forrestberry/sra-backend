Backend Schema Draft (Documentation Only)

Purpose
- Outline the proposed relational schema, RLS policies, and seeds for SRA backend.
- This is a planning document; do not execute in production yet.

Entities
- profiles: Parent accounts (maps 1:1 with Supabase Auth users)
- children: Child profiles owned by a parent; no separate auth
- levels: Static list of level codes (picture, prep, A–H)
- skills: Static list of skill categories (9 skills)
- books: Cross-product Level × Skill (ordered within a level)
- units: Ordered units per book
- questions: Questions per unit with typed prompts/options and answer_key
- book_progress: Per-child per-book state and aggregate score
- unit_attempts: Attempts per unit per child
- responses: Per-question response within an attempt

Draft SQL (DDL)
```sql
-- Profiles (parents)
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz default now()
);

-- Children
create table if not exists children (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  level_code text not null,
  created_at timestamptz default now()
);

-- Levels
create table if not exists levels (
  code text primary key,
  ordinal int not null,
  label text not null
);

-- Skills
create table if not exists skills (
  code text primary key,
  label text not null
);

-- Books (Level × Skill)
create table if not exists books (
  id uuid primary key default gen_random_uuid(),
  level_code text not null references levels(code) on delete restrict,
  skill_code text not null references skills(code) on delete restrict,
  title text not null,
  order_index int not null,
  total_units int not null
);
create unique index if not exists books_level_skill_idx
  on books(level_code, skill_code);

-- Units
create table if not exists units (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references books(id) on delete cascade,
  unit_index int not null
);
create unique index if not exists units_book_index_idx
  on units(book_id, unit_index);

-- Questions (typed)
create table if not exists questions (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id) on delete cascade,
  question_index int not null,
  type text not null, -- e.g., multiple_choice, true_false, short_answer
  prompt jsonb not null, -- structure depends on type
  options jsonb,         -- for choice-based types
  answer_key jsonb not null
);
create unique index if not exists questions_unit_index_idx
  on questions(unit_id, question_index);

-- Book Progress
create table if not exists book_progress (
  child_id uuid not null references children(id) on delete cascade,
  book_id uuid not null references books(id) on delete cascade,
  status text not null default 'not_started', -- not_started|in_progress|redo|completed
  started_at timestamptz,
  completed_at timestamptz,
  score numeric,
  primary key(child_id, book_id)
);

-- Unit Attempts
create table if not exists unit_attempts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  unit_id uuid not null references units(id) on delete cascade,
  started_at timestamptz default now(),
  completed_at timestamptz,
  correct_count int default 0,
  total_count int default 0
);
create index if not exists unit_attempts_child_unit_idx
  on unit_attempts(child_id, unit_id);

-- Responses
create table if not exists responses (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references unit_attempts(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  answer jsonb not null,
  correct boolean not null
);
create unique index if not exists responses_attempt_question_idx
  on responses(attempt_id, question_id);
```

Row-Level Security (RLS)
```sql
alter table profiles enable row level security;
alter table children enable row level security;
alter table book_progress enable row level security;
alter table unit_attempts enable row level security;
alter table responses enable row level security;

-- Profiles: a user can see only their row
create policy "parents can view self" on profiles
  for select using (id = auth.uid());
create policy "parents can manage self" on profiles
  for all using (id = auth.uid());

-- Children: filter by parent ownership
create policy "parents view children" on children
  for select using (parent_id = auth.uid());
create policy "parents manage children" on children
  for all using (parent_id = auth.uid());

-- Progress/Attempts/Responses: join through child ownership
create policy "parents view book_progress" on book_progress
  for select using (exists (
    select 1 from children c where c.id = book_progress.child_id and c.parent_id = auth.uid()
  ));
create policy "parents manage book_progress" on book_progress
  for all using (exists (
    select 1 from children c where c.id = book_progress.child_id and c.parent_id = auth.uid()
  ));

create policy "parents view attempts" on unit_attempts
  for select using (exists (
    select 1 from children c where c.id = unit_attempts.child_id and c.parent_id = auth.uid()
  ));
create policy "parents manage attempts" on unit_attempts
  for all using (exists (
    select 1 from children c where c.id = unit_attempts.child_id and c.parent_id = auth.uid()
  ));

create policy "parents view responses" on responses
  for select using (exists (
    select 1 from unit_attempts ua
    join children c on c.id = ua.child_id
    where ua.id = responses.attempt_id and c.parent_id = auth.uid()
  ));
create policy "parents manage responses" on responses
  for all using (exists (
    select 1 from unit_attempts ua
    join children c on c.id = ua.child_id
    where ua.id = responses.attempt_id and c.parent_id = auth.uid()
  ));
```

Seeds (Reference)
```sql
insert into levels (code, ordinal, label) values
  ('picture', 0, 'Picture Level'),
  ('prep', 1, 'Preparatory Level'),
  ('A', 2, 'Level A'),
  ('B', 3, 'Level B'),
  ('C', 4, 'Level C'),
  ('D', 5, 'Level D'),
  ('E', 6, 'Level E'),
  ('F', 7, 'Level F'),
  ('G', 8, 'Level G'),
  ('H', 9, 'Level H');

insert into skills (code, label) values
  ('working_within_words', 'Working Within Words'),
  ('following_directions', 'Following Directions'),
  ('using_the_context', 'Using the Context'),
  ('locating_the_answer', 'Locating the Answer'),
  ('getting_the_facts', 'Getting the Facts'),
  ('getting_the_main_idea', 'Getting the Main Idea'),
  ('drawing_conclusions', 'Drawing Conclusions'),
  ('detecting_the_sequence', 'Detecting the Sequence'),
  ('identifying_inferences', 'Identifying Inferences');
```

Notes
- Books can be generated programmatically from Level × Skill with consistent `order_index` per level.
- Questions content ingestion is out of scope here; store canonical content in `questions` with type-safe shapes.
- Grading logic can remain in Edge Functions comparing `answer` vs `answer_key` and writing attempts/responses.

