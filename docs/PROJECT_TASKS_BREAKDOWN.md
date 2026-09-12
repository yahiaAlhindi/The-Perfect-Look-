# The Perfect Look — MVP Project Tasks Breakdown

Source document: `The_Perfect_Look_App_Requirements_UPDATED.md` (Software Requirements Specification, SRS v1)

This file converts the SRS into a complete, dependency-aware, two-person task plan for building the **MVP** (client-approval demo).

---

## 1. Tech Stack Decision (MVP — Browser First)

The SRS requires: responsive web/mobile interface, online database, Arabic + English, deployable so an overseas client can review it.

| Layer        | Choice                                      | Why                                                                                                                            |
| ------------ | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Frontend     | React 18 + Vite + TypeScript + Tailwind CSS | Browser-first MVP, extremely fast dev, easy static deploy. Mobile-first responsive design.                                      |
| Routing      | React Router                                | Standard SPA routing for patient + admin areas.                                                                                  |
| Server state | TanStack Query                              | Cache-invalidation for availability/booking consistency.                                                                         |
| Backend/API  | Supabase (Postgres + Auth + RLS + REST)     | Online DB = SRS "System of Record"; free tier; handles auth, RLS, and transactions out of the box. No separate server to run.     |
| DB           | Supabase PostgreSQL                         | Online database per SRS §2/§12. All future transactions live here; Excel is read-only migration input.                           |
| Excel import | SheetJS (xlsx)                              | Parse the legacy Excel for the one-time migration (SRS §13).                                                                     |
| i18n/RTL     | i18next + date-fns                          | Arabic + English with full RTL support (SRS §18).                                                                                |
| PWA          | vite-plugin-pwa                             | Installable to the phone home screen, standalone mode — feels like a native app while living in the browser (MVP requirement).    |
| Deploy       | GitHub Pages via GitHub Actions             | Free static hosting for `yahiaAlhindi.github.io/The-Perfect-Look-` so the client can open it anywhere on any device.              |
| Validation   | zod                                         | Shared client/server-side schema validation (SRS §17).                                                                           |

> **Expo note:** Expo is preferred for the *production/next-level* native app. The MVP is deliberately React + Vite because it is browser-first and deployable to GitHub Pages. The component structure and API layer will be kept clean so the production app can migrate to Expo/React Native later without rewriting business logic.

> **SQLite note:** SQLite is allowed for local-only work, but since the MVP must run online for the client, **Supabase is the default**. SQLite may be used in the migration tool only for dry-run testing locally before hitting the online DB.

---

## 2. Team Roles

### Person 1 — Backend / Data / Infra (Supabase, APIs, migration, security, deploy)
Owns: Supabase project & schema, seed data, auth API, services API, availability engine, booking/lifecycle logic, RBAC, admin APIs, Excel migration tool, notifications service, security hardening, GitHub Pages deployment.

### Person 2 — Frontend / UI / UX (components, patient flows, admin UI, i18n, PWA)
Owns: design system, auth pages, profile, services browsing, availability picker, booking flow, "My Appointments", staff dashboard, admin management screens, migration UI, notifications UI, Arabic/RTL, PWA polish, responsive mobile pass.

---

## 3. Workflow Rules (Read This First)

1. **One task = one thread.** Open a separate chat thread per task. Focus that thread only on its task.
2. **Branch per task.** Branch name: `task/TXX-short-slug` (e.g. `task/T14-booking-api`). Open a PR into `main`, get it merged, then move to the next task.
3. **Dependency rule (MANDATORY).** Every task lists its **Dependencies**. Before starting ANY task, check every dependency's Status. If any dependency is not `🟢 Done`, you MUST state: *"I will not start this task until [TXX] is complete."* and do not begin work on it.
4. **Status values** (updated in the Status column after each task):

| Status        | Meaning                                                                 |
| ------------- | ----------------------------------------------------------------------- |
| ⬜ Not Started | Ready to be picked up (all dependencies done)                          |
| 🟡 Needs Input | Blocked waiting on data/a decision (details in Notes)                   |
| 🔵 In Progress | Currently being worked on in a thread                                    |
| 🟢 Done        | Merged via PR and verified                                              |

5. **Hand-off tasks.** Some tasks are labeled **"P1 + P2"** — they must be done as two PRs (P1 backend/API first, then P2 wires the UI to it). The backend part must be merged and marked done before the UI part starts.
6. **Verification.** Every task is only `🟢 Done` after its PR is merged AND its acceptance criteria pass in the live build.
7. **Open items (T35).** Anything needing client data is tracked there. If a task is blocked by T35, mark it `🟡 Needs Input` and note what's missing.

---

## 4. Task Plan

> Priority = build order. P1 builds backend foundations first; P2 builds UI in parallel where dependencies allow.

---

### MILESTONE A — Foundation & Setup

