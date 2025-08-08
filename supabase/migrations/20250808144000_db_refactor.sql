-- Backend DB build-out and alignment with planned schema
-- Safe, additive refactor on top of initial schema

-- Extensions
create extension if not exists pgcrypto;

-- Rename parents -> profiles (if exists)
do $$ begin
  if to_regclass('public.parents') is not null and to_regclass('public.profiles') is null then
    execute 'alter table public.parents rename to profiles';
  end if;
end $$;

-- Levels: sra_levels -> levels; add code, rename columns
do $$ begin
  if to_regclass('public.sra_levels') is not null then
    execute 'alter table public.sra_levels rename to levels';
  end if;
  if to_regclass('public.levels') is null then
    execute 'create table public.levels (
      id serial primary key,
      label text not null,
      ordinal int not null,
      code text unique
    )';
  end if;
end $$;

-- Rename columns if present
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='levels' and column_name='name') then
    execute 'alter table public.levels rename column name to label';
  end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='levels' and column_name='level_order') then
    execute 'alter table public.levels rename column level_order to ordinal';
  end if;
end $$;

alter table public.levels add column if not exists code text;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'levels_code_unique'
      and conrelid = 'public.levels'::regclass
  ) then
    execute 'alter table public.levels add constraint levels_code_unique unique (code)';
  end if;
end
$$;

-- Populate level codes if missing
update public.levels
set code = case
  when label ilike 'Picture Level' then 'picture'
  when label ilike 'Preparatory Level' then 'prep'
  when label ilike 'Level A' then 'A'
  when label ilike 'Level B' then 'B'
  when label ilike 'Level C' then 'C'
  when label ilike 'Level D' then 'D'
  when label ilike 'Level E' then 'E'
  when label ilike 'Level F' then 'F'
  when label ilike 'Level G' then 'G'
  when label ilike 'Level H' then 'H'
  else lower(replace(label,' ','_'))
end
where code is null;

-- Skills: sra_categories -> skills; add code, rename columns
do $$ begin
  if to_regclass('public.sra_categories') is not null then
    execute 'alter table public.sra_categories rename to skills';
  end if;
  if to_regclass('public.skills') is null then
    execute 'create table public.skills (
      id serial primary key,
      label text not null,
      code text unique
    )';
  end if;
end $$;

do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='skills' and column_name='name') then
    execute 'alter table public.skills rename column name to label';
  end if;
end $$;

alter table public.skills add column if not exists code text;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'skills_code_unique'
      and conrelid = 'public.skills'::regclass
  ) then
    execute 'alter table public.skills add constraint skills_code_unique unique (code)';
  end if;
end
$$;

-- Populate skill codes if missing
update public.skills
set code = case
  when label ilike 'Working Within Words' then 'working_within_words'
  when label ilike 'Following Directions' then 'following_directions'
  when label ilike 'Using the Context' then 'using_the_context'
  when label ilike 'Locating the Answer' then 'locating_the_answer'
  when label ilike 'Getting the Facts' then 'getting_the_facts'
  when label ilike 'Getting the Main Idea' then 'getting_the_main_idea'
  when label ilike 'Drawing Conclusions' then 'drawing_conclusions'
  when label ilike 'Detecting the Sequence' then 'detecting_the_sequence'
  when label ilike 'Identifying Inferences' then 'identifying_inferences'
  else lower(replace(label,' ','_'))
end
where code is null;

-- Books: sra_books -> books; add title, order_index, total_units
do $$ begin
  if to_regclass('public.sra_books') is not null then
    execute 'alter table public.sra_books rename to books';
  end if;
end $$;

alter table public.books add column if not exists title text;
alter table public.books add column if not exists order_index int default 0;
alter table public.books add column if not exists total_units int default 0;

-- Backfill titles and order_index
with skill_order as (
  select s.id as skill_id, s.code, s.label,
    case s.code
      when 'working_within_words' then 1
      when 'following_directions' then 2
      when 'using_the_context' then 3
      when 'locating_the_answer' then 4
      when 'getting_the_facts' then 5
      when 'getting_the_main_idea' then 6
      when 'drawing_conclusions' then 7
      when 'detecting_the_sequence' then 8
      when 'identifying_inferences' then 9
      else 999 end as idx
  from public.skills s
)
update public.books b
set title = concat(l.label, ' — ', s.label),
    order_index = so.idx
