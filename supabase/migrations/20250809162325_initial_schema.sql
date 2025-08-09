-- Initial schema based on ERD (normalized)
-- Generated on 2025-08-09

-- Ensure UUID generation available
create extension if not exists pgcrypto with schema extensions;

-- Helper to keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Parent
create table if not exists public.parent (
  id uuid primary key default extensions.gen_random_uuid(),
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Student
create table if not exists public.student (
  id uuid primary key default extensions.gen_random_uuid(),
  username text not null unique,
  current_level_id uuid null references public.level(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Level
create table if not exists public.level (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null unique,
  sort_order int not null
);

-- Category
create table if not exists public.category (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null unique,
  sort_order int not null
);

-- Book
create table if not exists public.book (
  id uuid primary key default extensions.gen_random_uuid(),
  level_id uuid not null references public.level(id) on delete restrict,
  category_id uuid not null references public.category(id) on delete restrict,
  title text not null,
  units_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Unit
create table if not exists public.unit (
  id uuid primary key default extensions.gen_random_uuid(),
  book_id uuid not null references public.book(id) on delete cascade,
  unit_number int not null,
  unit_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (book_id, unit_number)
);

-- Question
create table if not exists public.question (
  id uuid primary key default extensions.gen_random_uuid(),
  unit_id uuid not null references public.unit(id) on delete cascade,
  question_number int not null,
  question_data jsonb not null default '{}'::jsonb,
  answer_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (unit_id, question_number)
);

-- Answer
create table if not exists public.answer (
  id uuid primary key default extensions.gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  question_id uuid not null references public.question(id) on delete cascade,
  response_text text not null,
  attempt_number int not null default 1,
  is_correct boolean not null default false,
  submitted_at timestamptz not null default now()
);

-- Parent-Student Link (composite PK)
create table if not exists public.parent_student_link (
  parent_id uuid not null references public.parent(id) on delete cascade,
  student_id uuid not null references public.student(id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  primary key (parent_id, student_id)
);

-- Student Book Progress
create table if not exists public.student_book_progress (
  id uuid primary key default extensions.gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  book_id uuid not null references public.book(id) on delete cascade,
  units_completed int not null default 0,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, book_id)
);

-- Useful indexes for FKs and lookups
create index if not exists idx_book_level on public.book(level_id);
create index if not exists idx_book_category on public.book(category_id);
create index if not exists idx_unit_book on public.unit(book_id);
create index if not exists idx_question_unit on public.question(unit_id);
create index if not exists idx_answer_student on public.answer(student_id);
create index if not exists idx_answer_question on public.answer(question_id);
create index if not exists idx_progress_student on public.student_book_progress(student_id);
create index if not exists idx_progress_book on public.student_book_progress(book_id);

-- updated_at triggers
create trigger set_updated_at_parent before update on public.parent
for each row execute function public.set_updated_at();
create trigger set_updated_at_student before update on public.student
for each row execute function public.set_updated_at();
create trigger set_updated_at_book before update on public.book
for each row execute function public.set_updated_at();
create trigger set_updated_at_unit before update on public.unit
for each row execute function public.set_updated_at();
create trigger set_updated_at_question before update on public.question
for each row execute function public.set_updated_at();
create trigger set_updated_at_sbp before update on public.student_book_progress
for each row execute function public.set_updated_at();

-- Note: RLS policies are not enabled in this initial scaffold.
-- We'll add table-specific RLS and policies in a follow-up migration once access patterns are finalized.