#### T1 — Design System & UI Theme
- **Owner:** Person 2
- **Priority:** Must Start First (can start immediately)
- **Dependencies:** none
- **Status:** ⬜ Not Started
- **Description:**
  - Set up the React + Vite + TypeScript + Tailwind project with the app shell and design system.
  - Brand: premium beauty-clinic feel (The Perfect Look): elegant colors (e.g. soft neutrals, gold/rose accents), clean modern typography that supports Arabic glyphs.
  - Build the core component library: Button, Input, Select, Checkbox, Card, Badge, Modal/Dialog, Tabs, Toast/Snackbar, Spinner, Empty state, Page header.
  - Space tokens, radius, shadows, spacing scale; mobile-first responsive breakpoints (SMS-sized to desktop).
  - App shell with protected/public routing skeleton and shared layout (header, footer, bottom nav for mobile).
- **Acceptance criteria:**
  - Design tokens consumed by all components (no hard-coded colors in screens).
  - Components used by both the patient and admin areas.
  - A storybook-style demo page OR clearly documented component usage examples.
  - Passes responsive check at 360px, 768px, 1280px widths.
- **Notes:** This is the visual foundation; all P2 UI tasks reuse it.

---

#### T2 — Repo Structure & GitHub Pages Deploy Pipeline
- **Owner:** Person 1
- **Priority:** Must Start First (can start immediately)
- **Dependencies:** none
- **Status:** 🟢 Done
- **Description:**
  - Define repo layout: `/web` (frontend app), `/supabase` (SQL migrations + seed), `/tools` (migration script), `/docs` (this plan).
  - Add `vite-plugin-pwa` readiness config and `base` set for GitHub Pages sub-path `/The-Perfect-Look-/`.
  - GitHub Actions workflow: on push to `main` → install → build → typecheck → deploy `dist` to `gh-pages` branch (or use `actions/deploy-pages`).
  - Set up branch + PR conventions described in §3.
  - Environment variable strategy: `.env.example` with Supabase URL/anon key; secrets never committed.
- **Acceptance criteria:**
  - Empty-but-compiling app deploys to `https://yahiaAlhindi.github.io/The-Perfect-Look-/` and loads.
  - PR → merge → auto-deploy cycle proven with a trivial change.
  - `.env.example` present; no real keys in repo.
- **Notes:** Everything else deploys on top of this.

---

#### T3 — Supabase Project & Database Schema
- **Owner:** Person 1
- **Priority:** 1
- **Dependencies:** T2 (repo structure needed to hold `supabase/` migrations)
- **Status:** ⬜ Not Started
- **Description:**
  - Create the Supabase project (online database = System of Record, SRS §12).
  - Write SQL migrations covering (SRS §12 + §20):
    - **profiles** — id, full_name, mobile_number (unique), email (unique), dob, gender, preferred_language, role (patient/staff/admin), created_at.
    - **services** — id, name, description, duration_minutes, price, currency, active, assigned_staff_type, booking_rules (JSONB), sort_order.
    - **staff** — id, profile_id, title, specializations, active.
    - **staff_availability** — id, staff_id, day_of_week, start_time, end_time.
    - **blocked_periods** — id, staff_id (nullable = clinic-wide), start_datetime, end_datetime, reason.
    - **holidays** — id, date, reason.
    - **appointments** — id (unique ref + human-readable Appointment ID), patient_id, service_id, staff_id (nullable), scheduled_start, scheduled_end, status, notes, cancel_reason, last_modified fields.
    - **notifications** — id, user_id, type, channel, subject, body, status, sent_at, read_at.
    - **audit_logs** — id, admin_user_id, action, entity, entity_id, details JSONB, created_at.
    - **app_settings** — key, value JSONB (clinic working hours, slot interval, cancellation notice hours, rescheduling, currency, etc.).
  - Enums + check constraints for appointment statuses (Pending, Confirmed, Completed, Cancelled, Rescheduled, No Show — SRS §10) and notification channels (Email, SMS, WhatsApp — SRS §15).
  - Uniqueness/indexes: email, mobile_number; appointment date/time + staff; foreign keys with `ON DELETE RESTRICT`.
  - Row Level Security (RLS) policies covering patient, staff, admin access; **patients can only read/write their own data; staff/admin access granted by role** (SRS §17).
  - Seed an admin account (used for initial setup).
- **Acceptance criteria:**
  - All migrations apply cleanly in the online Supabase project.
  - `supabase/schema.sql` + seed script committed in the PR.
  - RLS blocks a patient from reading another patient's appointments (verified via an SQL test).
  - Appointment status values match SRS §10 exactly.
- **Notes:** The SRS says "final schema will be incorporated once provided by the project owner" (§20) — this schema is the MVP proposal and must be stable before T4–T27 start.

---

#### T4 — Seed Data (services, staff, working hours, settings)
- **Owner:** Person 1
- **Priority:** 1
- **Dependencies:** T3
- **Status:** ⬜ Not Started
- **Description:**
  - Seed the services from SRS §8 with sensible durations/prices (flagged in T35 for client confirmation):
    1. Skin Care Treatment
    2. Advanced Hair Care Solutions
    3. Laser Hair Removal
    4. Clinical Nutrition & Weight Management
    5. Body Contouring / Fat Reduction
    6. Cellulite Treatment
    7. Slimming / Weight Management
    8. Other services/packages (placeholder — final list per T35)
  - Seed 2–3 demo staff members with weekly availability.
  - Seed `app_settings`: working hours, slot interval (e.g. 30 min), cancellation notice period, rescheduling window, currency (default AED), holiday calendar.
  - Idempotent (safe to re-run).
