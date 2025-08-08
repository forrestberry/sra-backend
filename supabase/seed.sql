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

