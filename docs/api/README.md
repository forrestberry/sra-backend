# API Documentation Guide

This guide is the single entry point for every frontend consumer of the SRA backend (web app, admin tooling, scripts). It explains the authentication model, naming conventions, and links to the per-role endpoint catalogs.

## 1. Authentication + Headers
- **Base URL (local)**: `http://localhost:54321/rest/v1`
- **Base URL (prod)**: `https://<project>.supabase.co/rest/v1`
- Required headers for REST calls:
  - `apikey: <anon_or_service_key>`
  - `Authorization: Bearer <JWT>` (use Supabase client session token)
  - `Content-Type: application/json` on writes
  - `Prefer: return=representation` when the caller needs the affected rows returned
- Supabase JS handles these automatically once `supabase.createClient(url, anonKey)` is configured.

## 2. Roles & RLS Overview
| Role     | How it authenticates | What it can do today | Notes |
|----------|----------------------|----------------------|-------|
| `parent` | Supabase Auth signup/login with `"role":"parent"` metadata | Manage own profile, view linked parents/students, read curriculum, read linked student progress/answers | Updates to student data must go through service role for now |
| `student`| Supabase Auth admin-created account with `"role":"student"` metadata | Read own profile, view parents, browse curriculum, submit answers, view own answers/progress | Cannot mutate `student` or `student_book_progress` rows |
| `admin`  | Supabase Auth account with `"role":"admin"` metadata | (Future) Content management via edge functions or studio | Current schema only uses admin role inside row policies for `unit` and `question` writes |

RLS definitions live in `supabase/migrations/*_initial_schema.sql` and are enforced regardless of the client.

## 3. Endpoint Catalogs
- **Parents & Students**: See `docs/api/user_endpoints.md` for detailed request/response information, Supabase client examples, and coverage notes.
- **Admins**: Not yet exposed via dedicated endpoints. Content authors should use Supabase Studio or run SQL directly until we implement the edge functions described in TODO item 2.

When adding new endpoints:
1. Update the relevant per-role doc (or create `docs/api/admin_endpoints.md`).
2. Link to it here so frontend consumers know where to look.
3. Extend `supabase/tests/*.sql` to cover the new behavior.

## 4. Common Query Patterns
- **Column filtering**: `?select=id,title` to keep payloads light.
- **Ordering**: `?order=sort_order.asc` (can specify multiple `order` params).
- **Pagination**: Use `Range-Unit: items` headers (`Range: 0-24`) or Supabase JS `range(from, to)`.
- **Filtering**: `eq`, `neq`, `in`, `ilike`, etc. Example: `?student_id=eq.<uuid>`.
- **Foreign key expansion**: `?select=book:book_id(id,title)` returns joined book data.

## 5. Error Handling
- Supabase REST surfaces PostgREST error payloads (`{ "message": "...", "details": "...", "hint": "...", "code": "xxxxx" }`).
- 401/403 usually indicates missing/expired JWT or RLS denial—log the `code`/`details` and show a user-friendly message.
- Validation errors (e.g., constraint violations) return 400 with a descriptive `message`.

## 6. Testing Expectations
- For each documented endpoint, there should be a matching pgTAP or edge-function test verifying role-based access (see `supabase/tests/users_rls.test.sql` for patterns).
- New endpoints must ship with:
  - Schema/RLS migrations if needed.
  - Tests proving the intended roles can/cannot perform the action.
  - Documentation updates (this README + per-role spec).

## 7. Definition of Done Checklist
1. Endpoint implemented (SQL/Table, RPC, or Edge Function).
2. RLS policies updated and tested.
3. Documentation updated:
   - Overview (this file) references the endpoint group.
   - Detailed spec (per-role file) includes payloads and sample code.
4. Frontend consumers notified of the change (link to PR/commit).

Keeping this structure up to date ensures frontend work can proceed without waiting for backend clarifications. Whenever you add or change an endpoint, start the review by updating the docs—code reviewers will expect it.
