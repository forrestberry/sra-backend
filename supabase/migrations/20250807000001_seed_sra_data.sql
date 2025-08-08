
-- Insert SRA Levels
INSERT INTO sra_levels (name, level_order) VALUES
('Picture Level', 1),
('Preparatory Level', 2),
('Level A', 3),
('Level B', 4),
('Level C', 5),
('Level D', 6),
('Level E', 7),
('Level F', 8),
('Level G', 9),
('Level H', 10);

-- Insert SRA Categories
INSERT INTO sra_categories (name) VALUES
('Working Within Words'),
('Following Directions'),
('Using the Context'),
('Locating the Answer'),
('Getting the Facts'),
('Getting the Main Idea'),
('Drawing Conclusions'),
('Detecting the Sequence'),
('Identifying Inferences');

-- Insert SRA Books
INSERT INTO sra_books (level_id, category_id)
SELECT l.id, c.id
FROM sra_levels l, sra_categories c;
