# The Perfect Look - Project Tasks Breakdown

Source document: The_Perfect_Look_App_Requirements_UPDATED.md (SRS v2)

This is the dependency-aware implementation plan for the updated
multi-branch medical beauty and wellness platform. The existing tasks keep
their IDs so the work already completed in the repository remains
traceable. New v2 work starts at T36.

## 1. What changed in v2

| New requirement | Tasks that deliver it |
| --- | --- |
| Dubai, Abu Dhabi, and future UAE branches | T21, T37 |
| Unique permanent client number | T5, T37, T22, T25 |
| Website service/brand source and approved content | T1, T10, T11, T36, T46 |
| Price display, online payment, deposits, refunds | T23, T38, T39 |
| Monthly nutrition subscription | T40, T41 |
| BMI, BMR/TDEE, calories, macros, body goals | T42, T44 |
| Eating schedule and nutritionist-reviewed meal plans | T43, T44 |
| Native mobile app path in addition to website/PWA | T30, T45, T47, T48 |
| Health-data privacy, payment security, branch-scoped access | T18, T31, T37, T38, T42 |
| Expanded acceptance and release gates | T32, T33, T47, T48 |

## 2. Technical direction

The platform has one shared backend and business-rule layer:

- **Web:** React, Vite, TypeScript, Tailwind CSS, React Router.
- **Customer mobile:** installable PWA for the approval demo; Expo/React
  Native for the native iOS/Android release.
- **Server/data:** Supabase Auth, PostgreSQL, RLS, RPC/Edge Functions, and
  a typed data-access layer.
- **Payments:** provider-neutral checkout adapter with a UAE-compatible
  provider selected by the client; provider secrets stay server-side.
- **State and validation:** TanStack Query and shared Zod schemas.
- **Migration:** SheetJS-based controlled Excel import with dry-run,
  validation, deduplication, and an import report.
- **Localization:** i18next, Arabic/English, RTL, AED, Asia/Dubai timezone.
- **Web deployment:** GitHub Pages for the static web/PWA approval build;
  Supabase hosts the protected backend operations.
- **Mobile release:** TestFlight and Google Play internal testing before
  production store publishing.

The PWA is useful for the client demo but is not silently treated as the
final native mobile application. T45 and T48 track that distinction.

## 3. Ownership

### Person 1 - Backend, data, security, integrations, and deployment

Owns Supabase schema/migrations, seed data, authentication, RLS/RBAC,
availability, booking/lifecycle logic, branch scope, payments,
subscriptions, nutrition calculations, migration, notifications,
security, release automation, and production deployment.

### Person 2 - Frontend, mobile, UI/UX, content, and QA

Owns the design system, brand implementation, customer web flows,
staff/admin UI, Arabic/RTL, PWA, native mobile shell, checkout screens,
subscription and nutrition screens, responsive QA, and client demo
materials.

### Client / clinic reviewers

Approve the service catalogue, branch data, brand assets, prices, payment
provider, nutrition formulas/content, policies, legal text, and release
scope. These approvals are tracked in T35 and T36.

## 4. Workflow rules

1. One task = one focused thread and one branch named
   task/TXX-short-slug.
2. Open a PR into main for each task and merge it before moving to the
   next dependent task.
3. Before starting a task, every dependency must be marked Done. If any
   dependency is not Done, state: "I will not start this task until [TXX]
   is complete." Do not implement the dependent task.
4. Status values:

   | Status | Meaning |
   | --- | --- |
   | Not Started | Not begun; dependencies may or may not be complete |
   | Needs Input | Waiting for client data, approval, provider, or policy |
   | In Progress | Actively being worked on in a branch/thread |
   | Done | PR merged and acceptance criteria verified |

5. A P1 + P2 task is completed in two hand-offs: backend/API first, then
   the UI or mobile consumer.
6. A task is Done only when its acceptance criteria pass in the relevant
   local/staging/live build and evidence is recorded in the PR.
7. Demo defaults must be labelled and must not be treated as clinic policy.
8. Health, payment, and subscription features require client/qualified
   reviewer approval before production enablement.

## 5. Task plan

### Milestone A - Foundation and existing baseline

#### T1 - Design system, brand-ready UI theme

- **Owner:** Person 2
- **Priority:** Must start first
- **Dependencies:** none
- **Status:** Not Started
- **Description:**
  - Set up the React/Vite/TypeScript/Tailwind app shell and design tokens.
  - Build reusable buttons, inputs, selects, checkboxes, cards, badges,
    dialogs, tabs, toasts, loading states, empty states, and page headers.
  - Support responsive web, phone-sized PWA, Arabic/RTL, and future native
    mobile token reuse.
  - Use placeholder brand tokens until the approved assets arrive from
    T36; do not hard-code a guessed final palette.
