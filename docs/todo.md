# Backend TODOs

## 1. Add Admin-Endorsed Content Management Endpoints
1. Implement Supabase Edge Functions that require `app_metadata.role = 'admin'` (or service-role key) so admins can manage book content without touching SQL directly.
2. Primary bulk endpoint: given a book ID plus structured payload (units -> questions -> answer keys), create or update the entire book in a single transaction, keeping `units_count` and related triggers in sync.
3. Decide how reruns behave (append vs. replace) and ensure idempotent upserts so partial failures can be retried safely.
4. Provide dedicated endpoints for attaching unit-level images and question-level images; define whether the payload includes signed storage URLs or raw uploads and set storage bucket policies accordingly.
5. Extend `supabase/tests/users_rls.test.sql` (or new pgTAP suites) to prove only admins can call these functions while parents/students stay read-only.
6. Document the new admin APIs in `docs/api` and update the ERD/README if additional columns or storage references are introduced.

## 2. Backfill Curriculum Metadata
1. Gather the canonical unit counts for all 90 books and update both `docs/curriculum.md` and the seed/migration data (`supabase/migrations/20250812120000_seed_curriculum_data.sql`).
2. Once counts are known, seed placeholder `unit` rows (or at least metadata) so progress metrics have concrete targets and the admin tools can edit real records.
3. Update the `student_book_progress` creation trigger to handle retroactive additions (existing students should receive rows for any new books/units).
4. Add tests ensuring the seed data matches the documented curriculum to catch regressions.

## 3. Plan the Question/Answer Content Import Pipeline
1. Decide on the source-of-truth format for question text, answer keys, and associated assets (CSV, JSON, manual entry, etc.).
2. Create a repeatable script (e.g., in `scripts/`) that ingests the source data via the admin edge functions instead of direct SQL so validation, RLS, and triggers all run consistently.
3. Build validation/reporting into the script: detect duplicate unit/question numbers, missing answer keys, or broken image references before writing to the database.
4. Document the pipeline (inputs, command usage, troubleshooting) in `/docs` so future content imports stay consistent.
