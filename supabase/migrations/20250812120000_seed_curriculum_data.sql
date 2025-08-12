-- Seed static curriculum data: levels, categories, and books
-- This data is canonical and should not change.

begin;

-- Upsert Levels (10)
insert into public.level (name, sort_order) values
  ('Picture', 1),
  ('Preparatory', 2),
  ('A', 3),
  ('B', 4),
  ('C', 5),
  ('D', 6),
  ('E', 7),
  ('F', 8),
  ('G', 9),
  ('H', 10)
on conflict (name) do update set sort_order = excluded.sort_order;

-- Upsert Categories (9)
insert into public.category (name, sort_order) values
  ('Working Within Words', 1),
  ('Following Directions', 2),
  ('Using the Context', 3),
  ('Locating the Answer', 4),
  ('Getting the Facts', 5),
  ('Getting the Main Idea', 6),
  ('Drawing Conclusions', 7),
  ('Detecting the Sequence', 8),
  ('Identifying Inferences', 9)
on conflict (name) do update set sort_order = excluded.sort_order;

-- Insert Books (90) = 10 levels x 9 categories
-- Title format: "<Level> - <Category>"
with lv as (
  select id, name from public.level
  where name in ('Picture','Preparatory','A','B','C','D','E','F','G','H')
), cat as (
  select id, name from public.category
  where name in (
    'Working Within Words','Following Directions','Using the Context','Locating the Answer',
    'Getting the Facts','Getting the Main Idea','Drawing Conclusions','Detecting the Sequence','Identifying Inferences'
  )
), pairs as (
  select lv.id as level_id,
         cat.id as category_id,
         (lv.name || ' - ' || cat.name) as title
  from lv cross join cat
)
insert into public.book (level_id, category_id, title, units_count)
select p.level_id, p.category_id, p.title, 0
from pairs p
where not exists (
  select 1 from public.book b
  where b.level_id = p.level_id and b.category_id = p.category_id
);

commit;
