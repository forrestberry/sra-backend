


-- Create a table for public profiles
create table parents (
  id uuid references auth.users on delete cascade not null primary key,
  email varchar(255) not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Set up Row Level Security (RLS)
-- See https://supabase.com/docs/guides/auth/row-level-security
alter table parents
  enable row level security;

create policy "Public profiles are viewable by everyone." on parents
  for select using (true);

create policy "Users can insert their own profile." on parents
  for insert with check (auth.uid() = id);

create policy "Users can update own profile." on parents
  for update using (auth.uid() = id);

-- Create a table for SRA levels
create table sra_levels (
  id serial primary key,
  name varchar(255) not null,
  level_order int not null
);

-- Create a table for SRA categories
create table sra_categories (
  id serial primary key,
  name varchar(255) not null
);

-- Create a table for SRA books
create table sra_books (
  id serial primary key,
  level_id int references sra_levels(id) not null,
  category_id int references sra_categories(id) not null
);

-- Create a table for children
create table children (
  id uuid default gen_random_uuid() primary key,
  parent_id uuid references parents(id) on delete cascade not null,
  name varchar(255) not null,
  current_level_id int references sra_levels(id),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table children
  enable row level security;

create policy "Children are viewable by their parent." on children
  for select using (auth.uid() = parent_id);

create policy "Parents can insert their own children." on children
  for insert with check (auth.uid() = parent_id);

create policy "Parents can update their own children." on children
  for update using (auth.uid() = parent_id);

-- Create a table for units
create table units (
  id serial primary key,
  book_id int references sra_books(id) not null,
  unit_number int not null
);

-- Create a table for questions
create table questions (
  id serial primary key,
  unit_id int references units(id) not null,
  question_number int not null,
  correct_answer varchar(255) not null
);

-- Create a table for answers
create table answers (
  id serial primary key,
  question_id int references questions(id) not null,
  child_id uuid references children(id) on delete cascade not null,
  answer text not null,
  is_correct boolean not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table answers
  enable row level security;

create policy "Answers are viewable by the child's parent." on answers
  for select using (auth.uid() = (select parent_id from children where id = child_id));

create policy "Children can insert their own answers." on answers
  for insert with check (auth.uid() = (select parent_id from children where id = child_id));

-- Create a table for unit grades
create table unit_grades (
  id serial primary key,
  unit_id int references units(id) not null,
  child_id uuid references children(id) on delete cascade not null,
  score float not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table unit_grades
  enable row level security;

create policy "Unit grades are viewable by the child's parent." on unit_grades
  for select using (auth.uid() = (select parent_id from children where id = child_id));