- **Acceptance criteria:**
  - Services, staff, and settings visible via direct SQL query.
  - Settings read from `app_settings`, not hard-coded in the app.
- **Notes:** Values are demo defaults until the clinic answers T35.

---

### MILESTONE B — Authentication & Patient Account (SRS §5, §6, §7)

#### T5 — Auth & Session API (person-side: Supabase Auth + profile sync)
- **Owner:** Person 1
- **Priority:** 2
- **Dependencies:** T3
- **Status:** ⬜ Not Started
- **Description:**
  - Wire Supabase Auth: sign up (email + password), sign in with email OR mobile number (business decision T35), sign out, send password reset, update password.
  - On sign-up trigger (DB trigger/edge function): insert into `profiles` with role=patient; enforce mobile/email uniqueness on both `auth.users` and `profiles`.
  - Email format, mobile format (UAE/E.164 normalization), and password policy validation at the API boundary (SRS §5).
  - Secure session/token lifecycle; session persisted for refresh (SRS §6).
  - Expose a client API module (`supabase/client.ts`) used by all P2 screens.
- **Acceptance criteria:**
  - Register → login → logout → password reset works end to end via API.
  - Every new auth user automatically gets a `profiles` row.
  - Duplicate email/mobile returns a clear, mapped error (no raw DB errors).
  - Passwords are stored hashed by Supabase; never plain text (SRS §6/§17).
- **Notes:** OTP is explicitly "optional later" per SRS §6 — skipped in MVP.

---

#### T6 — Auth Pages: Register / Login / Forgot & Reset Password
- **Owner:** Person 2
- **Priority:** 2
- **Dependencies:** T1 (design system), T5 (auth API to wire to)
- **Status:** ⬜ Not Started
- **Description:**
  - **Register** (SRS §5): full_name, mobile, email, password, confirm password, DOB, gender, preferred_language, required consent checkbox for Privacy Policy / Terms.
  - **Login** (SRS §6): email or mobile + password, remember-me, forgot-password link.
  - **Forgot / Reset password**: request reset → Supabase email link → set new password → success screen.
  - **Logout** button in the app shell.
  - Live validation mirroring T5 rules (email format, mobile format, password policy, confirm-password match, required fields, duplicate-account server errors mapped to friendly Arabic/English messages).
  - Disable submit while pending; friendly error/success toasts; language switcher present.
- **Acceptance criteria:**
  - Full happy-path + error-path flows verified against live Supabase.
  - Terms consent blocks submission until checked (SRS §5).
  - Both EN and AR render (see also T29).
- **Notes:** Consumes all routes/errors from T5; if a server error message is missing, add it to T5's mapped-error catalog instead of hard-coding a workaround in UI.

---

#### T7 — Patient Profile: View, Edit, Change Password
- **Owner:** Person 2
- **Priority:** 3
- **Dependencies:** T6, T8 (profile API)
- **Status:** ⬜ Not Started
- **Description:**
  - Profile screen (SRS §7): view personal info; edit allowed fields; change password (current + new + confirm); save with optimistic updates.
  - Role-aware: patients see only their own profile.
  - Entry points from app shell; works in EN + AR.
- **Acceptance criteria:**
  - Edits persist to `profiles` and reload correctly after refresh.
  - Change password validates current password and rejects wrong values.
  - Mobile/email uniqueness conflicts surfaced as friendly errors.
- **Notes:** Depends on T8 for the update endpoint behavior.

---

#### T8 — Profile API (GET/PUT profile, change password)
- **Owner:** Person 1
- **Priority:** 3
- **Dependencies:** T3, T5
- **Status:** ⬜ Not Started
- **Description:**
  - `GET /profile` — fetch own profile (RLS-scoped).
  - `PUT /profile` — update allowed fields (full_name, dob, gender, preferred_language); email/mobile change restricted or gated (decision T35).
  - Change-password endpoint via Supabase Auth (`updateUser({ password })` after verifying current password).
- **Acceptance criteria:**
  - Profile fetch/update verified with RLS enforced (patient A cannot edit patient B).
  - Change password verified — old password required.
- **Notes:** Mirror of SRS §16 `GET /profile`, `PUT /profile`.

---

### MILESTONE C — Services & Availability (SRS §8, §11)

#### T9 — Services API (public list + detail + admin CRUD backend)
- **Owner:** Person 1
- **Priority:** 3
- **Dependencies:** T3, T4
- **Status:** ⬜ Not Started
- **Description:**
  - `GET /services` — active services only for patients (SRS §8 `active` flag).
  - `GET /services/:id` — service detail (description, duration, price visibility per T35, assigned staff type, booking rules).
  - Admin CRUD endpoints (create/update/deactivate) used by T11/T12 - enforce staff/admin role (T18 RBAC).
  - Services are dynamic from the online DB — no code deploy when a service is added/changed (SRS §8).
