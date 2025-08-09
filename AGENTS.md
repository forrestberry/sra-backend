# Backend Development Guide

This guide outlines the development workflow, documentation requirements, and conventions for the backend of the SRA Web App.

## Project Context

-- See [README.md](./README.md) for full project background and functional details.
- **Platform:** [Supabase](https://supabase.com) (Postgres-based backend with auth, database, and edge functions)
- **Database:** PostgreSQL
    - The **Entity Relationship Diagram (ERD)** is located in [`/docs`](./docs/erd_diagram.md) — it **must** be updated before any schema changes are made.
- **Auth:** Supabase Auth (JWT-based)
- **API:** Supabase-generated APIs + custom edge functions

## Development Workflow

### 1. Worktree Management

- Always work in a **separate git worktree** for each feature or bugfix.
- **Naming convention:**
    `backend-[feature|hotfix]-<short-description>`
    - Examples:
        - `git worktree add ../backend-feature-auth-add-magiclinks`
        - `git worktree add ../backend-hotfix-workinginwords-unit-renumbering`

### 2. Commit Practices
- Keep commits atomic (one logical change per commit).
- Write clear, descriptive commit messages.

### 3. Documentation Requirements

- In-code comments: Keep them clear and up to date.
- /docs folder:
    - Every API call used by the frontend must have an API contract documented here.
        - This includes built-in Supabase API endpoints that the frontend is expected to use.
        - Use OpenAPI spec for consistent formatting for API contracts
    - ERD diagram must always reflect the current schema.

## Auth
- Use the built-in Supabase Auth.
- Follow the Supabase Auth guide for configuration details.
- Store any role, claim, or metadata conventions in /docs for reference.
