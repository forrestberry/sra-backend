# Repository Guidelines

## Project Structure & Module Organization
- `supabase/functions/<function-name>/index.ts`: Edge Functions (Deno/TypeScript). Each function lives in its own kebab-case folder; `index.ts` is the entrypoint. Shared helpers live in `supabase/functions/*.ts` (e.g., `cors.ts`).
- `supabase/migrations/*.sql`: Database schema and seed SQL. Filenames are timestamped and ordered.
- `supabase/config.toml`: Local stack and function config.

## Build, Test, and Development Commands
- `supabase start`: Start local Postgres, Auth, Storage, and Functions.
- `supabase stop`: Stop the local stack.
- `supabase functions serve [<name>] --no-verify-jwt`: Serve all or one function locally (skip JWT check for local dev).
- `supabase functions deploy <name>`: Deploy a single function.
- `supabase migration new <name>`: Create a new migration file.
- `supabase db reset`: Recreate the local DB and apply migrations and seeds.
- `deno fmt supabase/functions`: Format TypeScript.
- `deno lint supabase/functions`: Lint TypeScript.

Example (local function call):
```
curl -i http://localhost:54321/functions/v1/get-children
```

## Coding Style & Naming Conventions
- TypeScript (Deno): 2-space indent, semicolons, single quotes. Prefer named exports.
- Function folders: kebab-case (e.g., `get-books-by-level`). Entrypoint is `index.ts`.
- SQL: lower_snake_case for tables/columns; keep migrations idempotent and reversible where possible.

## Testing Guidelines
- Unit tests: Deno `*_test.ts` colocated with code. Run with: `deno test --allow-env --allow-net supabase/functions`.
- Integration: Use `supabase functions serve` and `curl`/HTTP clients against `http://localhost:54321/functions/v1/<name>`.
- Aim for meaningful coverage on utility modules and request/response validation.

## Commit & Pull Request Guidelines
- Commits: Conventional Commits style (e.g., `feat: add get-children edge function`).
- PRs: concise description, linked issue, scope of change, manual test notes (example curl), and any schema changes (include migration file path).

## Security & Configuration Tips
- Do not commit secrets. Use `supabase secrets set KEY=VALUE` for deployed functions and a local `.env` with `supabase functions serve --env-file .env`.
- Use `--no-verify-jwt` only for local development; enforce JWT in non-local environments.

---

# Domain Workflow & Backend Design

## Parent/Child Workflow
- Auth: Parents authenticate via Supabase Auth (email/password or magic link).
- Children: Represented as rows owned by the parent (no separate child auth accounts initially).
- Flow:
  1) Parent logs in and creates child profiles.
  2) Parent assigns a level (Picture, Prep, A–H) per child.
  3) Parent switches to a child view in the UI (frontend passes a `child_id` along with requests).
  4) Child sees their level and available books (Level × Skill).
  5) Child selects a book and completes units (1–20 questions per unit).
  6) Backend grades a unit on submit and tracks book progress; after book completion, wrong answers are queued for redo.
  7) Child completes redo set, then advances to the next book; levels advance after all books in a level are finished.

## Proposed Data Model (SQL)
- `profiles` (parent): `id uuid pk` (auth.user), `display_name text`, `created_at timestamptz`.
- `children`: `id uuid pk`, `parent_id uuid fk -> profiles.id`, `name text`, `level_code text`, `created_at timestamptz`.
- `levels`: `code text pk` (e.g., `picture`, `prep`, `A`…`H`), `ordinal int`, `label text`.
- `skills`: `code text pk` (e.g., `working_within_words`, `following_directions`…), `label text`.
- `books`: `id uuid pk`, `level_code text fk -> levels.code`, `skill_code text fk -> skills.code`, `title text`, `order_index int`, `total_units int`.
- `units`: `id uuid pk`, `book_id uuid fk -> books.id`, `unit_index int`.
- `questions`: `id uuid pk`, `unit_id uuid fk -> units.id`, `question_index int`, `type text`, `prompt jsonb`, `options jsonb`, `answer_key jsonb`.
- `book_progress`: `child_id uuid fk`, `book_id uuid fk`, `status text` (`not_started|in_progress|redo|completed`), `started_at`, `completed_at`, `score numeric`, `primary key (child_id, book_id)`.
- `unit_attempts`: `id uuid pk`, `child_id uuid fk`, `unit_id uuid fk`, `started_at`, `completed_at`, `correct_count int`, `total_count int`.
- `responses`: `id uuid pk`, `attempt_id uuid fk -> unit_attempts.id`, `question_id uuid fk`, `answer jsonb`, `correct boolean`.