- **Acceptance criteria:**
  - Frontend never hard-codes service lists; everything comes from the API.
  - Editing a service in admin is reflected on the patient side immediately.
- **Notes:** Feeds T10 (patient UI) and T11/T12 (admin UI).

---

#### T10 — Patient Services Browsing UI
- **Owner:** Person 2
- **Priority:** 3
- **Dependencies:** T9
- **Status:** ⬜ Not Started
- **Description:**
  - Services listing screen: elegant cards with name, short description, duration, price (if enabled), "Book" call-to-action (SRS §8).
  - Service detail view with full description and booking rules.
  - Loading skeletons + empty state; Arabic + English.
- **Acceptance criteria:**
  - All active services render from API; inactive/deleted services never appear.
  - "Book" navigates to the booking flow (T15).
- **Notes:** Reuses T1 components.

---

#### T11 — Services Admin UI (CRUD + availability flags)
- **Owner:** Person 2
- **Priority:** 4
- **Dependencies:** T20 (admin APIs incl. services management), T18 (admin role guard)
- **Status:** ⬜ Not Started
- **Description:**
  - Admin screen: list services with active/inactive toggle, create/edit/delete form (name, description, duration, price, assigned staff type, booking rules).
  - Search + status filter; confirm dialogs on destructive actions.
- **Acceptance criteria:**
  - Admin changes instantly reflect on the patient services screen.
  - Non-admin (patient) cannot reach the screen (guard via T18).
- **Notes:** UI counterpart of the services admin part of T20.

---

#### T12 — Availability Engine (slots, working hours, staff, blocks) — CORE BUSINESS LOGIC
- **Owner:** Person 1
- **Priority:** 4
- **Dependencies:** T3, T4, T9
- **Status:** ⬜ Not Started
- **Description:**
  - `GET /availability?serviceId=&staffId=&date=` (SRS §16) returns bookable slots for a given day.
  - Generate slots from `app_settings` working hours + slot interval; subtract holidays (`holidays`) and blocked periods (`blocked_periods`, clinic-wide and per-staff); respect staff availability (`staff_availability`).
  - A slot is **bookable only if** no active appointment already occupies it — must read live state to prevent double booking (SRS §11).
  - Optional preferred-staff query reduces to that staff's slots.
  - Store slots in a `slots` ledger table OR compute against `appointments` with row locks — design must make double-booking impossible at DB level (SRS §11, §18).
- **Acceptance criteria:**
  - Slots respect: working hours, slot interval, holidays, blocked periods, staff schedules.
  - A booked slot never appears as available again.
  - API test: two simultaneous requests for the same slot → exactly one succeeds.
- **Notes:** Feeds T13 (picker UI) and T14 (booking). This is the trickiest P1 logic — take time to make the concurrency guard solid.

---

