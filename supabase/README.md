# supabase/

Supabase schema source of truth for The Perfect Look (MVP, tasks T3/T5/T12/T18/T37).

| File                             | Purpose                                                        |
| -------------------------------- | -------------------------------------------------------------- |
| `migrations/001_schema.sql`      | Full schema migration — tables, enums, indexes, triggers, RLS  |
| `migrations/002_auth_profiles.sql` | T5 auth support — contact normalisation, sign-up guard, login identifier resolver |
| `migrations/003_seed_data.sql`   | T4 idempotent seed — services (SRS §8), demo staff + availability, `app_settings`, holidays |
| `migrations/004_branches_client_number_pricing.sql` | T37 schema extension — branches, branch hours/closures, staff-branch assignments, branch_access (branch-scoped RLS), service-branch availability/pricing, packages/add-ons, client number, appointment branch + price snapshots, migration mappings |
| `migrations/005_seed_demo_branches.sql` | T37 idempotent seed + backfill — demo Dubai/Abu Dhabi branches, hours, staff assignments, branch access, service availability, client numbers, appointment snapshots |
| `migrations/006_availability_engine.sql` | T12 branch-aware availability engine — branch capacity, per-appointment buffer snapshot, DB EXCLUDE overlap boundary, `get_availability()`, atomic `reserve_slot()` |
| `migrations/007_branch_providers.sql` | T13 provider list for the availability picker — `get_branch_providers()` (active staff assigned to a branch, primary first) |
| `migrations/008_appointment_booking_api.sql` | T14 booking-API completion — `appointments.payment_status` (booking-time payment state; T38 owns the full payment domain). The booking API itself is T12's atomic `reserve_slot()` |
| `migrations/009_roles_rbac.sql`   | T18 roles/RBAC — 8-role model (SRS §3), invitation flow (SRS §27), branch-scoped helpers, role-change guard, audit hardening |
| `schema.sql`                     | Consolidated snapshot of the final schema (kept in sync)      |
| `seed.sql`                       | Idempotent admin-account seed (call `seed_admin()` with your credentials) |
| `tests/rls_appointments.sql`     | RLS acceptance test (patient isolation, branch-scoped RBAC, SRS §10 enum) |
| `tests/seed_data.sql`            | T4 seed acceptance test (services, settings, staff, holidays) + T37/T18 seed assertions |
| `tests/services_api.sql`         | T9 services API test (active-only reads, admin-only writes, instant patient reflection) |
| `tests/multi_branch_pricing_schema.sql` | T37 acceptance test (branches seed idempotently, client-number uniqueness/immutability/search, branch-scoped RLS, price snapshots, packages, migration mappings) |
| `tests/availability_engine.sql`  | T12 acceptance test (branch hours + Asia/Dubai slots, holidays/closures, leave blocks, buffer/existing-appointment conflicts, cross-branch no-double-book, capacity, snapshots, authorization, layout rejections) |
| `tests/availability_engine_parallel_setup.sql` | T12 parallel-slot proof fixtures + results table (`cleanup` var toggles teardown) |
| `tests/availability_engine_parallel_worker.sql` | T12 parallel-slot proof worker (one concurrent `reserve_slot()` attempt, one result row) |
| `tests/availability_engine_parallel.ps1` | T12 parallel-slot proof driver (Windows) — N concurrent workers, asserts exactly one success |
| `tests/availability_engine_parallel.sh` | T12 parallel-slot proof driver (POSIX) — same proof as the `.ps1` |
| `tests/appointment_booking_api.sql` | T14 booking-API acceptance test (full confirmation contract — appointment ID, client number, branch, service, time, payment status; double-booking impossible; inactive/not-offered services rejected; provider/slot rejections; identity auth gate; booking-time price snapshot) |
| `tests/rbac_invitations.sql`     | T18 acceptance test — no self-escalation, invitation flow, branch-scoped RBAC, role gates, audit trail |

## What the schema contains

- `profiles` (synced from `auth.users` via trigger), `services`,
  `staff`, `staff_availability`, `blocked_periods`, `holidays`,
  `appointments` (with human-readable `appointment_ref` like
  `TPL-20260912-0001`), `notifications`, `audit_logs`, `app_settings`,
  `staff_invitations`, plus the T37 branch tables (`branches`,
  `branch_hours`, `branch_closures`, `staff_branches`, `branch_access`,
  `service_branches`, `package_items`, `service_addons`,
  `migration_mappings`).