Notes
- Use RLS on child-owned tables to restrict access to `auth.uid() = parent_id` via a join to `profiles`.
- Seed `levels` and `skills`; derive `books` from Level × Skill with consistent ordering.

## API Surface (Edge Functions)
- `GET /children`: List children for the authenticated parent.
- `POST /children`: Create child `{ name, level_code }`.
- `PATCH /children/:id`: Update child `{ name?, level_code? }`.
- `GET /levels`: Return all levels and ordinals.
- `GET /skills`: Return all skill categories.
- `GET /books?level=CODE`: List books for a level (ordered).
- `GET /books/:id`: Book detail + basic progress for current child.
- `GET /units?book_id=...`: List units within a book.
- `GET /questions?unit_id=...`: Fetch questions for a unit (omit answer_key for clients).
- `POST /responses`: Submit a unit’s answers `{ child_id, unit_id, questions: [...] }`; returns graded results and updates progress.
- `POST /books/:id/grade`: Grade/refresh a book summary (idempotent) from latest attempts.
- `GET /progress/child/:id`: Summary across books and levels.

Auth & Context
- Parent session only. The frontend sends an explicit `child_id` header or body param; Edge Functions validate that `child_id` belongs to `auth.uid()` before proceeding.

## Grading Flow
- Unit grading: For each submitted question, compare `answer` vs `answer_key` by type. Store per-question result and attempt summary (correct/total).
- Book grading: Aggregate the latest completed attempt per unit to compute book score and status. Transition status: `not_started -> in_progress -> redo? -> completed`.
- Redo set: Questions marked incorrect in the latest attempt are returned in the response and can be re-attempted until correct.

## Local Development (Backend)
- Start stack: `supabase start`
- Reset DB: `supabase db reset` (applies migrations and seeds)
- Serve functions: `supabase functions serve --no-verify-jwt`
- Example call: `curl -i http://localhost:54321/functions/v1/get-children`

## Open Questions / Decisions
- Child auth: Keep children as non-auth rows tied to parent for now; revisit separate child accounts only if needed.
- Content source: Ground-truth questions/answers come from curated assets; ingestion pipeline TBD (manual seed vs. import script).
- Progress rules: Define minimum correct threshold per book or rely on “all questions eventually correct”.

---

# API Contracts (Examples)

Headers
- `Authorization: Bearer <JWT>` (parent session required)
- `X-Child-Id: <child_uuid>` for child-scoped routes (preferred over body field)

Errors
- On error, respond with `4xx/5xx` and body: `{ "error": { "code": "string", "message": "string" } }`

GET /children
- Purpose: List children owned by the authenticated parent.
- curl:
```
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:54321/functions/v1/children
```
- 200 response:
```json
[
  { "id": "d1...", "name": "Ava", "level_code": "C", "created_at": "2025-08-01T12:00:00Z" },
  { "id": "e2...", "name": "Max", "level_code": "prep", "created_at": "2025-08-02T10:00:00Z" }
]
```

POST /children
- Purpose: Create a child profile.
- Request body:
```json
{ "name": "Ava", "level_code": "B" }
```
- 201 response:
```json
{ "id": "d1...", "name": "Ava", "level_code": "B", "created_at": "2025-08-01T12:00:00Z" }
```