- **Acceptance criteria:**
  - Patient and admin screens consume shared tokens and components.
  - Responsive checks pass at 360px, 768px, and 1280px.
  - A component demo or usage document exists.
  - Brand assets can be swapped from one configuration layer.
- **Notes:** T46 applies the approved client assets and final catalogue
  content after T36.

#### T2 - Repository structure and web deployment pipeline

- **Owner:** Person 1
- **Priority:** Must start first
- **Dependencies:** none
- **Status:** Done
- **Description:**
  - Maintain web, Supabase, tools, and docs structure.
  - Keep GitHub Pages base-path and CI build/typecheck/deploy pipeline
    working.
  - Keep environment variables and secrets out of source control.
- **Acceptance criteria:**
  - The compiling app deploys to the configured GitHub Pages URL.
  - The PR-to-merge-to-deploy path has been proven.
  - No real keys are committed.
- **Notes:** Existing baseline completed; re-run after major release work.

#### T3 - Supabase baseline schema and project

- **Owner:** Person 1
- **Priority:** 1
- **Dependencies:** T2
- **Status:** Done
- **Description:**
  - Maintain the baseline profiles, services, staff, availability,
    blocked periods, holidays, appointments, notifications, audit logs,
    app settings, Auth integration, and RLS.
  - Keep appointment concurrency and patient-owned data protections.
- **Acceptance criteria:**
  - Existing migrations apply cleanly.
  - A patient cannot read another patient's appointments.
  - Baseline status values, indexes, constraints, and RLS tests pass.
- **Notes:** Done for the original booking baseline. T37 adds the v2
  branch, client-number, pricing, and access-scope schema; T3 must not be
  marked as v2-complete until that extension is merged.

#### T4 - Baseline seed data

- **Owner:** Person 1
- **Priority:** 1
- **Dependencies:** T3
- **Status:** Done
- **Description:**
  - Keep demo services, staff, weekly availability, working hours,
    cancellation defaults, AED settings, and holidays idempotent.
- **Acceptance criteria:**
  - Seed script can be re-run without duplicate rows or overwriting clinic
    edits.
  - Services and settings are available through the data layer.
- **Notes:** Demo values only. T36 supplies approved catalogue/brand data;
  T37 adds demo Dubai/Abu Dhabi branch records.

#### T5 - Authentication, session, and profile API

- **Owner:** Person 1
- **Priority:** 2
- **Dependencies:** T3
- **Status:** Done
- **Description:**
  - Keep Supabase Auth registration, login, logout, reset, session
    persistence, profile creation, and duplicate email/mobile handling.
  - Normalize UAE/international mobile numbers and keep passwords managed
    by Supabase Auth.
- **Acceptance criteria:**
  - Register -> login -> logout -> reset works through the API.
  - Every new user receives a profile and role=customer/patient by
    default.
  - Patient-owned access and mapped errors are tested.
- **Notes:** The permanent client number is added by T37 and must appear
  in customer-facing flows before the v2 account feature is Done.

### Milestone B - Customer account and profile

#### T6 - Customer authentication pages

- **Owner:** Person 2
- **Priority:** 2
- **Dependencies:** T1, T5
- **Status:** Not Started
- **Description:** Build registration, login, forgot/reset password,
  logout, consent, language switch, validation, and return-to-booking
  behavior.
- **Acceptance criteria:** Happy/error paths work in English and Arabic,
  required consent blocks submission, and the UI works on mobile.
- **Notes:** Include a visible client number after account creation once
  T37 exposes it.

#### T7 - Customer profile UI

- **Owner:** Person 2
- **Priority:** 3
- **Dependencies:** T6, T8
- **Status:** Not Started
- **Description:** View/edit allowed profile fields, client number,
  language, consent preferences, and password change. Keep sensitive
  nutrition data in its own protected flow.
- **Acceptance criteria:** Changes persist, uniqueness errors are friendly,
  client number cannot be edited, and the customer cannot access another
  profile.

#### T8 - Profile and consent API

- **Owner:** Person 1
- **Priority:** 3
- **Dependencies:** T3, T5
- **Status:** Not Started
- **Description:** Implement own-profile GET/PUT, allowed field rules,
  password change, consent history, data-request entry point, and
  server-side validation.
- **Acceptance criteria:** RLS prevents cross-customer updates; consent
  records include version and timestamp; sensitive fields are not exposed
  to public queries.

### Milestone C - Catalogue, branches, and availability

