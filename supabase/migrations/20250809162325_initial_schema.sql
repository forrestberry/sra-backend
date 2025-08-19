-- initial schema based on erd (normalized)
-- generated on 2025-08-09

-- enable pgcrypto for uuid generation
create extension if not exists pgcrypto;

-- helper to keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger 
language plpgsql 
security definer
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------ tables ------------------

-- books

-- level
create table if not exists public.level (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null check (sort_order > 0)
);

-- category
create table if not exists public.category (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null check (sort_order > 0)
);

-- book
create table if not exists public.book (
  id uuid primary key default gen_random_uuid(),
  level_id uuid not null references public.level(id) on delete restrict,
  category_id uuid not null references public.category(id) on delete restrict,
  title text not null,
  units_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- unit
create table if not exists public.unit (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.book(id) on delete cascade,
  unit_number int not null check (unit_number > 0),
  unit_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (book_id, unit_number)
);

-- question
create table if not exists public.question (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references public.unit(id) on delete cascade,
  question_number int not null check (question_number > 0),
  question_data jsonb not null default '{}'::jsonb,
  answer_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, question_number)
);

-- users

-- parent
create table if not exists public.parent (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- student
create table if not exists public.student (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  current_level_id uuid null references public.level(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- parent-student link (composite pk)
create table if not exists public.parent_student_link (
  parent_id uuid not null references public.parent(id) on delete cascade,
  student_id uuid not null references public.student(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);

-- parent-parent link (composite pk)
create table if not exists public.parent_parent_link(
  parent_id uuid not null references public.parent(id) on delete cascade,
  linked_parent_id uuid not null references public.parent(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (parent_id, linked_parent_id)
);

-- student progress

-- answer
create table if not exists public.answer (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  question_id uuid not null references public.question(id) on delete cascade,
  response_text text not null,
  attempt_number int not null default 1 check (attempt_number > 0),
  is_correct boolean not null default false,
  submitted_at timestamptz not null default now(),
  unique (student_id, question_id, attempt_number)
);

-- student book progress status enums
create type public.book_progress_status as enum (
  'not_started',
  'skipped',
  'in_progress',
  'completed'
);

-- student book progress
create table if not exists public.student_book_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  book_id uuid not null references public.book(id) on delete cascade,
  units_completed int not null default 0 check (units_completed >= 0),
  status public.book_progress_status not null default 'not_started',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, book_id)
);

-- ------------------ indexes ------------------

create index if not exists idx_book_level on public.book(level_id);
create index if not exists idx_book_category on public.book(category_id);
create index if not exists idx_unit_book on public.unit(book_id);
create index if not exists idx_question_unit on public.question(unit_id);
create index if not exists idx_answer_student on public.answer(student_id);
create index if not exists idx_answer_question on public.answer(question_id);
create index if not exists idx_progress_student on public.student_book_progress(student_id);
create index if not exists idx_progress_book on public.student_book_progress(book_id);
create index if not exists idx_psl_parent on public.parent_student_link(parent_id);
create index if not exists idx_psl_student on public.parent_student_link(student_id);
create index if not exists idx_answer_student_question_time
  on public.answer (student_id, question_id, submitted_at desc);
create index if not exists idx_answer_student_question_correct
  on public.answer (student_id, question_id)
  where is_correct = true;
create index if not exists idx_student_current_level
  on public.student (current_level_id);

-- ------------------ rls policies ------------------

alter table public.parent enable row level security;
alter table public.student enable row level security;
alter table public.parent_parent_link enable row level security;
alter table public.parent_student_link enable row level security;
alter table public.answer enable row level security;
alter table public.student_book_progress enable row level security;
alter table public.book enable row level security;
alter table public.category enable row level security;
alter table public.level enable row level security;
alter table public.unit enable row level security;
alter table public.question enable row level security;

-- Read-only policies (for book data)
create policy "read books"
  on public.book for select
  to anon, authenticated
  using (true);

create policy "read categories"
  on public.category for select
  to anon, authenticated
  using (true);

create policy "read levels"
  on public.level for select
  to anon, authenticated
  using (true);

create policy "read units"
  on public.unit for select
  to anon, authenticated
  using (true);

create policy "read questions"
  on public.question for select
  to anon, authenticated
  using (true);

-- parent policies
create policy "parent can view self"
    on public.parent for select
    using (id = (select auth.uid()));

create policy "parent can update self"
    on public.parent for update
    using (id = (select auth.uid()));

create policy "view_parent_parent_links"
  on public.parent_parent_link
  for select
  to authenticated
  using (
    parent_id = (select auth.uid())
    or linked_parent_id = (select auth.uid())
  );

-- student policies
create policy "student can view parent"
    on public.parent for select
    using (
      exists (
        select 1
        from public.parent_student_link l
        where l.student_id = (select auth.uid())
          and l.parent_id = parent.id
      )
    );

create policy "student can submit answers"
on public.answer for insert
with check (student_id = (select auth.uid()));


-- combo policies
create policy "view_student"
  on public.student for select
  using (
    -- student sees self
    id = (select auth.uid())
    -- parent sees their children
    or exists (
      select 1
      from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = student.id
    )
  );

create policy "view_answers"
  on public.answer for select
  using (
    -- student sees own answers
    student_id = (select auth.uid())
    -- parent sees child's answers through link
    or exists (
      select 1
      from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = answer.student_id
    )
  );

create policy "view_student_links"
  on public.parent_student_link for select
  using (
    parent_id  = (select auth.uid())
    or student_id = (select auth.uid())
  );

create policy "view_student_book_progress"
  on public.student_book_progress for select
  using (
    -- student sees own progress
    student_id = (select auth.uid())
    -- parent sees child's progress via link
    or exists (
      select 1
      from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = student_book_progress.student_id
    )
  );

-- ------------------ triggers ------------------

create trigger set_updated_at_parent 
  before update on public.parent
  for each row execute function public.set_updated_at();
create trigger set_updated_at_student 
  before update on public.student
  for each row execute function public.set_updated_at();
create trigger set_updated_at_book 
  before update on public.book
  for each row execute function public.set_updated_at();
create trigger set_updated_at_unit 
  before update on public.unit
  for each row execute function public.set_updated_at();
create trigger set_updated_at_question 
  before update on public.question
  for each row execute function public.set_updated_at();
create trigger set_updated_at_sbp 
  before update on public.student_book_progress
  for each row execute function public.set_updated_at();

-- Handle new auth.users rows for parents and students
create or replace function public.handle_new_user_profiles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  _role         text := new.raw_user_meta_data->>'role';
  _parent_id    uuid := nullif(new.raw_user_meta_data->>'parent_id', '')::uuid;
  _username     text := new.raw_user_meta_data->>'username';
  _display_name text := coalesce(
    new.raw_user_meta_data->>'display_name',
    nullif(split_part(new.email, '@', 1), ''),
    'user'
  );
begin
  if _role = 'parent' then
    insert into public.parent (id, display_name)
    values (new.id, _display_name)
    on conflict (id) do nothing;
    if _parent_id is not null then
      insert into public.parent_parent_link (parent_id, linked_parent_id)
      values (new.id, _parent_id)
      on conflict (parent_id, linked_parent_id) do nothing;
    end if;

  elsif _role = 'student' then
    if _parent_id is null then
      raise exception 'student account requires raw_user_meta_data.parent_id';
    end if;

    if _username is null then
      raise exception 'student account requires raw_user_meta_data.username';
    end if;

    insert into public.student (id, username)
    values (new.id, _username)
    on conflict (id) do nothing;

    -- establish the relationship
    insert into public.parent_student_link (parent_id, student_id)
    values (_parent_id, new.id)
    on conflict (parent_id, student_id) do nothing;

  else
    -- other roles: no-op
    null;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profiles on auth.users;

create trigger on_auth_user_created_profiles
  after insert on auth.users
  for each row execute procedure public.handle_new_user_profiles();

-- Ensure parent links are symmetric
create or replace function public.ensure_symmetric_parent_link()
returns trigger
language plpgsql as $$
begin
  if not exists (
    select 1
    from public.parent_parent_link
    where parent_id = new.linked_parent_id
      and linked_parent_id = new.parent_id
  ) then
    insert into public.parent_parent_link (parent_id, linked_parent_id)
    values (new.linked_parent_id, new.parent_id);
  end if;
  return new;
end;
$$;

create trigger parent_parent_link_symmetric
after insert on public.parent_parent_link
for each row execute function public.ensure_symmetric_parent_link();

-- Create student links across parents when a parent-parent link is created
create or replace function public.ensure_parent_student_links_on_parent_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Link NEW.linked_parent_id to all students of NEW.parent_id
  insert into public.parent_student_link (parent_id, student_id)
  select new.linked_parent_id, psl.student_id
  from public.parent_student_link psl
  where psl.parent_id = new.parent_id
  on conflict (parent_id, student_id) do nothing;

  -- Link NEW.parent_id to all students of NEW.linked_parent_id
  insert into public.parent_student_link (parent_id, student_id)
  select new.parent_id, psl.student_id
  from public.parent_student_link psl
  where psl.parent_id = new.linked_parent_id
  on conflict (parent_id, student_id) do nothing;

  return new;
end;
$$;

drop trigger if exists parent_parent_link_backfill_psl on public.parent_parent_link;

create trigger parent_parent_link_backfill_psl
after insert on public.parent_parent_link
for each row execute function public.ensure_parent_student_links_on_parent_link();

-- When a parent gets linked to a student, also link that student to all of the parent's linked parents
create or replace function public.propagate_parent_student_link_to_linked_parents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- For every parent linked to NEW.parent_id, add (that parent, NEW.student_id)
  insert into public.parent_student_link (parent_id, student_id)
  select ppl.linked_parent_id, new.student_id
  from public.parent_parent_link ppl
  where ppl.parent_id = new.parent_id
  on conflict (parent_id, student_id) do nothing;

  -- Also handle the reverse link direction (because you maintain symmetric links)
  insert into public.parent_student_link (parent_id, student_id)
  select ppl.parent_id, new.student_id
  from public.parent_parent_link ppl
  where ppl.linked_parent_id = new.parent_id
  on conflict (parent_id, student_id) do nothing;

  return new;
end;
$$;

drop trigger if exists parent_student_link_propagate on public.parent_student_link;

create trigger parent_student_link_propagate
after insert on public.parent_student_link
for each row execute function public.propagate_parent_student_link_to_linked_parents();
