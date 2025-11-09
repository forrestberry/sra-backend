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

## 4. Math Facts Trainer Implementation
1. **Schema & ERD updates**: add `facts`, `fact_units`, `fact_unit_members`, `student_fact_assignments`, `math_sessions`, `math_session_facts`, `math_attempts`, and `student_fact_mastery` tables plus supporting indexes; refresh both `docs/erd_diagram.md` (core) and `docs/erd_math_facts.md` (math facts) and generate migrations; include columns to track session wasted time and answers-per-10s validation.
2. **Fact library seeding**: ✅ base arithmetic facts (0–15 operands) are seeded via `20250915123000_math_facts_seed_data.sql`, and baseline units/dynamic placeholders (addition sums ≤10, 2× table >10, "missed twice in 7 days") are provisioned in `20250915124500_math_fact_units_seed.sql`; next up is wiring a unit resolver that can interpret `rule_config` when generating sessions and providing admin tooling for custom units.
3. **Session bundle API**: ✅ `create_math_fact_session` RPC now validates unit requests, resolves facts (including dynamic units), persists `math_session`/`math_session_fact`, and returns the ordered payload. Follow-up: add pgTAP coverage + frontend wiring.
4. **Result ingestion API**: ✅ `submit_math_fact_session_results` ingests batched attempts, enforces the "≥1 answer per 10 seconds" rule, logs wasted time for discarded sessions, and updates mastery. Follow-up: add automated tests plus telemetry/dashboard queries.
5. **Mastery + recommendations**: `update_math_fact_mastery` enforces the 95% accuracy & <2s latency rule, and the read-side RPCs `get_student_math_fact_mastery` / `get_student_math_fact_recent_misses` now expose those metrics to the frontend. Follow-up: layer higher-level recommendations (e.g., auto playlist suggestions) and parent/admin dashboards on top of these RPCs.
6. **Reporting & docs**: expose read APIs for mastery dashboards and recent misses, update `/docs/api` with contracts for the new endpoints, and extend automated tests covering selection logic, wasted-time logging, result ingestion, and RLS.
