-- math facts schema extension

-- enums
do $$
begin
  if not exists (select 1 from pg_type where typname = 'math_fact_operation') then
    create type public.math_fact_operation as enum ('addition', 'subtraction', 'multiplication', 'division');
  end if;

  if not exists (select 1 from pg_type where typname = 'math_session_mode') then
    create type public.math_session_mode as enum ('learning', 'timed_test');
  end if;

  if not exists (select 1 from pg_type where typname = 'math_session_status') then
    create type public.math_session_status as enum ('issued', 'submitted', 'discarded');
  end if;

  if not exists (select 1 from pg_type where typname = 'math_fact_mastery_status') then
    create type public.math_fact_mastery_status as enum ('training', 'mastered', 'needs_review');
  end if;
end $$;

-- facts catalog
create table if not exists public.math_fact (
  id uuid primary key default gen_random_uuid(),
  operation public.math_fact_operation not null,
  operand_a smallint not null,
  operand_b smallint not null,
  result_value smallint not null,
  difficulty_tag text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint math_fact_operands_unique unique (operation, operand_a, operand_b)
);

create table if not exists public.math_fact_unit (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text null,
  is_dynamic boolean not null default false,
  rule_config jsonb null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint math_fact_unit_name_unique unique (name)
);

create table if not exists public.math_fact_unit_member (
  id uuid primary key default gen_random_uuid(),
  fact_unit_id uuid not null references public.math_fact_unit(id) on delete cascade,
  fact_id uuid not null references public.math_fact(id) on delete cascade,
  weight smallint not null default 1 check (weight > 0),
  created_at timestamptz not null default now(),
  constraint math_fact_unit_member_unique unique (fact_unit_id, fact_id)
);

create table if not exists public.student_math_fact_assignment (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  fact_unit_id uuid not null references public.math_fact_unit(id) on delete cascade,
  assigned_by uuid null references auth.users(id) on delete set null,
  is_active boolean not null default true,
  assigned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_fact_assignment_unique unique (student_id, fact_unit_id)
);

