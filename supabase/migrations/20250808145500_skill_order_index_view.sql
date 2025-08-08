-- Centralize skill -> order_index mapping

create or replace view public.skill_order_index as
select s.id as skill_id,
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
         else 999 end as order_index
from public.skills s;

-- Backfill using centralized mapping without overwriting explicit zeros
update public.books b
set title = coalesce(b.title, concat(l.label, ' — ', s.label))
from public.levels l
join public.skills s on s.id = b.category_id
where b.level_id = l.id
  and (b.title is null or b.title = '');

update public.books b
set order_index = soi.order_index
from public.skill_order_index soi
where b.category_id = soi.skill_id
  and b.order_index is null;