from public.levels l, public.skills s, skill_order so
where s.id = b.category_id
  and so.skill_id = s.id
  and b.level_id = l.id
  and (b.title is null or b.title = '')
  and (b.order_index is null or b.order_index = 0);

-- Units: ensure column name and index
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='units' and column_name='unit_number') then
    execute 'alter table public.units rename column unit_number to unit_index';
  end if;
end $$;

create unique index if not exists units_book_unit_idx on public.units(book_id, unit_index);

-- Questions: add typed columns
alter table public.questions add column if not exists type text default 'short_answer' not null;
alter table public.questions add column if not exists prompt jsonb default '{}'::jsonb not null;
alter table public.questions add column if not exists options jsonb;
alter table public.questions add column if not exists answer_key jsonb;

-- Backfill answer_key from correct_answer if present
update public.questions set answer_key = to_jsonb(correct_answer)
where answer_key is null and correct_answer is not null;

-- Progress tracking tables
create table if not exists public.book_progress (
  child_id uuid not null references public.children(id) on delete cascade,
  book_id int not null references public.books(id) on delete cascade,
  status text not null default 'not_started',
  started_at timestamptz,
  completed_at timestamptz,
  score numeric,
  primary key(child_id, book_id)
);

-- Constrain status to known values (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'book_progress_status_chk'
      and conrelid = 'public.book_progress'::regclass
  ) then
    execute 'alter table public.book_progress add constraint book_progress_status_chk
      check (status in (''not_started'',''in_progress'',''redo'',''completed''))';
  end if;
end
$$;

create table if not exists public.unit_attempts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children(id) on delete cascade,
  unit_id int not null references public.units(id) on delete cascade,
  started_at timestamptz default now(),
  completed_at timestamptz,
  correct_count int default 0,
  total_count int default 0
);
create index if not exists unit_attempts_child_unit_idx on public.unit_attempts(child_id, unit_id);

create table if not exists public.responses (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.unit_attempts(id) on delete cascade,
  question_id int not null references public.questions(id) on delete cascade,
  answer jsonb not null,
  correct boolean not null
);
create unique index if not exists responses_attempt_question_idx on public.responses(attempt_id, question_id);

-- RLS policies for new tables
alter table public.book_progress enable row level security;
alter table public.unit_attempts enable row level security;
alter table public.responses enable row level security;

-- book_progress policies
create policy if not exists "parents view book_progress" on public.book_progress
  for select using (exists (
    select 1 from public.children c where c.id = book_progress.child_id and c.parent_id = auth.uid()
  ));
create policy if not exists "parents manage book_progress" on public.book_progress
  for all using (exists (
    select 1 from public.children c where c.id = book_progress.child_id and c.parent_id = auth.uid()
  )) with check (exists (
    select 1 from public.children c where c.id = book_progress.child_id and c.parent_id = auth.uid()
  ));

-- unit_attempts policies
create policy if not exists "parents view attempts" on public.unit_attempts
  for select using (exists (
    select 1 from public.children c where c.id = unit_attempts.child_id and c.parent_id = auth.uid()
  ));
create policy if not exists "parents manage attempts" on public.unit_attempts
  for all using (exists (
    select 1 from public.children c where c.id = unit_attempts.child_id and c.parent_id = auth.uid()
  )) with check (exists (
    select 1 from public.children c where c.id = unit_attempts.child_id and c.parent_id = auth.uid()
  ));

-- responses policies
create policy if not exists "parents view responses" on public.responses
  for select using (exists (
    select 1 from public.unit_attempts ua
    join public.children c on c.id = ua.child_id
    where ua.id = responses.attempt_id and c.parent_id = auth.uid()
  ));
create policy if not exists "parents manage responses" on public.responses
  for all using (exists (
    select 1 from public.unit_attempts ua
    join public.children c on c.id = ua.child_id
    where ua.id = responses.attempt_id and c.parent_id = auth.uid()
  )) with check (exists (
    select 1 from public.unit_attempts ua
    join public.children c on c.id = ua.child_id
    where ua.id = responses.attempt_id and c.parent_id = auth.uid()
  ));
