-- Seed reference data with conflict safety

-- Levels
insert into public.levels (label, ordinal, code) values
  ('Picture Level', 0, 'picture'),
  ('Preparatory Level', 1, 'prep'),
  ('Level A', 2, 'A'),
  ('Level B', 3, 'B'),
  ('Level C', 4, 'C'),
  ('Level D', 5, 'D'),
  ('Level E', 6, 'E'),
  ('Level F', 7, 'F'),
  ('Level G', 8, 'G'),
  ('Level H', 9, 'H')
on conflict (code) do nothing;

-- Skills
insert into public.skills (label, code) values
  ('Working Within Words', 'working_within_words'),
  ('Following Directions', 'following_directions'),
  ('Using the Context', 'using_the_context'),
  ('Locating the Answer', 'locating_the_answer'),
  ('Getting the Facts', 'getting_the_facts'),
  ('Getting the Main Idea', 'getting_the_main_idea'),
  ('Drawing Conclusions', 'drawing_conclusions'),
  ('Detecting the Sequence', 'detecting_the_sequence'),
  ('Identifying Inferences', 'identifying_inferences')
on conflict (code) do nothing;

-- Books (Level × Skill) — ensure existence
-- Create unique index if missing (required for ON CONFLICT)
do $$ begin
  if not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'books_level_category_idx'
  ) then
    execute 'create unique index books_level_category_idx on public.books(level_id, category_id)';
  end if;
end $$;

insert into public.books (level_id, category_id, title, order_index, total_units)
select l.id, s.id,
       concat(l.label, ' — ', s.label) as title,
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
         else 999 end as order_index,
       0 as total_units
from public.levels l
cross join public.skills s
on conflict (level_id, category_id) do nothing;

-- Backfill titles and order_index if any rows are missing values
with skill_order as (
  select id as skill_id, code,
    case code
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
  from public.skills
)
update public.books b
set title = coalesce(b.title, concat(l.label, ' — ', s.label)),
    order_index = case when b.order_index is null or b.order_index = 0 then so.idx else b.order_index end
from public.levels l
join public.skills s on s.id = b.category_id
join skill_order so on so.skill_id = s.id
where b.level_id = l.id;
