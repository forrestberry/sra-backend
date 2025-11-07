# User-Facing API Endpoints

This document captures the current REST endpoints exposed to the frontend via Supabase's PostgREST API. All paths are relative to the Supabase REST base URL (`https://<project>.supabase.co/rest/v1`) and require the `apikey` and authenticated `Authorization: Bearer <JWT>` headers supplied by the Supabase client SDK. See `docs/api/README.md` for global conventions, role definitions, and testing expectations.

## Conventions
- Use the Supabase JS client whenever possible; its `from(table)` helpers generate the exact `GET /rest/v1/<table>` calls described below.
- Include a `select` querystring to project nested data (e.g., `?select=student(id,username)`).
- Pass `Prefer: return=representation` on writes when the frontend needs the inserted/updated row back.
- Row Level Security (RLS) confines the result set to the caller: parents only see their household, students only see their own data, and anonymous users only get read-only curriculum tables (`book`, `level`, `category`, `unit`, `question`).

---

## Parent Role (app_metadata.role = "parent")

### 1. Create/Link Parent Accounts
- **Sign up**: `POST /auth/v1/signup`
  - Metadata must include `"role": "parent"`.
  - To link a new parent to an existing household, include `"parent_id": "<existing-parent-uuid>"` which triggers `handle_new_user_profiles()` to populate `parent_parent_link`.
- **Invite additional parents**: reuse the same signup call but send the invite link or run via the Supabase Admin API from the parent management UI.

### 2. Fetch Parent Profile
- **GET `/rest/v1/parent?id=eq.<parent_id>`**
- Returns `id`, `display_name`, `created_at`, `updated_at` for the signed-in parent only (policy `parent can view self`).
```ts
const { data, error } = await supabase
  .from('parent')
  .select('id,display_name,created_at')
  .eq('id', userId)
  .single();
```

### 3. Update Display Name
- **PATCH `/rest/v1/parent?id=eq.<parent_id>`** with JSON `{ "display_name": "New Name" }`.
- Policy `parent can update self` restricts the mutation to the caller.

### 4. View Linked Parents
- **GET `/rest/v1/parent_parent_link?select=parent_id,linked_parent_id,created_at`**
- Result automatically includes both directions because of the symmetry trigger.

### 5. View Linked Students
- **GET `/rest/v1/parent_student_link?select=student(id,username,current_level_id)`**
- Parents only see rows where `parent_id = auth.uid()` thanks to `view_student_links`.

### 6. Retrieve Student Profiles
- **GET `/rest/v1/student?id=in.(<comma-separated-child-ids>)`**
- Policy `view_student` lets parents read child rows surfaced by `parent_student_link`.

### 7. Inspect Student Book Progress
- **GET `/rest/v1/student_book_progress?student_id=eq.<student_id>&select=book:book_id(title,level_id,category_id),units_completed,status`**
- Parents can only access progress rows tied to their linked students (`view_student_book_progress`).

### 8. Browse Curriculum Catalog
Read-only tables are open to `anon` and `authenticated`:
- **Levels**: `GET /rest/v1/level?select=id,name,sort_order&order=sort_order.asc`
- **Categories**: `GET /rest/v1/category?select=id,name,sort_order&order=sort_order.asc`
- **Books**: `GET /rest/v1/book?select=id,title,level_id,category_id,units_count&order=title.asc`
- **Units**: `GET /rest/v1/unit?select=id,book_id,unit_number,unit_text,unit_image_url&book_id=eq.<book_id>`
- **Questions**: `GET /rest/v1/question?select=id,unit_id,question_number,question_text,question_context,question_image_url,answer_key&unit_id=eq.<unit_id>`

### 9. Review Student Answers
- **GET `/rest/v1/answer?select=id,question_id,response_text,attempt_number,is_correct,submitted_at&student_id=eq.<student_id>`**
- RLS (`view_answers`) limits the rows to the parent's students.

### 10. Audit Parent/Student Relationships
- **GET `/rest/v1/parent_student_link?select=parent_id,student_id,created_at`**
- Useful when building admin/parent dashboards to confirm linkage propagation worked.

---

## Student Role (app_metadata.role = "student")

### 1. Student Account Creation
- Students are created via the Supabase Auth Admin API (`POST /auth/v1/admin/users`) by a parent-facing workflow.
- Required metadata: `"role": "student"`, `"username": "<student-handle>"`, `"parent_id": "<owning-parent-uuid>"`. The trigger `handle_new_user_profiles()` inserts the `student` row and links it to the parent.

### 2. Fetch Student Profile
- **GET `/rest/v1/student?id=eq.<student_id>`**
- Students only see themselves (`view_student` policy).

### 3. View Assigned Parents
- **GET `/rest/v1/parent_student_link?select=parent(id,display_name)`**
- Students see every linked parent row due to `view_student_links`.

### 4. Browse Curriculum Catalog
- Same read-only endpoints as parents (Levels, Categories, Books, Units, Questions). No special filtering is required because RLS grants universal `select` access.

### 5. Fetch Book Progress
- **GET `/rest/v1/student_book_progress?student_id=eq.<student_id>`**
- Students see all 90 rows (one per book) because `view_student_book_progress` permits `student_id = auth.uid()`.

### 6. Submit Answers
- **POST `/rest/v1/answer`** with JSON:
```json
{
  "student_id": "<student_id>",
  "question_id": "<question_uuid>",
  "response_text": "A",
  "attempt_number": 2,        // optional; defaults to 1 but must stay > 0
  "is_correct": false         // backend can set this after evaluation if desired
}
```
- Policy `student can submit answers` enforces `student_id = auth.uid()`.
- Use `Prefer: return=representation` to receive the inserted row (including `id`, `submitted_at`).

### 7. Review Own Answers
- **GET `/rest/v1/answer?student_id=eq.<student_id>`**
- Filter further by `question_id=eq.<uuid>` to show per-question history, or order via `order=submitted_at.desc`.

### 8. Retrieve Unit/Question Content
- Students rely on the same read-only catalog endpoints listed for parents to render assessments.

### 9. Track Current Level
- `student.current_level_id` can be read via `GET /rest/v1/student` and updated by privileged flows (no student update policy exists yet, so any promotion must run via service role).

---

## Verification Notes
- Every endpoint above is already guarded by explicit RLS in `supabase/migrations/20250809162325_initial_schema.sql` and covered (where applicable) in `supabase/tests/users_rls.test.sql`.
- No additional admin-specific endpoints are documented here; they will be tracked separately once implemented.