#### T9 - Service catalogue API baseline

- **Owner:** Person 1
- **Priority:** 3
- **Dependencies:** T3, T4
- **Status:** Done
- **Description:** Keep public active-service list/detail and admin CRUD
  with duration, description, price visibility, staff type, booking
  rules, and audit logging.
- **Acceptance criteria:** The frontend reads services from the database;
  inactive services are hidden; admin edits are reflected without a code
  deploy.
- **Notes:** Existing baseline implementation is complete. T37 adds
  branch pricing/availability and T46 loads the approved client content.

#### T10 - Customer services and branches browsing UI

- **Owner:** Person 2
- **Priority:** 3
- **Dependencies:** T1, T9
- **Status:** Not Started
- **Description:** Build service categories, service detail, branch list,
  branch detail, price/duration display, preparation/aftercare content,
  and Book actions.
- **Acceptance criteria:** Active data renders from the API; customer can
  select a branch; loading/empty/error states and English/Arabic work.
- **Notes:** Use demo content until T36/T46 are complete.

#### T11 - Service catalogue admin UI

- **Owner:** Person 2
- **Priority:** 4
- **Dependencies:** T18, T20, T37
- **Status:** Not Started
- **Description:** CRUD for categories, services, packages, branch
  availability, branch prices, duration, buffers, provider type,
  booking rules, images/content, publish state, and price-on-request.
- **Acceptance criteria:** Authorized users can update catalogue data;
  branch-scoped users cannot edit another branch; public UI reflects
  approved changes.

#### T12 - Branch-aware availability engine

- **Owner:** Person 1
- **Priority:** 4
- **Dependencies:** T3, T4, T9, T37
- **Status:** Done
- **Description:** Generate slots from branch hours, service duration and
  buffers, provider schedules, leave, holidays, closures, blocks,
  capacity, and existing appointments. Include branch and timezone in
  every query. Server-side `reserve_slot()` re-validates the whole
  availability stack and serialises concurrent requests per provider
  + branch so exactly one overlapping booking succeeds.
- **Acceptance criteria:**
  - Slots respect branch/provider rules and Asia/Dubai time.
    - Verified by `supabase/tests/availability_engine.sql` TEST 1
      (19 slots in branch hours, times within 10:00–20:00 Asia/Dubai,
      timezone + branch carried in every row), TEST 3 (leave removes
      covered slots) and TEST 4 (existing appointment + buffer both
      remove the right starts).
  - A staff member working at two branches cannot be double-booked.
    - Verified by TEST 5: Dubai 10:00 booked -> Abu Dhabi 10:00
      absent from slot list; `reserve_slot()` at Abu Dhabi 10:00
      rejected; raw INSERT overlapping across branches rejected by the
      DB `appt_no_overlapping_staff` EXCLUDE constraint; same-start
      insert at a second branch rejected by the T3 unique index.
  - Parallel requests for one slot result in exactly one successful
    booking.
- Verified by `supabase/tests/availability_engine_parallel_worker.sql`
      spawned by `.ps1` / `.sh` drivers: N concurrent `reserve_slot()`
      calls for one slot -> exactly one 'success' in
      `availability_parallel_results`; DB EXCLUDE constraint and
      advisory lock provide the boundary across every channel.
  - Branch capacity (`max_concurrent_appointments`) blocks a second
    concurrent slot when the limit is reached.
    - Verified by TEST 6 (capacity 1 -> second provider's 10:00 gone,
      11:00 open; `reserve_slot()` rejected with the stable message).
  - Reservation snapshots (price, buffer, client number, service name)
    are captured at booking time and immune to later catalogue edits.
    - Verified by TEST 7 (`TPL-` appointment_ref, client_number,
      service_name_snapshot, price_snapshot, currency_snapshot,
      buffer_minutes, status Pending).
  - Authorization: signed-in patient may book only for themselves;
    anon JWT is rejected.
    - Verified by TEST 8.
  - Layout and branch-scope rejections: closed day, outside hours,
    off-grid start, provider not at branch, missing provider.
    - Verified by TEST 9 (Sunday, 21:00, 10:15, NULL provider,
      provider-B-at-abu-dhabi, buffer-service-at-abu-dhabi).
- **Notes:** Migration 006 extends branches/appointments and adds
  `get_availability()` + `reserve_slot()`. Typecheck + build pass in
  `web/`. Run `supabase db reset` then the test suite against the
  local or online DB to record evidence (see supabase/README.md).

#### T13 - Availability picker UI