- Enums: `appointment_status` (SRS §10), `user_role` (8 roles per
  SRS §3: customer, receptionist, branch_manager, provider, nutritionist,
  finance, administrator, super_admin), `notification_channel` (SRS §15),
  `notification_status`, `service_type`, `branch_access_role`.
- Foreign keys use `ON DELETE RESTRICT`. Unique indexes: email, mobile,
  `appointment_ref`, and a partial unique index that makes double booking
  of the same staff/time impossible at the DB level.
- Row Level Security enabled on every table. Customers see/own only their
  own rows (SRS §17); staff access is **branch-scoped** (T37
  `branch_access` + `can_access_branch()`); admins have full access.
  Self role-escalation is blocked by a trigger, and public sign-ups can
  never self-assign a role (T18).

## Roles & invitations (T18)

- Roles are stored on `profiles.role` and enforced by RLS policies plus
  SECURITY DEFINER helpers (`is_admin()`, `is_staff_or_admin()`,
  `is_super_admin()`, `current_role()`, `can_access_branch()`,
  `can_manage_branch()`, `can_access_payments()`, `can_access_nutrition()`).
- Staff are created through **invitations** (SRS §27): an admin or branch
  manager calls `invite_staff()`, the invitee signs up normally and
  accepts via `accept_invitation(code)`, which provisions the role, the
  `staff` row, `staff_branches` assignment and the `branch_access` grant.
- A session flag (`app.rbac_role_change_authorized`) gates the
  `handle_new_user` / `prevent_self_role_change` triggers so role changes
  only happen through sanctioned pathways (invitation acceptance, admin
  role assignment); test fixtures set the flag to reproduce those paths.

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
insert/update another patient's appointment, staff access is scoped to
their granted branch (Dubai receptionist never sees Abu Dhabi records),
admins see all, and the `appointment_status` enum matches SRS §10. It can
also be pasted into the online SQL editor.

## Running the T18 acceptance test

Requires migrations 001–009 applied (`supabase db reset`), then:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rbac_invitations.sql
```

It asserts: public sign-ups always become `customer` (metadata roles are
never trusted), role changes are blocked outside sanctioned pathways, the
full invitation lifecycle (invite → signup → accept) provisions role +
staff + branch assignments, branch-scoped RBAC isolation, role module gates
(payments / nutrition / super_admin grants), and the audit trail
visibility rules.

## Running the availability-engine acceptance test (T12)

Requires migrations 001–006 applied (`supabase db reset`), then:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/availability_engine.sql
```

It asserts: slots respect branch hours/provider schedules/buffers in
Asia/Dubai (with branch + timezone in every row), holidays and branch
closures remove the day, leave blocks remove covered slots, existing
appointments (incl. buffers) remove overlapping starts, a multi-branch
provider cannot be double-booked (slot list, `reserve_slot()`, DB EXCLUDE
constraint + T3 unique index), branch capacity blocks the second
concurrent slot, booking-time snapshots are captured, authorization
(own-record only, no anon), and layout/branch-scope rejections.

### Parallel-requests proof (exactly one success)

```bash
export SUPABASE_DB_URL="postgresql://postgres:postgres@localhost:54322/postgres"
./supabase/tests/availability_engine_parallel.sh        # or .ps1 on Windows
```

Spawns N concurrent `psql` workers that all try to `reserve_slot()` the
exact same slot, then asserts `availability_parallel_results` has exactly
one `success` among N attempts (advisory-locked re-check + DB overlap
boundary). Fixtures and the results table are created and torn down by
`availability_engine_parallel_setup.sql` automatically.

## Running the booking-API acceptance test (T14)

Requires migrations 001–008 applied (`supabase db reset`), then:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/appointment_booking_api.sql
```

It asserts the T14 booking contract built on T12's `reserve_slot()`:
the confirmation returns appointment ID, `appointment_ref`, client
number, branch, service and time plus `payment_status` (defaults to
`unpaid`, CHECK-enforced); a booked/overlapping slot is rejected and
never re-offered (double-booking impossible); inactive and not-offered
services are rejected; provider/slot layout rejections (required
provider, off-grid, closed day, past time); the identity auth gate
(book-own-only, no anon); and booking-time price snapshots stay
immutable when the catalogue later changes.

> Only the Supabase URL + **anon** key ever reach the browser. The
> service-role key is used exclusively by `tools/` (T25) and CI.