# Math Facts Session RPCs

Supabase RPC endpoints that power the math facts trainer. All requests require an authenticated **student** session (`Authorization: Bearer <student JWT>`). Parents/admins may invoke these RPCs on behalf of a student via service-role tokens, but the functions enforce that `auth.uid()` matches the `math_session.student_id` they operate on.

Base path for RPC calls (local): `http://localhost:54321/rest/v1/rpc/<function_name>`.

---

## 1. `create_math_fact_session`
- **Method:** `POST /rest/v1/rpc/create_math_fact_session`
- **Body:**
```json
{
  "mode": "timed_test",                // enum: "learning" | "timed_test"
  "requested_duration_seconds": 180,    // positive integer
  "unit_requests": [
    { "unit_id": "<uuid addition_sum_upto_10>", "count": 50 },
    { "unit_id": "<uuid recent_misses_twice_7_days>", "count": 20 }
  ],
  "config": {                           // optional arbitrary metadata
    "flash_timeout_ms": 5000,
    "notes": "Evening practice"
  }
}
```
- **Validation:**
  - Caller must be authenticated (`auth.uid()` forms the `student_id`).
  - `requested_duration_seconds > 0`.
  - `unit_requests` is a non-empty array; each object needs a valid `unit_id` and positive `count`.
  - Each unit must be able to supply the requested number of facts. Static units use `math_fact_unit_member`; dynamic ones (e.g., "recent misses") are resolved via `rule_config` and the caller's recent attempts.
  - The session stores `min_answers_required = ceil(duration / 10)` to enforce the "≥1 answer per 10 seconds" rule.
- **Response:**
```json
{
  "session_id": "<uuid>",
  "mode": "timed_test",
  "requested_duration_seconds": 180,
  "min_answers_required": 18,
  "facts": [
    {
      "sequence": 1,
      "fact_id": "<uuid>",
      "unit_id": "<uuid addition_sum_upto_10>",
      "operation": "addition",
      "operand_a": 5,
      "operand_b": 4,
      "result_value": 9
    },
    {
      "sequence": 2,
      "fact_id": "<uuid>",
      "unit_id": "<uuid recent_misses_twice_7_days>",
      "operation": "multiplication",
      "operand_a": 7,
      "operand_b": 9,
      "result_value": 63
    }
  ]
}
```
- **Notes:**
  - The frontend must cache this payload locally; no further server calls are needed until the session completes.
  - The ordered fact list is also persisted in `math_session_fact` to validate submissions later.

### Supabase JS Example
```ts
const { data, error } = await supabase.rpc('create_math_fact_session', {
  mode: 'timed_test',
  requested_duration_seconds: 180,
  unit_requests: [
    { unit_id: additionUnitId, count: 50 },
    { unit_id: recentMissesUnitId, count: 20 }
  ],
  config: { flash_timeout_ms: 5000 }
});

if (error) throw error;
const session = data; // cache `session.facts` locally for offline use
```

## 2. `submit_math_fact_session_results`
- **Method:** `POST /rest/v1/rpc/submit_math_fact_session_results`
- **Body:**
```json
{
  "session_id": "<uuid>",
  "elapsed_ms": 175000,                  // actual time spent; used to log wasted time if session fails requirements
  "attempts": [
    {
      "sequence": 1,
      "fact_id": "<uuid>",
      "response_text": "9",
      "is_correct": true,
      "response_ms": 2300,
      "hint_used": false,
      "flashed_answer": false,
      "attempted_at": "2025-09-15T19:32:10Z"   // optional; defaults to request timestamp
    },
    {
      "sequence": 2,
      "fact_id": "<uuid>",
      "response_text": "60",
      "is_correct": false,
      "response_ms": 5200,
      "hint_used": false,
      "flashed_answer": true
    }
  ]
}
```
- **Validation:**
  - Caller must own the session (`math_session.student_id = auth.uid()` and `status = 'issued'`).
  - Every attempt must reference a fact/sequence that was part of the session bundle; mismatches raise an error.
  - Attempts array may be empty (e.g., immediate abort), but the session will then fail the minimum-answer requirement.
- **Server behavior:**
  - Upserts each attempt into `math_attempt` (allowing replays if connectivity hiccups) and invokes `update_math_fact_mastery` per fact.
  - Updates `math_session` summary fields (`answers_submitted`, `elapsed_ms`, `submitted_at`).
  - If `answers_submitted < min_answers_required`, marks the session as `discarded`, records `wasted_ms` (max of reported `elapsed_ms` and scheduled duration), and sets `counted = false` with `discarded_reason = 'min_answers_not_met'`.
  - Otherwise, marks the session `submitted`, keeps `wasted_ms = 0`, and `counted = true`.
- **Response:**
```json
{
  "session_id": "<uuid>",
  "answers_submitted": 70,
  "min_answers_required": 18,
  "counted": true,
  "status": "submitted",
  "wasted_ms": 0
}
```
- **Client expectations:**
  - Resend the full payload on reconnection; the RPC is idempotent per `session_fact_sequence`.
  - The frontend is responsible for enforcing per-question 5s timers and flashing behavior; only summary stats and correctness flow back to the backend.

### Supabase JS Example
```ts
const attempts = localFacts.map((fact, idx) => ({
  sequence: fact.sequence,
  fact_id: fact.fact_id,
  response_text: answers[idx].value,
  is_correct: answers[idx].isCorrect,
  response_ms: answers[idx].elapsed,
  hint_used: answers[idx].hintUsed,
  flashed_answer: answers[idx].flashed,
  attempted_at: answers[idx].timestamp
}));

const { data, error } = await supabase.rpc('submit_math_fact_session_results', {
  session_id: session.session_id,
  elapsed_ms: totalElapsedMs,
  attempts
});

if (error) throw error;
const summary = data; // contains status, wasted_ms, etc.
```

---

## 3. Helper Function Reference
- `resolve_math_fact_unit(unit_id uuid, student_id uuid)` — resolves static memberships or interprets `rule_config` (e.g., dynamic recent misses) to return fact IDs.
- `update_math_fact_mastery(student_id uuid, fact_id uuid, is_correct bool, response_ms int)` — maintains rolling accuracy, latency, streak, and mastery status per fact.

Frontends typically interact only with the two RPCs above, but understanding the helper functions clarifies how `rule_config`-driven units and mastery enforcement behave.