- **Owner:** Person 2
- **Priority:** 4
- **Dependencies:** T12
- **Status:** Done
- **Description:** Build branch -> provider (optional) -> date -> slot
  selection with mobile-friendly day/week navigation and clear
  unavailable states.
- **Acceptance criteria:** UI matches API availability, carries branch and
  slot into booking, and renders in English/Arabic/RTL.
- **Notes:** Implemented in branch `t3code/availability-picker-ui`:
  `web/src/components/AvailabilityPicker.tsx` + `.css` (three-step
  branch -> optional provider -> date/slot flow; previous/next/today week
  navigation; day states past/closed/unavailable/limited/available with
  legend; slots only ever sourced from the T12 `get_availability` RPC;
  `BookingSelection` passed to the parent). `supabase/migrations/
  007_branch_providers.sql` adds the `get_branch_providers()` RPC
  (migration 006 from PR #10 had no provider-list function). Demo wiring
  in `web/src/App.tsx` (service select, EN/AR + RTL toggle via
  `web/src/i18n.ts`, booking summary carrying branch/provider/date/time).
  Frontend verified with `npm run typecheck` + `npm run build`.

### Milestone D - Appointment booking and lifecycle

#### T14 - Appointment booking API

- **Owner:** Person 1
- **Priority:** 5
- **Dependencies:** T5, T9, T12, T37
- **Status:** Not Started
- **Description:** Transactional appointment creation with server-side
  re-check of branch, price, service, provider, slot, notice period,
  booking rules, and customer identity. Generate a unique Appointment ID
  and store the client number and branch.
- **Acceptance criteria:** Double-booking is impossible; inactive/invalid
  service or slot is rejected; confirmation data includes appointment ID,
  client number, branch, service, time, and payment status.
- **Notes:** Payment may initially be unpaid/pay-at-clinic; T38 adds
  online checkout and payment-required transitions.

#### T15 - Customer booking flow UI

- **Owner:** Person 2
- **Priority:** 5
- **Dependencies:** T13, T14
- **Status:** Not Started
- **Description:** Mobile-friendly wizard: service -> branch -> provider
  -> date/slot -> customer review -> price/payment choice -> confirmation.
  Handle login redirect and slot-taken errors.
- **Acceptance criteria:** A customer can create a real appointment; the
  review shows price/policy/branch; errors are friendly and localized.

#### T16 - Appointment lifecycle API

- **Owner:** Person 1
- **Priority:** 5
- **Dependencies:** T14, T37
- **Status:** Not Started
- **Description:** List/detail/upcoming/history, cancel, reschedule,
  confirm, check-in, complete, no-show, and audit history. Apply
  branch-scoped staff permissions and notice/refund rules.
- **Acceptance criteria:** Cancel releases a slot; reschedule atomically
  releases old and reserves new slot; customer access is own-record only.

#### T17 - My appointments UI

- **Owner:** Person 2
- **Priority:** 5
- **Dependencies:** T13, T16
- **Status:** Not Started
- **Description:** Upcoming/history cards with client number, Appointment
  ID, branch, service, provider, time, status, payment status, cancel,
  reschedule, and policy messages.
- **Acceptance criteria:** Actions update lists and availability; status
  badges and empty/error states work in English and Arabic.

### Milestone E - Staff, branch, and admin portal

#### T18 - Roles, invitations, and branch-scoped RBAC

- **Owner:** Person 1
- **Priority:** 4
- **Dependencies:** T3, T5, T37
- **Status:** Not Started
- **Description:** Add customer, receptionist, branch manager, provider,
  nutritionist, finance, administrator, and super-administrator roles.
  Enforce branch scope in claims/RLS/API and protect health/payment data.
- **Acceptance criteria:** A customer receives 403 for staff APIs; a branch
  user cannot read another branch's records; finance can see payments
  without unnecessary nutrition data; admin access is auditable.

#### T19 - Staff dashboard UI

- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T16, T18, T20
- **Status:** Not Started
- **Description:** Today's/upcoming calendar and list, branch filter,
  customer/client-number search, service/provider/status filters, and
  permitted status actions.
- **Acceptance criteria:** Staff see only authorized branches and can
  update allowed appointment statuses from desktop or mobile layout.

#### T20 - Admin APIs

- **Owner:** Person 1
- **Priority:** 5
- **Dependencies:** T16, T18, T37
- **Status:** Not Started
- **Description:** Branch, staff, service, availability, appointment,
  customer lookup, settings, payment/subscription, report, and audit
  endpoints. Include create-on-behalf booking.
- **Acceptance criteria:** Every route has server-side role and branch
  checks; availability changes affect new lookups; actions are logged.

#### T21 - Branch and staff management UI

- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T18, T20, T37
- **Status:** Not Started
- **Description:** Manage branches, hours, holidays, closures, staff
  invitations, role, branch assignment, provider schedule, leave, and
  blocked periods.
- **Acceptance criteria:** Changes affect availability after refresh;
  branch managers cannot manage outside their scope; destructive actions
  require confirmation.

#### T22 - Admin appointment and customer management UI

- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T16, T18, T20
- **Status:** Not Started
- **Description:** Search by client number/name/mobile/email, view permitted
  customer history, create appointments on behalf, and manage all
  approved status transitions.
- **Acceptance criteria:** Search is branch-scoped, status changes preserve
  slot consistency, and customer health data is not shown to roles that
  do not need it.

#### T23 - Reports and export API

- **Owner:** Person 1
- **Priority:** 7
- **Dependencies:** T20, T37
- **Status:** Not Started
- **Description:** Export filtered appointments, clients, branch
  utilization, revenue/payment records, subscriptions, and migration
  results as authorized CSV/Excel reports.
- **Acceptance criteria:** Filters are applied server-side, exports contain
  only permitted fields, and migration results are retrievable.

#### T24 - Reports and export UI

- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T18, T23
- **Status:** Not Started
- **Description:** Admin report screens, filters, export buttons, download
  state, and permission-aware errors.
- **Acceptance criteria:** One action exports the current authorized
  dataset; no sensitive fields leak to unauthorized roles.

### Milestone F - Legacy Excel migration

#### T25 - Excel migration and validation engine

- **Owner:** Person 1
- **Priority:** 6
- **Dependencies:** T3, T4, T37
- **Status:** Not Started
- **Description:** Extend the SheetJS tool for customers, legacy IDs,
  client-number generation/mapping, branches, services, staff, historical
  appointments, and approved status normalization. Support dry run,
  duplicate detection, idempotency, and row-level reports.
- **Acceptance criteria:** A fixture imports correctly; duplicate/invalid/
  failed rows are separated; rerunning does not duplicate records; the
  source workbook is byte-identical.
- **Notes:** Do not import payments/subscriptions unless the client
  supplies reliable columns and approves the mapping.

#### T26 - Migration admin UI

- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T18, T23, T25
- **Status:** Not Started
- **Description:** Admin-only upload, mapping preview, dry-run/live choice,
  run state, result counts, row errors, and downloadable report.
- **Acceptance criteria:** Upload -> validate -> migrate -> report works
  end-to-end and is guarded by admin/RLS.

### Milestone G - Notifications and localization

#### T27 - Notification service

- **Owner:** Person 1
- **Priority:** 7
- **Dependencies:** T5, T14, T16
- **Status:** Not Started
- **Description:** Confirmation/reminder/cancellation/reschedule,
  payment, refund, subscription renewal/failure, and nutrition-plan
  notifications through in-app and client-selected external channels.
- **Acceptance criteria:** Events create one auditable notification;
  retries are safe; provider failure does not duplicate a booking or
  charge.

#### T28 - In-app notifications UI

- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T27
- **Status:** Not Started
- **Description:** Notification bell/list, unread count, read state, and
  links to appointment/payment/subscription/nutrition records.
- **Acceptance criteria:** Relevant users see events, unread state clears,
  and unauthorized records cannot be opened.

#### T29 - Arabic, English, and RTL

- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T1
- **Status:** Not Started
- **Description:** Translate every screen, form, error, status, payment,
  subscription, nutrition, and disclaimer string. Support RTL, localized
  date/number/currency formatting, and persisted language preference.
- **Acceptance criteria:** A language toggle flips the full app without
  layout artifacts; no user-facing hard-coded English remains.

### Milestone H - PWA, security, and baseline QA

#### T30 - PWA and shared mobile-ready shell

- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T1, T2
- **Status:** Not Started
- **Description:** Configure manifest/icons, installability, app-shell
  caching, standalone display, safe areas, touch targets, offline state,
  and mobile navigation.
- **Acceptance criteria:** PWA installs and opens standalone on a phone;
  Lighthouse installability passes; offline shell has a friendly data
  error state.
- **Notes:** This is the demo mobile experience. T45 tracks the native
  app.

#### T31 - Security, privacy, and validation hardening

- **Owner:** Person 1
- **Priority:** 8
- **Dependencies:** T5, T18, T25, T37
- **Status:** Not Started
- **Description:** Final RLS/branch-scope audit, server-side validation,
  audit logs, secret scan, HTTPS, backups/recovery, rate limits, health
  data policies, payment webhook security, consent, retention, and UAE
  privacy review checklist.
- **Acceptance criteria:** Cross-customer/branch access tests fail safely;
  admin/payment/nutrition actions are auditable; no secrets are exposed;
  recovery and privacy documents exist.

#### T32 - Core appointment end-to-end testing

- **Owner:** P1 + P2
- **Priority:** 8
- **Dependencies:** T14, T16, T17, T19, T25, T26, T37
- **Status:** Not Started
- **Description:** Verify registration, client number, services,
  branches, availability, booking concurrency, appointment lifecycle,
  staff operations, migration, RLS, and Arabic/English against the v2
  acceptance criteria.
- **Acceptance criteria:** Test evidence covers each core case in a
  staging/live build; every failure has a linked fix task.

#### T33 - Browser/PWA client demo deployment

- **Owner:** P1 + P2
- **Priority:** 9
- **Dependencies:** T30, T31, T32, T46
- **Status:** Not Started
- **Description:** Deploy the approved website/PWA build, create safe demo
  accounts/data, verify phone/desktop behavior, and prepare a client demo
  script covering branches, booking, client number, and catalogue.
- **Acceptance criteria:** External client can open the URL, sign in with
  demo accounts, install the PWA, and complete the approved demo flows.
- **Notes:** Do not use live card credentials or real health data in the
  demo.

#### T34 - Documentation and handover

- **Owner:** Person 2
- **Priority:** 9
- **Dependencies:** T33
- **Status:** Not Started
- **Description:** Update README, environment setup, Supabase/RLS notes,
  migration runbook, roles, client demo script, brand/content workflow,
  payment/subscription runbook, and native-mobile handover.
- **Acceptance criteria:** A new developer can run the project from the
  README; all open decisions and release gates are documented.

### Milestone I - Client input and requirements gate

#### T35 - Open clinic decisions and release gate

- **Owner:** Person 1 tracks; clinic/client answers
- **Priority:** Ongoing / blocking
- **Dependencies:** none
- **Status:** Needs Input
- **Description:** Obtain decisions for:
  1. final services/packages, English/Arabic copy, duration, buffers,
     branch pricing, and provider assignments;
  2. exact branches, addresses, contacts, hours, holidays, slot interval,
     capacity, and branch policies;
  3. public price visibility, VAT/fees, deposits, pay-at-clinic,
     cancellations, refunds, and no-shows;
  4. payment provider, supported methods, sandbox/live credentials, and
     webhook ownership;
  5. monthly subscription plans, prices, entitlements, grace, trial,
     cancellation, and basic-calculator access;
  6. nutritionist-approved formulas, target ranges, meal content,
     allergies, disclaimers, and review workflow;
  7. client-number format and legacy matching rules;
  8. login identifier, OTP, notification providers, and channels;
  9. native-app-first versus PWA-demo decision, store accounts, and
     release ownership;
  10. Terms, Privacy Policy, health consent, marketing consent, and
      retention/deletion requirements;
  11. legacy Excel workbook, columns, and historical payment/subscription
      migration scope.
- **Acceptance criteria:** Every item is answered or explicitly deferred
  to a named later release. Answers are recorded in the SRS and task
  notes.
- **Notes:** Until answers arrive, use labelled demo defaults only. Any
  task that needs a missing decision must be marked Needs Input rather
  than quietly guessing.

#### T36 - Client website, service catalogue, and brand discovery

- **Owner:** Person 2 with client
- **Priority:** Immediate, before final UI/content
- **Dependencies:** none
- **Status:** Needs Input
- **Description:** Receive and review the client website/link, extract the
  authoritative services, categories, descriptions, prices, branch
  details, brand colors, logo, app-icon direction, images, and copy.
  Produce a content/asset inventory with unresolved conflicts for client
  approval.
- **Acceptance criteria:** The source link is recorded; every planned
  service and branch has a source or explicit TBD; approved brand assets
  and content are versioned; discrepancies are listed for T35.
- **Notes:** The user said a link will be provided. This task cannot be
  marked Done until the link and approval are available.

### Milestone J - Multi-branch and customer identity v2

#### T37 - Multi-branch, client-number, and pricing schema extension

- **Owner:** Person 1
- **Priority:** 1
- **Dependencies:** T3, T4
- **Status:** Done
- **Description:** Add branches, branch hours/closures, staff-branch
  assignments, service-branch availability/pricing, immutable client
  number, branch on appointments, branch-scoped RLS, price snapshots,
  package/add-on relationships, and migration mappings.
- **Acceptance criteria:**
  - Demo Dubai and Abu Dhabi branches seed idempotently.
    - Verified by `supabase/tests/multi_branch_pricing_schema.sql` (TEST 6).
  - Client numbers are unique, immutable, collision-safe, searchable,
    and visible through authorized APIs.
    - Trigger-generated `TPL-######` numbers, unique index, immutability
      trigger, and `search_clients()` RPC (TEST 1).
  - A user cannot read/write another branch's protected data.
    - `branch_access`-driven RLS on branches/hours/pricing/appointments;
      managers scoped to their own branch (TEST 2/4).
  - Appointment and price snapshots preserve historical truth.
    - `service_name_snapshot`/`price_snapshot`/`client_number` captured
      at booking and immune to later catalogue edits (TEST 4).
- **Notes:** Use demo branches until T35/T36 supplies the official data.
  Migrations 004–005 and the RLS acceptance test are included in the
  T37 PR; run the test against the local/online project to record
  evidence (see supabase/README.md).

### Milestone K - Payments and subscriptions

#### T38 - Payment domain, checkout API, and webhook integration

- **Owner:** Person 1
- **Priority:** 6
- **Dependencies:** T18, T20, T35, T37
- **Status:** Needs Input
- **Description:** Implement provider adapter, checkout/payment intents,
  full/deposit/pay-at-clinic options, payment status, invoices, refunds,
  manual payment, signed webhooks, idempotency, retries, and appointment
  payment transitions.
- **Acceptance criteria:** Sandbox success/failure/refund/replay flows
  update the database exactly once; appointment status cannot claim paid
  before provider confirmation; no card details are stored.
- **Notes:** Provider selection and credentials are required before live
  integration. A provider-neutral domain contract may be prepared first.

#### T39 - Customer checkout and finance UI

- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T38, T1
- **Status:** Not Started
- **Description:** Price summary, payment method, hosted checkout/redirect,
  success/failure/pending states, receipts, balances, refund messages,
  and finance/admin payment views.
- **Acceptance criteria:** Customer never sees a trusted client-side price;
  sandbox payment states are clear and localized; finance roles see only
  permitted records.

#### T40 - Subscription plans and entitlement API

- **Owner:** Person 1
- **Priority:** 6
- **Dependencies:** T35, T37, T38
- **Status:** Needs Input
- **Description:** Add plans, monthly recurring billing, subscription
  status transitions, renewal/failure/grace/cancel/pause/refund events,
  invoices, webhook replay, and entitlement checks for nutrition features.
- **Acceptance criteria:** Active, past-due, cancelled, expired, and
  payment-failed fixtures produce the correct access; duplicate webhooks
  are harmless; all transitions are audited.

#### T41 - Subscription and membership UI

- **Owner:** Person 2
- **Priority:** 6
- **Dependencies:** T39, T40
- **Status:** Not Started
- **Description:** Plans/comparison, checkout entry, active membership,
  next billing date, invoice history, cancel/pause, renewal failure,
  expired-access, and entitlement messaging.
- **Acceptance criteria:** The UI reflects server entitlement after every
  test event and never unlocks premium nutrition features from local state
  alone.

### Milestone L - Nutrition and wellness

#### T42 - Versioned nutrition calculation engine

- **Owner:** Person 1
- **Priority:** 6
- **Dependencies:** T3, T18, T35
- **Status:** Needs Input
- **Description:** Implement tested, unit-aware, versioned BMI, BMR, TDEE,
  calorie target, protein/fat/carbohydrate, weight goal, body-fat/muscle
  guidance, validation limits, and progress calculations. Store formula
  version and input/output snapshot.
- **Acceptance criteria:** Approved fixtures match the nutritionist's
  expected results; invalid/extreme inputs are handled safely; outputs
  carry the estimate/disclaimer; calculations cannot leak across users.
- **Notes:** Do not copy an open-source implementation until its license
  and formula suitability are reviewed. The client/nutritionist must
  approve formulas and ranges.

#### T43 - Nutrition profile, meal plan, and admin content API

- **Owner:** Person 1 + nutritionist reviewer
- **Priority:** 7
- **Dependencies:** T20, T40, T42, T35
- **Status:** Needs Input
- **Description:** Store consented measurements/goals, dietary
  preferences/allergies, plan versions, meals, portions, substitutions,
  eating times, weekly schedules, progress check-ins, nutritionist
  review, and subscription entitlement checks.
- **Acceptance criteria:** Only an active entitlement can access the
  configured premium plan; staff access follows role; plan revisions are
  versioned; nutritionist approval is recorded.

#### T44 - Customer nutrition and wellness UI

- **Owner:** Person 2
- **Priority:** 7
- **Dependencies:** T41, T42, T43, T1
- **Status:** Not Started
- **Description:** Onboarding measurements/goals, calculator results,
  BMI/calorie/macro explanation, subscription gate, eating schedule,
  meal plan, progress updates, disclaimers, and error/empty states.
- **Acceptance criteria:** Customer can complete the approved fixture flow
  in English/Arabic; locked/expired subscription behavior is clear; no
  health data appears in public URLs or unauthorized screens.

### Milestone M - Native mobile and final release

#### T45 - Native iOS/Android customer app shell

- **Owner:** Person 2 + Person 1
- **Priority:** 7
- **Dependencies:** T29, T30, T37, T35
- **Status:** Needs Input
- **Description:** Create the Expo/React Native app shell, navigation,
  authentication, shared API client, brand assets, branch/service browse,
  booking, appointments, checkout, subscription, and nutrition routes.
  Reuse domain contracts and tests from the web implementation.
- **Acceptance criteria:** App builds for iOS and Android, authenticates
  against the same backend, respects RLS/entitlements, supports RTL,
  handles offline/error states, and passes internal device testing.
- **Notes:** Store accounts, app ownership, and whether this is required
  for the first demo are T35 decisions.

#### T46 - Approved brand and catalogue implementation

- **Owner:** Person 2
- **Priority:** 4
- **Dependencies:** T1, T9, T10, T11, T36
- **Status:** Needs Input
- **Description:** Replace placeholders with approved logo, colors,
  typography, app icon, imagery, service copy, branch content, prices,
  disclaimers, and localized catalogue data.
- **Acceptance criteria:** Client approves a visual/content review on
  website, PWA, and relevant mobile screens; no fabricated service or
  price remains in the production seed.

#### T47 - Full v2 end-to-end and launch-readiness test

- **Owner:** P1 + P2
- **Priority:** 8
- **Dependencies:** T31, T32, T38, T40, T41, T44, T45, T46
- **Status:** Not Started
- **Description:** Test the complete website/PWA/native path: client
  number, branches, services, booking, payment, refunds,
  subscription lifecycle, calculations, meal plans, notifications,
  branch-scoped RBAC, migration, privacy, and audit evidence.
- **Acceptance criteria:** Every SRS v2 MVP criterion passes with
  screenshots/logs/test reports; open defects are triaged; client signs
  off the release candidate.

#### T48 - Production release and handover

- **Owner:** P1 + P2
- **Priority:** 9
- **Dependencies:** T33, T34, T47
- **Status:** Not Started
- **Description:** Configure production domains, Supabase settings,
  payment production credentials, monitoring, backups, notification
  providers, native app signing, TestFlight/Play release, store
  metadata, support/runbooks, and final client handover.
- **Acceptance criteria:** Approved release is deployed; mobile builds are
  available to the intended audience; production secrets are protected;
  rollback/support procedures and ownership are documented.

## 6. Recommended execution order

The current repository can continue from its completed baseline as follows:

Phase 1: T1 + T36 (design/content discovery in parallel)
Phase 2: T37 + T29 + T6/T8 (schema extension, localization, account UI/API)
Phase 3: T18 + T12 + T13 (RBAC and branch availability)
Phase 4: T14 + T15 + T16 + T17 (booking and lifecycle)
Phase 5: T10 + T11 + T19 + T20 + T21 + T22 + T23 + T24 + T25 + T26 (catalogue, operations, and migration)
Phase 6: T27 + T28 + T30 + T31 + T32 (notifications, PWA, security, QA)
Phase 7: T35 decisions + T38 + T39 (payment)
Phase 8: T40 + T41 + T42 + T43 + T44 (subscription and wellness)
Phase 9: T46 + T33 (approved content and browser/PWA demo)
Phase 10: T45 + T47 + T48 (native app and production release)

Critical paths:

- **Booking:** T37 -> T12 -> T14 -> T16 -> T18/T20 -> T32.
- **Payment:** T35 -> T37/T18/T20 -> T38 -> T39.
- **Nutrition:** T35 -> T38 -> T40 -> T41, and T35 -> T42 -> T43 -> T44.
- **Client-ready release:** T36/T46 -> T33, then T45 -> T47 -> T48.

## 7. Status legend

| Status | Meaning |
| --- | --- |
| Not Started | Work has not begun |
| Needs Input | Waiting on client/clinic/provider information or approval |
| In Progress | Work is active in a branch/thread |
| Done | PR merged and acceptance criteria verified |

Dependency reminder: a task must not start until every listed dependency
is Done. T35 and T36 are intentionally open because the client website,
service list, brand assets, policies, provider, and nutrition approvals
have not yet been supplied.
