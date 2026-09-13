# supabase/

Supabase schema source of truth for The Perfect Look (MVP, task T3).

| File                             | Purpose                                                        |
| -------------------------------- | -------------------------------------------------------------- |
| `migrations/001_schema.sql`      | Full schema migration — tables, enums, indexes, triggers, RLS  |
| `migrations/002_auth_profiles.sql` | T5 auth support — contact normalisation, sign-up guard, login identifier resolver |
| `migrations/003_seed_data.sql`   | T4 idempotent seed — services (SRS §8), demo staff + availability, `app_settings`, holidays |
| `migrations/004_branches_client_number_pricing.sql` | T37 schema extension — branches, branch hours/closures, staff-branch assignments, branch_access (branch-scoped RLS), service-branch availability/pricing, packages/add-ons, client number, appointment branch + price snapshots, migration mappings |
| `migrations/005_seed_demo_branches.sql` | T37 idempotent seed + backfill — demo Dubai/Abu Dhabi branches, hours, staff assignments, branch access, service availability, client numbers, appointment snapshots |
| `migrations/006_availability_engine.sql` | T12 branch-aware availability engine — `get_branch_providers()`, `is_staff_free()`, `get_availability()` (branch hours/closures, holidays, duration/buffers, provider schedules, blocks, appointments at any branch, Asia/Dubai time, booking window/notice) |
| `schema.sql`                     | Consolidated snapshot of the final schema (kept in sync)      |
| `seed.sql`                       | Idempotent admin-account seed (call `seed_admin()` with your credentials) |
| `tests/rls_appointments.sql`     | RLS acceptance test (patient isolation, RBAC, SRS §10 enum)   |
| `tests/seed_data.sql`            | T4 seed acceptance test (services, settings, staff, holidays) |
| `tests/services_api.sql`         | T9 services API test (active-only reads, admin-only writes, instant patient reflection) |
| `tests/multi_branch_pricing_schema.sql` | T37 acceptance test (branches seed idempotently, client-number uniqueness/immutability/search, branch-scoped RLS, price snapshots, packages, migration mappings) |
| `tests/availability_engine.sql`  | T12 acceptance test (slot grid in Asia/Dubai, holiday/closure days, provider filter, booking + buffer blocks, cross-branch single-book, unique-index concurrency, past dates, advance notice) |

## What the schema contains

- `profiles` (synced from `auth.users` via trigger), `services`,
  `staff`, `staff_availability`, `blocked_periods`, `holidays`,
  `appointments` (with human-readable `appointment_ref` like
  `TPL-20260912-0001`), `notifications`, `audit_logs`, `app_settings`.
- Enums: `appointment_status` (SRS §10), `user_role`, `notification_channel`
  (SRS §15), `notification_status`.
- Foreign keys use `ON DELETE RESTRICT`. Unique indexes: email, mobile,
  `appointment_ref`, and a partial unique index that makes double booking
  of the same staff/time impossible at the DB level.
- Row Level Security enabled on every table. Patients see/own only their
  own rows; staff see all appointments; admins have full access
  (SRS §17). Self role-escalation is blocked by a trigger.

## Applying locally / to the online project

```bash
supabase start          # local stack (must be installed)
supabase db push        # apply migrations to the linked remote project
```

The online Supabase project (System of Record, SRS §12) is linked via
`supabase login` + `supabase link --project-ref <ref>`; see the T3 ticket.

## Seeding the admin account

`seed.sql` defines `public.seed_admin(email, password)` (idempotent —
returns the existing id if the email already exists) and calls it with a
**dev-only default**. Change it immediately on anything shared:

```sql
SELECT public.seed_admin('admin@theperfectlook.ae', 'your-strong-password');
```

Preferred: create the admin via the Supabase Dashboard (Authentication →
Users → Add user, role `` set in the profiles row or `raw_user_meta_data`)
so no bootstrap password ever sits in a file.

## Running the RLS acceptance test

Requires a running local stack (`supabase db reset` first), then:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_appointments.sql
```

It asserts: patients can only read their own appointments, can't
insert/update another patient's appointment, staff/admin see all, and the
`appointment_status` enum matches SRS §10. It can also be pasted into the
online SQL editor.

> Only the Supabase URL + **anon** key ever reach the browser. The
> service-role key is used exclusively by `tools/` (T25) and CI.