PATCH /children/:id
- Purpose: Update child name and/or level.
- Request body (partial):
```json
{ "level_code": "C" }
```
- 200 response:
```json
{ "id": "d1...", "name": "Ava", "level_code": "C" }
```

GET /levels
- Purpose: Retrieve ordered levels.
- 200 response:
```json
[
  { "code": "picture", "ordinal": 0, "label": "Picture Level" },
  { "code": "prep", "ordinal": 1, "label": "Preparatory Level" },
  { "code": "A", "ordinal": 2, "label": "Level A" }
]
```

GET /skills
- Purpose: Retrieve skill categories.
- 200 response:
```json
[
  { "code": "working_within_words", "label": "Working Within Words" },
  { "code": "following_directions", "label": "Following Directions" }
]
```

GET /books?level=CODE
- Purpose: List books available for a level.
- Example: `/books?level=C`
- 200 response:
```json
[
  {
    "id": "b1...",
    "level_code": "C",
    "skill_code": "following_directions",
    "title": "Level C — Following Directions",
    "order_index": 2,
    "total_units": 40
  }
]
```

GET /books/:id
- Purpose: Book detail plus current child progress.
- Requires `X-Child-Id`.
- 200 response:
```json
{
  "book": {
    "id": "b1...",
    "level_code": "C",
    "skill_code": "following_directions",
    "title": "Level C — Following Directions",
    "total_units": 40
  },
  "progress": {
    "status": "in_progress",
    "score": 0.82,
    "started_at": "2025-08-03T10:00:00Z",
    "completed_at": null
  }
}
```

GET /units?book_id=...
- Purpose: List units for a book.
- 200 response:
```json
[
  { "id": "u1...", "unit_index": 1 },
  { "id": "u2...", "unit_index": 2 }
]
```

GET /questions?unit_id=...
- Purpose: Retrieve questions for a unit (no answer_key to clients).
- 200 response:
```json
{
  "unit": { "id": "u1...", "unit_index": 1 },
  "questions": [
    {
      "id": "q1...",
      "question_index": 1,
      "type": "multiple_choice",
      "prompt": { "text": "Choose the correct word" },
      "options": ["fits", "fit", "fitting", "fitted"]
    },
    {
      "id": "q2...",
      "question_index": 2,
      "type": "true_false",
      "prompt": { "text": "The cat is an animal." }
    },
    {
      "id": "q3...",
      "question_index": 3,
      "type": "short_answer",
      "prompt": { "text": "Write the main idea in 1 sentence." }
    }
  ]
}
```

POST /responses
- Purpose: Submit answers for grading and record an attempt.
- Requires `X-Child-Id`.
- Request body:
```json
{
  "unit_id": "u1...",
  "answers": [
    { "question_id": "q1...", "answer": "fits" },
    { "question_id": "q2...", "answer": true },
    { "question_id": "q3...", "answer": "The story is about teamwork." }
  ]
}
```
- 200 response:
```json
{
  "attempt_id": "a1...",
  "summary": { "correct": 2, "total": 3, "score": 0.6667 },
  "results": [
    { "question_id": "q1...", "correct": true },
    { "question_id": "q2...", "correct": true },
    { "question_id": "q3...", "correct": false }
  ],
  "redo": [
    { "question_id": "q3..." }
  ],
  "book_status": { "book_id": "b1...", "status": "redo", "score": 0.82 }
}
```

POST /books/:id/grade
- Purpose: Recompute a book’s aggregate from latest attempts (idempotent).
- 200 response:
```json
{ "book_id": "b1...", "status": "in_progress", "score": 0.82 }
```

GET /progress/child/:id
- Purpose: Overview across levels/books for dashboard.
- 200 response:
```json
{
  "child": { "id": "d1...", "name": "Ava", "level_code": "C" },
  "levels": [
    {
      "code": "C",
      "books": [
        { "book_id": "b1...", "skill_code": "following_directions", "status": "redo", "score": 0.82 },
        { "book_id": "b2...", "skill_code": "getting_the_facts", "status": "not_started", "score": null }
      ]
    }
  ]
}
```
