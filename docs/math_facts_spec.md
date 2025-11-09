# Math Facts Trainer Specification

## 1. Product Goals
- Help students master granular arithmetic facts (addition, subtraction, multiplication, division) through structured learning and testing workflows.
- Target sustained fluency of **≥100 correct answers in 3 minutes**.
- Enforce a **5-second max latency** per prompt; flash the answer when time elapses to prevent idle time.
- Track mastery at both the individual fact level (e.g., `7×9`) and across logical groupings ("addition sums ≤ 10", "2× table products > 10", "facts missed twice in 7 days").

## 2. User Experience Overview
### 2.1 Modes
- **Learning Mode**: paced introduction with hints, slower overall timers, spaced repetition to gradually expand fact sets.
- **Timed Test Mode**: rapid-fire, default 3-minute session aiming for 100+ correct responses, strict 5-second per-fact enforcement.

### 2.2 Fact Collections & Assignments
- Support curated **fact families** and **custom logical units** defined by operand, operator, and rule constraints (e.g., addition sums ≤ 10, multiplication table of 2 with products > 10).
- Allow dynamic groupings, such as "facts missed ≥2 times in the last 7 days" or "not-yet-mastered facts".
- Parents/admins assemble playlists that mix fixed units and dynamic collections per student; reusable shared templates are not required for v1.

### 2.3 Session Flow (Offline-Friendly)
1. Frontend requests a session bundle from the backend, specifying student, mode, and fact collection mix.
2. Backend responds with the **full set of prompts** (fact IDs plus operands/operator) and configuration data (timers, hint policy, goal counts). No streaming/next endpoints are needed.
3. Frontend runs the entire session locally, enforcing timers and flashing answers at 5 seconds.
4. When the session completes (or recovers after a loss of connectivity), the frontend submits **one payload** with every attempt (fact ID, correctness, response time, hint/flash flags, timestamps).
5. Backend verifies facts belong to the issued session, records attempts, updates mastery, and returns session stats.
6. Partial sessions (e.g., app quit mid-test) never count toward mastery goals but must report elapsed time so the backend can track "time wasted"; enforce policy that at least 1 answer is logged per 10 seconds of configured test time or the session is fully discarded.

## 3. Frontend Feature Requirements
- Session builder UI to choose student, mode, duration, unit mix, and special filters ("focus on recent misses").
- Learning Mode view with hints/manipulatives, per-question and total timers, optional coaching text.
- Timed Test view with large prompt, on-screen keypad, progress meter toward 100 correct, and visual 5-second countdown.
- Feedback overlays for incorrect answers or flashed answers; optional immediate re-queue.
- Progress dashboards: heatmaps showing mastery by operator/fact, recent misses, recommended next units.
- Admin screens to define fact units, playlists, and review attempt logs.
- Accessibility: keyboard-first flow, large fonts, color-blind friendly cues.

## 4. Backend Feature Requirements
### 4.1 Domain Model
- `facts`: canonical arithmetic facts (`operand_a`, `operand_b`, `operation`, difficulty metadata).
- `fact_units`: named groupings with descriptive metadata and rule definitions.
- `fact_unit_members`: explicit fact-to-unit membership for rule-based and curated sets.
- `student_fact_assignments`: tracks which units/facts are currently active for a student.
- `math_sessions`: session configs (mode, timers, requested units, issued fact list hash).
- `math_session_facts`: per-session ordered queue of facts issued to the frontend, preserving metadata for validation.
- `math_attempts`: per-fact attempt logs with correctness, response ms, hint/flash flags.
- `student_fact_mastery`: rolling metrics (streaks, accuracy, avg latency, last-miss timestamp).

### 4.2 APIs (Supabase RPC + future Edge Functions)
- `rpc/create_math_fact_session` (**implemented**): payload `{ mode, requested_duration_seconds, unit_requests: [{ unit_id, count }], config? }`. Returns `{ session_id, mode, requested_duration_seconds, min_answers_required, facts: [{ sequence, fact_id, unit_id, operation, operand_a, operand_b, result_value }] }`. Enforces the ≥1 answer/10s rule up front and stores the issued fact order in `math_session_fact`.
- `rpc/submit_math_fact_session_results` (**implemented**): payload `{ session_id, attempts: [{ sequence, fact_id, response_text, is_correct, response_ms, hint_used, flashed_answer, attempted_at? }], elapsed_ms }`. Validates that every attempt belongs to the issued session, upserts attempts, updates mastery, and enforces the "min answers" requirement—sessions that fall short flip to `discarded` with `wasted_ms` recorded.
- CRUD endpoints for `fact_units` and playlists (admin-only) to create curated mixes and constraint-based units (future Edge Functions will back these operations, using the resolver below).
- `GET /students/{id}/math-facts/mastery`: aggregated mastery plus recommended next units/facts (requires future read endpoints).
- `GET /math-facts/reports/missed`: parameterized query for "facts missed ≥N times in last X days", to support playlist builders.

### 4.3 Business Logic
- **Fact Selection Engine**: implemented via `resolve_math_fact_unit(unit_id, student_id)` plus `create_math_fact_session`, which interprets `rule_config` for dynamic/static filters, resolves fact queues, deduplicates per unit, and stores the ordered sequence.
- **Timer/Integrity Enforcement**: `submit_math_fact_session_results` compares attempts to the issued queue, enforces the "≥1 answer per 10 seconds" rule, marks underperforming sessions as discarded, and records `wasted_ms` for auditing.
- **Mastery Updater**: `update_math_fact_mastery` maintains rolling accuracy, latency, streaks, and `status` (`training` → `mastered` → `needs_review`) per fact/student whenever attempts are ingested.
- **Recommendation Service**: (next) surfaces next-best facts/units by analyzing gaps (e.g., only `7×9` missing in the 7s table) using mastery data + recent attempts.
- **Analytics & Alerts**: flag repeated timeouts (answer flashes), aborted sessions, or prolonged accuracy dips (future dashboards can query `math_session` + `math_attempt`).

### 4.4 Data Retention & Performance
- Keep attempt history for at least **one year** with indexes on `(student_id, fact_id, attempted_at)`.
- Support archival/cleanup policies to control table growth.
- RLS policies enforce: students can only view their own sessions/attempts; admins/parents have scoped access per configuration.

## 5. Reporting & Telemetry
- Session summaries: total attempts, correct count, average response time, number of flashed answers, accuracy by unit.
- Mastery heatmaps per student/class to feed dashboards.
- Export endpoints for admins to download attempt logs.
- Metrics for product analytics (session completion rate, average correct/minute, facts mastered per week).

## 6. Decision Log
1. Attempt history retained for **one year** before archival/cleanup.
2. Mastery threshold: rolling ≥95% accuracy **and** average latency <2s per fact; dropping below either metric removes mastery.
3. Partial sessions never count, but their elapsed time is logged as "time wasted" if the answers-per-10-seconds rule fails.
4. Playlists/assignments are managed per student; shared templates are out of scope for v1.

Document last updated: <!-- date to be filled automatically by git history -->
