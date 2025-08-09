-- Seed data for local development
-- Keep minimal and deterministic. Extend as needed.

begin;

-- Example Levels (uncomment and adjust if desired)
-- insert into public.level (id, name, sort_order) values
--   (extensions.gen_random_uuid(), 'Level 1', 1),
--   (extensions.gen_random_uuid(), 'Level 2', 2)
-- on conflict (name) do update set sort_order = excluded.sort_order;

-- Example Categories
-- insert into public.category (id, name, sort_order) values
--   (extensions.gen_random_uuid(), 'Fiction', 1),
--   (extensions.gen_random_uuid(), 'Nonfiction', 2)
-- on conflict (name) do update set sort_order = excluded.sort_order;

commit;
