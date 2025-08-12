# Curriculum Data (Static)

This application uses a fixed set of Levels, Categories, and Books based on the SRA Specific Skills series. These values are seeded via a migration and are intended to be immutable.

## Levels (order)
1. Picture
2. Preparatory
3. A
4. B
5. C
6. D
7. E
8. F
9. G
10. H

## Categories (order)
1. Working Within Words
2. Following Directions
3. Using the Context
4. Locating the Answer
5. Getting the Facts
6. Getting the Main Idea
7. Drawing Conclusions
8. Detecting the Sequence
9. Identifying Inferences

## Books
- Constructed as all combinations of Level x Category (10 x 9 = 90 books).
- Title format: "<Level> - <Category>" (e.g., "C - Working Within Words").
- `units_count` is currently set to `0` for all books and will be updated in a later migration when unit counts are finalized.