create table if not exists public.math_session (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  mode public.math_session_mode not null,
  status public.math_session_status not null default 'issued',
  requested_duration_seconds int not null check (requested_duration_seconds > 0),
  total_facts_requested int not null default 0 check (total_facts_requested >= 0),
  config jsonb not null default '{}'::jsonb,
  issued_at timestamptz not null default now(),
  submitted_at timestamptz null,
  answers_submitted int not null default 0 check (answers_submitted >= 0),
  min_answers_required int not null default 0 check (min_answers_required >= 0),
  elapsed_ms int not null default 0 check (elapsed_ms >= 0),
  wasted_ms int not null default 0 check (wasted_ms >= 0),
  counted boolean not null default false,
  discarded_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.math_session_fact (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.math_session(id) on delete cascade,
  fact_id uuid not null references public.math_fact(id) on delete restrict,
  sequence int not null check (sequence > 0),
  metadata jsonb not null default '{}'::jsonb,
  constraint math_session_fact_sequence_unique unique (session_id, sequence)
);

create table if not exists public.math_attempt (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.math_session(id) on delete cascade,
  student_id uuid not null references public.student(id) on delete cascade,
  fact_id uuid not null references public.math_fact(id) on delete restrict,
  session_fact_sequence int not null,
  response_text text not null,
  is_correct boolean not null,
  response_ms int not null check (response_ms >= 0),
  hint_used boolean not null default false,
  flashed_answer boolean not null default false,
  attempted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint math_attempt_session_sequence_unique unique (session_id, session_fact_sequence),
  constraint math_attempt_session_sequence_fk foreign key (session_id, session_fact_sequence)
    references public.math_session_fact(session_id, sequence) on delete cascade
);

create table if not exists public.student_math_fact_mastery (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.student(id) on delete cascade,
  fact_id uuid not null references public.math_fact(id) on delete cascade,
  rolling_accuracy numeric(5,4) not null default 0,
  rolling_avg_response_ms int not null default 0,
  attempts_count int not null default 0,
  correct_streak int not null default 0,
  last_attempt_at timestamptz null,
  status public.math_fact_mastery_status not null default 'training',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_math_fact_mastery_unique unique (student_id, fact_id)
);

-- indexes
create index if not exists idx_math_fact_operation on public.math_fact(operation);
create index if not exists idx_math_fact_unit_member_unit on public.math_fact_unit_member(fact_unit_id);
create index if not exists idx_math_fact_unit_member_fact on public.math_fact_unit_member(fact_id);
create index if not exists idx_student_math_fact_assignment_student on public.student_math_fact_assignment(student_id) where is_active;
create index if not exists idx_math_session_student on public.math_session(student_id);
create index if not exists idx_math_session_status on public.math_session(status);
create index if not exists idx_math_session_fact_session on public.math_session_fact(session_id);
create index if not exists idx_math_attempt_student_fact on public.math_attempt(student_id, fact_id);
create index if not exists idx_math_attempt_session on public.math_attempt(session_id);
create index if not exists idx_math_mastery_student on public.student_math_fact_mastery(student_id);
create index if not exists idx_math_mastery_fact on public.student_math_fact_mastery(fact_id);

-- RLS setup
alter table public.math_fact enable row level security;
alter table public.math_fact_unit enable row level security;
alter table public.math_fact_unit_member enable row level security;
alter table public.student_math_fact_assignment enable row level security;
alter table public.math_session enable row level security;
alter table public.math_session_fact enable row level security;
alter table public.math_attempt enable row level security;
alter table public.student_math_fact_mastery enable row level security;

-- fact catalog readable by everyone, mutable by admins
create policy if not exists "read math facts" on public.math_fact for select to anon, authenticated using (true);
create policy if not exists "admin manage math facts"
  on public.math_fact for all to authenticated
  using (auth.jwt() -> 'app_metadata' ->> 'role' = 'admin')
  with check (auth.jwt() -> 'app_metadata' ->> 'role' = 'admin');

create policy if not exists "read math fact units" on public.math_fact_unit for select to anon, authenticated using (true);
create policy if not exists "admin manage math fact units"
  on public.math_fact_unit for all to authenticated
  using (auth.jwt() -> 'app_metadata' ->> 'role' = 'admin')
  with check (auth.jwt() -> 'app_metadata' ->> 'role' = 'admin');

create policy if not exists "read math fact unit members"
  on public.math_fact_unit_member for select to anon, authenticated using (true);
create policy if not exists "admin manage math fact unit members"
  on public.math_fact_unit_member for all to authenticated
  using (auth.jwt() -> 'app_metadata' ->> 'role' = 'admin')
  with check (auth.jwt() -> 'app_metadata' ->> 'role' = 'admin');

-- student-facing policies
create policy if not exists "select math assignments"
  on public.student_math_fact_assignment
  for select using (
    student_id = (select auth.uid())
    or exists (
      select 1 from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = student_math_fact_assignment.student_id
    )
  );

create policy if not exists "insert math assignments admin"
  on public.student_math_fact_assignment
  for insert to authenticated
  with check (
    auth.jwt() -> 'app_metadata' ->> 'role' = 'admin'
    or assigned_by = (select auth.uid())
  );

create policy if not exists "select own math sessions"
  on public.math_session
  for select using (
    student_id = (select auth.uid())
    or exists (
      select 1 from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = math_session.student_id
    )
  );

create policy if not exists "insert own math sessions"
  on public.math_session
  for insert with check (student_id = (select auth.uid()));

create policy if not exists "update own math sessions"
  on public.math_session
  for update using (student_id = (select auth.uid()))
  with check (student_id = (select auth.uid()));

create policy if not exists "select session facts"
  on public.math_session_fact
  for select using (
    exists (
      select 1 from public.math_session s
      where s.id = math_session_fact.session_id
        and (
          s.student_id = (select auth.uid())
          or exists (
            select 1 from public.parent_student_link l
            where l.parent_id = (select auth.uid())
              and l.student_id = s.student_id
          )
        )
    )
  );

create policy if not exists "insert session facts"
  on public.math_session_fact
  for insert with check (
    exists (
      select 1 from public.math_session s
      where s.id = math_session_fact.session_id
        and s.student_id = (select auth.uid())
    )
  );

create policy if not exists "student insert math attempts"
  on public.math_attempt for insert
  with check (student_id = (select auth.uid()));

create policy if not exists "view math attempts"
  on public.math_attempt for select
  using (
    student_id = (select auth.uid())
    or exists (
      select 1 from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = math_attempt.student_id
    )
  );

create policy if not exists "view math mastery"
  on public.student_math_fact_mastery for select
  using (
    student_id = (select auth.uid())
    or exists (
      select 1 from public.parent_student_link l
      where l.parent_id = (select auth.uid())
        and l.student_id = student_math_fact_mastery.student_id
    )
  );

-- triggers
create trigger set_updated_at_math_fact
  before update on public.math_fact
  for each row execute function public.set_updated_at();

create trigger set_updated_at_math_fact_unit
  before update on public.math_fact_unit
  for each row execute function public.set_updated_at();

create trigger set_updated_at_math_fact_unit_member
  before update on public.math_fact_unit_member
  for each row execute function public.set_updated_at();

create trigger set_updated_at_student_math_fact_assignment
  before update on public.student_math_fact_assignment
  for each row execute function public.set_updated_at();

create trigger set_updated_at_math_session
  before update on public.math_session
  for each row execute function public.set_updated_at();

create trigger set_updated_at_math_attempt
  before update on public.math_attempt
  for each row execute function public.set_updated_at();

create trigger set_updated_at_math_mastery
  before update on public.student_math_fact_mastery
  for each row execute function public.set_updated_at();
