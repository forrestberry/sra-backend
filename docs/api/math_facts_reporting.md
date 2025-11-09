# Math Facts Reporting RPCs

Read-only RPCs for dashboards and practice builders. All calls require an authenticated session. Students can see their own data; parents see linked students; admins can access any student.

## `get_student_math_fact_mastery`
- **URL:** `POST /rest/v1/rpc/get_student_math_fact_mastery`
- **Body fields:**
  - `student_id` (optional) – defaults to caller; required when parent/admin fetches another student.
  - `unit_id` (optional) – limit output to facts that belong to a specific fact unit/playlist.
  - `limit` / `offset` (optional) – pagination, default `100/0`.
- **Response:** array of mastery rows: fact operands, operation, result, mastery `status`, rolling accuracy, avg response ms, attempts count, streak, `last_attempt_at`.
- **Usage:**
```ts
const { data, error } = await supabase.rpc('get_student_math_fact_mastery', {
  student_id: childId,
  unit_id: additionUnitId,
  limit: 50
});
```
Use this to populate mastery dashboards and show the next gaps (facts still in `training` or `needs_review`).

## `get_student_math_fact_recent_misses`
- **URL:** `POST /rest/v1/rpc/get_student_math_fact_recent_misses`
- **Body fields:**
  - `student_id` (optional) – defaults to caller.
  - `lookback_days` (default 7) – rolling window for consideration.
  - `min_misses` (default 2) – threshold for including a fact.
- **Response:** array ordered by `last_missed_at` with operands, operation, miss count, and timestamp for the last miss.
- **Usage:**
```ts
const { data, error } = await supabase.rpc('get_student_math_fact_recent_misses', {
  student_id: childId,
  lookback_days: 7,
  min_misses: 2
});
```
Use this payload to focus future sessions on trouble facts (e.g., feed into `unit_requests`).

## Access Rules
- Students: can only request their own data by omitting `student_id`.
- Parents: pass `student_id` for any linked child; RLS rejects other students.
- Admins: pass any `student_id` (useful for support dashboards).

Frontends should cache mastery results locally to power heatmaps and streak indicators. Pair these RPCs with `create_math_fact_session` / `submit_math_fact_session_results` so students see updated mastery immediately after finishing a session.
