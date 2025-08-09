# SRA Web App Backend

The SRA Web App is a tool designed to help students work independently through the *SRA Specific Skills* book series, providing timely feedback and tracking progress.

**Mission**: Enable students to complete all of the SRA Specific Skills books at their own pace, receiving timely feedback so that they can progress as quickly as their ability allows.

## About the SRA Book Series

There are 90 books in the SRA Specific Skills Series. Each book is made up of the level and the skill (e.g. C - Working Within Words). Each book is made up of multiple units (usually 25-50). Each unit is made up of questions (anywhere from 1 to 20).

There are 10 levels:
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

Each Level has 9 categories:
1. Working Within Words
2. Following Directions
3. Using the Context
4. Locating the Answer
5. Getting the Facts
6. Getting the Main Idea
7. Drawing Conclusions
8. Detecting the Sequence
9. Identifying Inferences


## App Workflow

1. **Parent** creates account.
2. *(Optional)* Add additional parent accounts.
3. **Parent** adds student(s) with username and password.
4. *(Optional)* Parent marks books the student has already completed.
5. **Student** logs in.
6. *(Optional)* Student changes password.
7. Student selects an available book in their **current level**.
8. Student answers questions in the unit.
9. After completing **5 units**, the student:
    - Receives feedback on incorrect answers from those units.
    - Retakes incorrect questions until correct.
10. Repeat until the book is complete.
11. Repeat until all books are complete.

**Note:**
- The "5 units" checkpoint is configurable.

## About the SRA Web App

The SRA Web App is a light-weight frontend that relies on a robust backend. The backend comprises of auth, a database, and APIs.

The basic flow is:
- Parent creates account.
- Optional: Parent adds additional parent accounds.
- Parent adds student(s) (including setup of username and password).
- Optional: Parent marks books that each student has already completed.
- Student logs in with credentials provided by parent.
- Optional: Student can change password.
- Student selects an available book in the current level.
- Student answers the questions in the unit.
- Student completes 5 units in the book.
- Student receives feedback on incorrection answers from the past 5 units.
- Student answers the incorrect questions again until they are right.
- Student repeats until the book is completed.
- Student repeats until every book is completed.

## Backend Tech Stack

- **Platform:** [Supabase](https://supabase.com) (Postgres-based backend with auth, database, and edge functions)
- **Database:** PostgreSQL  
- **Auth:** Supabase Auth (JWT-based)  
- **API:** Supabase-generated APIs + custom edge functions  

## User Roles and Permissions

### Parent
- Create account and manage linked students
- Optionally add additional parent accounts
- Optionally mark books as completed for a student

### Student
- Log in with credentials set by parent
- Complete assigned or available books
- Review feedback and retry incorrect answers


## Data Model Overview

**Entities:**
- **Parent**
- **Student**
- **Book** (linked to Level and Category)
- **Unit** (linked to Book)
- **Question** (linked to Unit)
- **Answer** (linked to Student + Question)

> An ERD diagram will be provided in `/docs/` for development reference.


## Local Development

**Requirements:**
- [Supabase CLI](https://supabase.com/docs/guides/cli)

**Setup:**
```bash
# Clone repository
git clone git@github.com:forrestberry/sra-backend.git
cd sra-web-app-backend

# Start Supabase locally
supabase start

# Push migrations
supabase db push

# Run locally
supabase functions serve
```

**Deploy to Production:**
```bash
supabase db push --prod
supabase functions deploy --prod
```