#### T13 — Availability Picker UI (date + slot + preferred staff)
- **Owner:** Person 2
- **Priority:** 4
- **Dependencies:** T12
- **Status:** ⬜ Not Started
- **Description:**
  - Date navigator (day/week view, only bookable days enabled).
  - Slot grid for the selected date (with timezone handled for the clinic's location).
  - Optional "preferred staff" select when the service supports it (SRS §9 step 5).
  - Unavailable/blocked slots visually disabled with reason (holiday / fully booked).
- **Acceptance criteria:**
  - Slots match the API exactly; selecting a slot carries it into the booking flow (T15).
  - Arabic + English rendering.
- **Notes:** Depends on T12's data contract; if the shape changes, T12 owns the contract.

---

### MILESTONE D — Appointment Booking & Lifecycle (SRS §9, §10, §11)

#### T14 — Appointment Booking API (transactional, no double booking)
- **Owner:** Person 1
- **Priority:** 5
- **Dependencies:** T12, T9, T5
- **Status:** ⬜ Not Started
- **Description:**
  - `POST /appointments` (SRS §16): flow = re-check slot availability **inside a DB transaction** → insert appointment → mark slot taken.
  - Race-free: use row-level locks / unique constraint so two bookings for the same slot cannot both succeed.
  - Generate unique, human-readable **Appointment ID** (e.g. `TPL-20260912-XXXX`).
  - Validate: service active, slot within working hours, not holiday/blocked, notice-period rules (SRS §11).
  - Create "Pending" appointment; confirmation flows per SRS §9 step 9.
  - Trigger notification hook (T27).
- **Acceptance criteria:**
  - Double-booking attempt always fails server-side (verified with parallel requests).
  - Appointment persisted in online DB with valid status + unique Appointment ID.
  - Business rules (working hours, holidays, blocks, notice periods) all enforced.
- **Notes:** The vertex of the whole app — correctness here is non-negotiable.

---

#### T15 — Booking Flow UI (multi-step wizard)
- **Owner:** Person 2
- **Priority:** 5
- **Dependencies:** T13, T14
- **Status:** ⬜ Not Started
- **Description:**
  - Mobile-friendly wizard (SRS §9 steps 1–9): Service → Date & Slot (T13) → Preferred staff (if any) → Review & Confirm → Confirmation screen with Appointment ID + next steps.
  - Requires login; redirects to login with a "return to booking" behavior when a guest tries to book.
  - Backend availability re-check surfaced: if the slot is taken at confirm time, show a friendly "slot just taken, pick another" state.
- **Acceptance criteria:**
  - Full flow completes and creates a real appointment in Supabase.
  - Slot-taken race handled gracefully.
  - Works at mobile width and flows naturally.
- **Notes:** Consumes T14 API; maps server statuses to friendly messages.

---

#### T16 — Appointment Lifecycle API (list, detail, cancel, reschedule)
- **Owner:** Person 1
- **Priority:** 5
- **Dependencies:** T14, T3
- **Status:** ⬜ Not Started
- **Description:**
  - `GET /appointments` — my appointments (upcoming + history) (SRS §7, §16).
  - `GET /appointments/:id` — detail with service/staff info.
  - `POST /appointments/:id/cancel` — releases the slot, sets status Cancelled, respects notice period (SRS §11).
  - `PUT /appointments/:id` — reschedule: in one transaction release old slot + reserve new slot (SRS §11), status → Rescheduled, keep a link to history.
  - Enforce rules: only own appointments (patients) or staff/admin; cancellation/reschedule only for Pending/Confirmed; notice-period checks.
- **Acceptance criteria:**
  - Cancel releases the slot (it is bookable again).
  - Reschedule atomically frees old + holds new slot (no gap where both are taken or none).
  - Upcoming vs history correctly derived from date/time + status.
- **Notes:** Feeds T17 (My Appointments UI) and T22 (admin management).

---

#### T17 — My Appointments UI (upcoming + history, cancel/reschedule)
- **Owner:** Person 2
- **Priority:** 5
- **Dependencies:** T16
- **Status:** ⬜ Not Started
- **Description:**
  - "My Appointments" (SRS §7): tabs/sections for Upcoming and History.
  - Cards show service, date/time, staff, status badge, Appointment ID.
  - Cancel action (with confirm dialog + reason) and Reschedule action (reuses T13 picker).
  - Statuses displayed per SRS §10 (Pending/Confirmed/Completed/Cancelled/Rescheduled/No Show).
  - Empty states and loading states.
- **Acceptance criteria:**
  - Cancelling updates the list immediately and the slot is gone from the app's availability.
  - Reschedule opens the picker and updates the appointment on confirm.
  - Arabic + English.
- **Notes:** Reuses T1 components + T13 picker.

---

### MILESTONE E — Staff & Admin Portal (SRS §14)

#### T18 — Roles, Invitations & Access Control (RBAC)
- **Owner:** Person 1
- **Priority:** 4
- **Dependencies:** T5, T3
- **Status:** ⬜ Not Started
- **Description:**
  - Role model: patient / staff (receptionist) / admin on `profiles.role` + helper claims.
  - Staff invitation flow (admin creates staff account).
  - Route guard helper exposed to frontend (can user access `role >= staff`?).
  - All admin/staff API endpoints enforce role server-side + via RLS (SRS §17, §19: "Unauthorized users cannot access staff/admin functions").
- **Acceptance criteria:**
  - Patient token receives 403 on any admin endpoint.
  - Staff can access staff-only endpoints; admin can access everything; patients only their own data.
- **Notes:** Prerequisite for T11, T19–T24.

---

#### T19 — Staff Dashboard UI (today's & upcoming appointments)
- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T16, T18, T20 (list/search API)
- **Status:** ⬜ Not Started
- **Description:**
  - Dashboard (SRS §14): today's and upcoming appointments; quick status change (Pending → Confirmed → Completed; No Show; Cancel with reason).
  - Search/filter by patient, service, staff, date, status.
  - Compact table (desktop) + card list (mobile).
- **Acceptance criteria:**
  - Staff can see and update appointment statuses.
  - Filters behave server-side (via T20).
- **Notes:** Person 2's main staff-facing screen.

---

#### T20 — Admin APIs (staff, availability, appointments, reports, services mgmt)
- **Owner:** Person 1
- **Priority:** 5
- **Dependencies:** T3, T16, T18
- **Status:** ⬜ Not Started
- **Description:**
  - Staff CRUD + role assignment (feeds T21).
  - Staff availability + blocked-period CRUD (feeds T21) — consumed by the availability engine (T12).
  - Appointment management endpoints: create-on-behalf, confirm, cancel, reschedule, complete, no-show (feeds T22).
  - Search/filter endpoint for appointments (patient, service, staff, date, status) (SRS §14).
  - Services + settings management endpoints (admin portion consumed by T11).
  - Role-enforced on every route (T18).
- **Acceptance criteria:**
  - Every listed operation works with proper RBAC (403 for non-admin where required).
  - Availability changes via this API immediately affect new slot lookups.
- **Notes:** The admin surface of the SRS §14 + §16 "Admin APIs". Feeds T21, T22, T23.

---

#### T21 — Admin Staff Management UI (staff, availability, blocked time)
- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T20, T18
- **Status:** ⬜ Not Started
- **Description:**
  - Manage staff: invite/create, edit details, activate/deactivate, assign role.
  - Manage staff weekly availability (per day-of-week start/end times) (SRS §14).
  - Manage clinic-wide & per-staff blocked periods and holidays.
- **Acceptance criteria:**
  - Availability/block changes reflect in the patient-facing availability inside a refresh.
  - Guarded to admin role.
- **Notes:** Reuses T1 form components.

---

#### T22 — Admin Appointment Management UI
- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T16, T20
- **Status:** ⬜ Not Started
- **Description:**
  - Admin/staff screens: search/filter appointments (patient, service, staff, date, status) (SRS §14).
  - Create appointment for a patient (booking on their behalf).
  - Confirm / cancel / reschedule / complete / mark no-show.
  - View patient appointment history per role permissions.
- **Acceptance criteria:**
  - All status transitions per SRS §10 available; slot consistency maintained (uses T16 logic).
  - RBAC respected.
- **Notes:** Sits on T20 endpoints; visual twin of T19 for admins.

---

#### T23 — Reports & Export API (CSV/Excel)
- **Owner:** Person 1
- **Priority:** 7
- **Dependencies:** T20
- **Status:** ⬜ Not Started
- **Description:**
  - Export endpoint for appointments (filtered) → CSV/Excel (SRS §14 "Export reports/data when required").
  - Include migration results endpoint (imported/skipped/duplicate/failed) for the T26 UI (SRS §14 "View migration results").
- **Acceptance criteria:**
  - Exported file opens correctly and contains filtered data.
  - Migration report retrievable by admin.
- **Notes:** Feeds T24 (UI) and T26 (migration UI).

---

#### T24 — Reports & Export UI
- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T23, T18
- **Status:** ⬜ Not Started
- **Description:**
  - Admin screen with export buttons for appointment reports (respecting current filters).
  - Download handling (CSV) and success/failure toasts.
- **Acceptance criteria:**
  - One click exports the currently filtered dataset.
  - Guarded to admin role.
- **Notes:** Thin UI over T23.

---

### MILESTONE F — Legacy Excel Migration (SRS §2, §13)

#### T25 — Excel Migration Tool & Validation Engine
- **Owner:** Person 1
- **Priority:** 6
- **Dependencies:** T3, T4
- **Status:** ⬜ Not Started
- **Description:**
  - Node/TS script + reusable library to read the legacy Excel (SheetJS) and migrate to Supabase (SRS §13).
  - Mapping per SRS §13 example matrix:

    | Excel      | Target      | Transformation                                    |
    | ---------- | ----------- | ------------------------------------------------- |
    | Patient Name | Patient (profiles.full_name) | Trim/normalize text                     |
    | Mobile     | MobileNumber | Normalize to E.164 country/phone format           |
    | Email      | Email        | Lowercase + validate                              |
    | Treatment  | Service      | Map legacy name → configured service name         |
    | Appt Date  | AppointmentDate | Convert to DB date                             |
    | Appt Time  | StartTime    | Convert to standard time                          |
    | Status     | Status       | Map legacy status → system status enum (SRS §10)  |
  - Validate required fields; detect duplicates (patients and appointments) via agreed matching rules (T35).
  - Insert valid records; **never modify the source Excel file** (SRS §2).
  - Produce a migration report: imported / skipped / duplicate / failed counts + row-level detail.
  - Dry-run mode (SQLite or a staging Supabase project) before production (SRS §13 "run in controlled environment").
- **Acceptance criteria:**
  - A sample Excel fixture migrates correctly in dry-run; report shows correct buckets.
  - Migration is idempotent-enough (re-running doesn't duplicate already-imported patients/appointments).
  - Source file byte-identical after migration.
- **Notes:** The legacy Excel file itself is NOT in the repo — the clinic must supply it (T35). Build and test against a generated sample that follows the SRS column structure. After migration, Excel is read-only forever (SRS §2/§22).

---

#### T26 — Migration Admin UI (upload, run, view results)
- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T25, T18, T23 (results endpoint)
- **Status:** ⬜ Not Started
- **Description:**
  - Admin-only screen: upload an Excel file (drag & drop), configured mapping preview, run migration (dry-run vs live), view the migration report (imported/skipped/duplicate/failed) (SRS §14).
  - Show per-row errors for the failed/skipped rows.
- **Acceptance criteria:**
  - End-to-end: upload → migrate → report rendered.
  - Guarded to admin.
- **Notes:** Person 1 owns the engine (T25); Person 2 owns this screen.

---

### MILESTONE G — Notifications & Internationalization (SRS §15, §18)

#### T27 — Notifications Service (confirmations, reminders, cancellations)
- **Owner:** Person 1
- **Priority:** 7
- **Dependencies:** T14, T16, T5
- **Status:** ⬜ Not Started
- **Description:**
  - Trigger on: booking created (confirmation), before-appointment reminder, cancellation confirmation, rescheduling confirmation (SRS §15).
  - Channel abstraction: Email (Supabase Auth email / third-party), SMS, WhatsApp — configurable provider per T35; default to Email in MVP.
  - Record notification status in `notifications` (SRS §15 "Notification status should be recorded").
  - Insert in-app notification rows for the bell UI (T28).
- **Acceptance criteria:**
  - Booking → confirmation email + in-app notification created (status recorded).
  - Cancellation → cancellation email + in-app notification.
  - Missing/invalid provider gracefully logged, never crashes booking.
- **Notes:** Provider keys = env/secrets, never in frontend.

---

#### T28 — In-App Notifications UI
- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T27
- **Status:** ⬜ Not Started
- **Description:**
  - Notification bell in the app shell: unread count badge, list of in-app notifications, expand to read, mark-as-read.
  - Link notifications to the relevant appointment.
- **Acceptance criteria:**
  - Booking/cancel/reschedule generates a notification visible to the right user.
  - Unread badge clears on read.
- **Notes:** Pure UI over T27's `notifications` table.

---

#### T29 — Internationalization: Arabic + English + RTL
- **Owner:** Person 2
- **Priority:** 6 (parallel with other UI tasks)
- **Dependencies:** T1
- **Status:** ⬜ Not Started
- **Description:**
  - i18next: EN + AR locale files for every screen, form label, status, toast, error message (SRS §18).
  - Full RTL: dir=rtl layout, mirrored icons/navigation, Arabic pluralization, date/number formatting (date-fns locale, Gregorian + optional Hijri display).
  - Language switcher persisted on the profile; default from `preferred_language`.
- **Acceptance criteria:**
  - Toggling language flips the entire app (layout direction + content) without reload artifacts.
  - Every user-facing string is translated (audit by searching for hard-coded English in JSX).
- **Notes:** Do this early enough that new screens are written EN+AR from day one.

---

### MILESTONE H — PWA, Security, QA, Deployment (SRS §17, §18, §19)

#### T30 — PWA: Installable "real app" feel on mobile
- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T2
- **Status:** ⬜ Not Started
- **Description:**
  - `vite-plugin-pwa`: web manifest (name "The Perfect Look", icons 192/512), theme color, standalone display, service worker with app-shell caching.
  - On phones: "Add to Home Screen" / install prompt → opens full-screen like a native app (MVP requirement).
  - Mobile viewport/theme-color meta, safe-area handling, bottom-nav affordance, touch-friendly hit areas.
  - Offline shell: cached app loads; data ops show friendly offline state.
- **Acceptance criteria:**
  - On a phone browser the install banner appears; installed to home screen and opens standalone with no browser chrome.
  - Lighthouse PWA installability passes.
- **Notes:** This delivers the "website but works like a mobile app" requirement.

---

#### T31 — Security Hardening & Validation Pass
- **Owner:** Person 1
- **Priority:** 8
- **Dependencies:** T5, T18, T25
- **Status:** ⬜ Not Started
- **Description:**
  - Server-side (Supabase RPC/edge) validation for all writes (SRS §17 "server-side validation").
  - HTTPS enforced (GitHub Pages + Supabase are HTTPS; document + verify no http links) (SRS §17).
  - No DB credentials reach the browser — only Supabase URL + **anon** key; service-role key server-side only (SRS §17).
  - Audit logging for important admin actions writes to `audit_logs` (SRS §17).
  - RLS final audit: enumerate tables and confirm the least-privilege policy set.
  - Patient records never publicly exposed; no public routes leak data (SRS §17).
  - Backup & recovery: document Supabase PITR/export procedure (SRS §17).
  - UAE healthcare/privacy note: dependency/checklist in docs (SRS §17).
- **Acceptance criteria:**
  - Attempts to read/write others' data fail at DB level (tested).
  - Admin actions appear in `audit_logs`.
  - Secret/key leakage scan clean (`rg` for keys, no `.env` committed).
- **Notes:** Pair with T32 for verification.

---

#### T32 — End-to-End Testing vs MVP Acceptance Criteria
- **Owner:** P1 + P2 (shared; run as two PRs — P1 drafts the script + fixes backend, P2 fixes UI)
- **Priority:** 8
- **Dependencies:** T14, T16, T17, T19, T25, T26
- **Status:** ⬜ Not Started
- **Description:**
  Verify every line of SRS §19 in the live app + record results:
  1. Patient creates an account.
  2. Patient logs in and out.
  3. Patient views active services.
  4. Patient views available dates and slots.
  5. Patient books an available appointment.
  6. System prevents double booking (parallel test).
  7. Booking stored in the online database.
  8. Patient views appointment history and upcoming.
  9. Patient cancels / reschedules per configured rules.
  10. Staff views and manages bookings.
  11. Legacy Excel data validates & imports into the online database.
  12. Excel NOT used for new transactions after migration.
  13. Unauthorized users cannot access staff/admin functions.
- **Acceptance criteria:**
  - All 13 criteria pass with evidence (screen recordings/screenshots) recorded in the PR description.
- **Notes:** Any failure → new fix PR referencing the failing criterion.

---

#### T33 — Final Deployment & Client Demo Prep
- **Owner:** P1 + P2 (shared)
- **Priority:** 9
- **Dependencies:** T30, T31, T32
- **Status:** ⬜ Not Started
- **Description:**
  - Final deploy to GitHub Pages from `main` (live URL: `https://yahiaAlhindi.github.io/The-Perfect-Look-/`).
  - Verify on phone (install + standalone) and desktop.
  - Create **demo accounts** (demo patient, demo staff, demo admin) for the client.
  - Prepare a short client-facing demo script (walking through the MVP acceptance flows).
- **Acceptance criteria:**
  - Live URL reachable from outside; all core flows work in production build.
  - Demo accounts active; client can log in.
- **Notes:** This is the "share link with the client in another country" milestone — the handoff point for approval to proceed to production scope.

---

#### T34 — Documentation & Handover
- **Owner:** Person 2
- **Priority:** 9
- **Dependencies:** T33
- **Status:** ⬜ Not Started
- **Description:**
  - README: project overview, setup (env vars, Supabase config), role accounts, deploy instructions, and how to run the migration tool.
  - Update this task list: mark statuses, note closed/open decisions.
  - Short handover doc for the future production/Expo build (what's reusable: API layer, RBAC, availability engine).
- **Acceptance criteria:**
  - A fresh developer can go from clone → running app in under 15 minutes using the README.
- **Notes:** FINAL task; close it only when everything else is `🟢 Done`.

---

### MILESTONE I — Open Items & Client Input

#### T35 — Open Configuration Items (needs clinic decisions) — DATA GATEKEEPER
- **Owner:** Person 1 (tracks; clinic answers)
- **Priority:** Ongoing
- **Dependencies:** none
- **Status:** 🟡 Needs Input
- **Description:**
  These SRS §21 items are required to finalize migrations, availability, and prices. Track them; anything blocked by them stays `🟡 Needs Input` with a note.
  1. Final list of bookable treatments/services.
  2. Duration for each service.
  3. Pricing + whether price is displayed publicly.
  4. Doctors/therapists assigned per service.
  5. Clinic working hours + holidays.
  6. Slot interval (default 30 min).
  7. Cancellation/rescheduling policy (notice hours, windows).
  8. Multiple treatments per booking (yes/no).
  9. Online payment required (default: No for MVP).
  10. Notification channels to activate (Email / SMS / WhatsApp) + providers.
  11. Final online database/schema details (if provided, else MVP schema stands).
  12. The actual legacy Excel file + exact column structure (required for T25).
  13. Login identifier: email only, or email AND mobile (SRS §6 decision).
  14. UAE privacy/consent texts for Terms & Privacy Policy pages.
- **Status rules:** This task never goes `🟢 Done` until all items have answers (or are explicitly "defer to next phase"). Tick answered items in the Notes.
- **Notes:** Defaults used until answered: 30-min slots, Mon–Sat 10:00–20:00, prices hidden behind "Contact us", No payment, Email-only notifications, email+password login, en/ar.

---

## 5. Execution Order (Recommended Sequence)

Because P1 and P2 work in parallel threads/PRs:

```
Phase 1 (parallel):  T1 (P2)  ·  T2 (P1)  ·  T35 tracking (P1, ongoing)
Phase 2 (parallel):  T3 (P1)  ·  T29 i18n base (P2, after T1)
Phase 3 (parallel):  T4 (P1)  ·  T5 (P1)  ·  T6 (P2, waits on T5)
Phase 4 (parallel):  T8 (P1)  ·  T7 (P2)  ·  T9 (P1)
Phase 5 (parallel):  T12 (P1 core engine)  ·  T18 (P1 RBAC)  ·  T10 (P2)
Phase 6 (parallel):  T13 (P2, waits on T12)  ·  T14 (P1)
Phase 7 (parallel):  T15 (P2, waits on 13+14)  ·  T16 (P1)  ·  T20 (P1, waits on 18)
Phase 8 (parallel):  T17 (P2)  ·  T11 (P2)  ·  T21 (P2)  ·  T19 (P2)
Phase 9 (parallel):  T22 (P2)  ·  T23 (P1)  ·  T25 (P1)  ·  T24 (P2)
Phase 10 (parallel): T26 (P2, waits on 25)  ·  T27 (P1)  ·  T30 (P2)
Phase 11 (parallel): T28 (P2)  ·  T31 (P1)  ·  T32 (P1+P2)
Phase 12:            T33 (P1+P2 deployment & demo)  →  T34 (final document)
```

Critical path (can't be skipped): `T3 → T4/T5 → T9 → T12 → T14 → T16 → T32 → T33`. Anything on this path that stalls holds up the demo — prioritize it.

---

## 6. Status Legend

| Status | Meaning |
| ------ | ------- |
| ⬜ Not Started | Dependencies done; ready to pick up in a thread |
| 🔵 In Progress | Actively being worked on in a thread |
| 🟢 Done | Merged via PR + acceptance criteria verified |
| 🟡 Needs Input | Waiting on client data/decision (see T35) |

**Dependency rule reminder:** Before starting any task, every item in its **Dependencies** list must be `🟢 Done`; otherwise state *"I will not start [TXX] until [TYY] is 🟢 Done"* and wait.

---

*Generated from `The_Perfect_Look_App_Requirements_UPDATED.md` (SRS v1). Update statuses in place as tasks complete.*