# The Perfect Look - Software Requirements Specification

## Document control

- **Product:** The Perfect Look health and beauty clinic platform
- **Revision:** SRS v2 - client requirement update
- **Status:** Draft for client validation
- **Primary market:** United Arab Emirates, initially Dubai and Abu Dhabi
- **Primary currency and timezone:** AED and Asia/Dubai
- **Languages:** English and Arabic, including RTL support

This revision replaces the earlier single-clinic booking scope. It keeps
the online database and legacy Excel migration requirements, and adds
multi-branch operations, client identity, service payments, nutrition
membership, wellness calculations, and a mobile-app delivery path.

## 1. Product objective and scope

The system shall provide a branded website and mobile experience for a
medical beauty and wellness clinic operating across UAE branches. It shall
allow a customer to:

1. Discover the clinic, branches, services, packages, prices, and
   availability.
2. Create an account with a permanent unique client number.
3. Select a branch, service, preferred staff member when applicable, and
   appointment time.
4. See a price summary and pay online, pay a configured deposit, or choose
   pay-at-clinic when that option is enabled.
5. View, cancel, and reschedule appointments according to clinic policy.
6. Purchase and manage a monthly nutrition/wellness subscription.
7. Enter personal measurements and goals to calculate BMI, calorie needs,
   protein, fat, carbohydrate, and weight/muscle targets.
8. Receive a personalized eating schedule or meal-plan content available
   under the selected subscription.

Clinic staff shall be able to manage customers, appointments, branches,
services, staff schedules, payments, subscriptions, and nutrition content
from a protected portal.

The product is a scheduling and wellness-support platform. It shall not
present itself as an emergency service, make an autonomous medical
diagnosis, prescribe medication, or replace a licensed clinician or
nutritionist review.

### 1.1 Delivery channels

- **Public website:** responsive marketing, service catalogue, branch
  information, account entry, booking, payment, and subscription flows.
- **Customer web application:** authenticated customer dashboard, bookings,
  payments, subscription, and wellness features.
- **Mobile application:** customer-facing iOS/Android experience using the
  same backend and business rules. The current browser-first implementation
  may be delivered as an installable PWA for the approval demo, but a native
  app release remains a separately tracked delivery unless the client
  explicitly accepts the PWA as the final mobile application.
- **Staff/admin portal:** responsive protected web interface for clinic
  operations.

## 2. Product terminology

- **Customer / client:** a person receiving a clinic service or using the
  wellness program. Existing code and data may use the term patient.
- **Client number:** a permanent human-readable identifier for a customer;
  it is different from an internal database UUID.
- **Branch:** a physical clinic location in an emirate/city.
- **Service:** a treatment, consultation, package, or bookable wellness
  offering.
- **Provider:** a doctor, therapist, technician, receptionist, or
  nutritionist who may be assigned to work.
- **Wellness plan:** nutrition calculations, goals, meal schedule, and
  related content. It is not a medical diagnosis.

## 3. Stakeholders and roles

The authorization model shall support the following roles and scope them
to the branches they are allowed to access:

- **Customer:** manages their own profile, appointments, payments,
  subscription, and wellness data.
- **Receptionist / booking staff:** manages customers and appointments for
  assigned branches.
- **Branch manager:** manages branch operations, staff schedules, services,
  and reports for assigned branches.
- **Provider / therapist / clinician:** sees assigned appointments and
  permitted customer information.
- **Nutritionist:** manages or reviews nutrition profiles, plans, and meal
  content according to clinic policy.
- **Finance staff:** views payment, refund, invoice, and subscription
  records without unnecessary health-data access.
- **Administrator:** manages all branches, services, users, settings,
  integrations, and reports.
- **Super administrator:** controls system-level configuration and support
  access where required.

## 4. Brand, content, and design requirements

- The website and app shall use the approved The Perfect Look brand
  identity, including logo, icon, typography, color palette, imagery,
  tone, and spacing.
- The service catalogue and public content shall be sourced from the
  clinic's approved website/link and reviewed by the client before
  publication.
- The mobile app icon, splash screen, manifest, and store artwork shall
  use the approved brand assets. Do not invent final colors or a logo
  treatment before the client supplies or approves them.
- All customer-facing flows shall support English and Arabic. Arabic shall
  use RTL layout, localized labels, dates, numbers, validation messages,
  and status names.
- The design shall be accessible and usable on small phones, tablets, and
  desktop screens, with touch targets suitable for mobile use.

## 5. Customer account, authentication, and client number

### 5.1 Registration

Registration shall support:

- Full name.
- Mobile number, normalized to an agreed UAE/international format.
- Email address.
- Password and confirmation.
- Date of birth or age, when required for the wellness feature.
- Gender/biological profile fields only where required by an approved
  calculation or clinic workflow.
- Preferred language.
- Optional marketing consent, kept separate from required service consent.
- Required acceptance of Terms of Service, Privacy Policy, and health-data
  disclaimer where applicable.

The system shall validate required fields, email/mobile format, password
policy, duplicate accounts, and consent before account creation.

### 5.2 Authentication

- Sign in with the client-approved identifier: email, mobile, or both.
- Support logout, password reset, session expiry, and secure session
  persistence.
- OTP or verified mobile login may be enabled after the provider and
  business policy are confirmed.
- Passwords shall be managed by the authentication provider and never
  stored as plain text.

### 5.3 Unique client number

- A client number shall be generated when a customer account is created
  or imported.
- It shall be globally unique, immutable, searchable by authorized staff,
  and shown in the customer profile and booking confirmations.
- The client number shall not expose sensitive information such as date of
  birth or phone number.
- The final prefix, length, and formatting are client configuration. The
  implementation shall support a configurable format and collision-safe
  generation.
- Imported customers shall retain a mapped legacy identifier where useful,
  but the new client number remains the system identifier for future
  operations.

## 6. Branches and UAE locations

The system shall support multiple active branches, initially including
Dubai and Abu Dhabi and expandable to other UAE emirates.

Each branch shall support:

- Branch ID, name, emirate, city, address, phone, email, and optional map
  coordinates/link.
- Active/inactive status and public display order.
- Branch-specific working hours, holidays, closures, and timezone.
- Services offered at the branch, branch-specific prices when needed, and
  branch-specific booking rules.
- Staff/provider assignments and schedules.
- Branch-specific blocked periods and capacity rules.

Booking availability shall always be calculated for a selected branch.
Staff who work in more than one branch shall not be double-booked across
overlapping branch schedules.

## 7. Services, treatments, packages, and catalogue

The service catalogue shall be dynamic data managed in the online database.
The frontend shall not require a code deployment when the clinic changes
an offering.

The final catalogue shall be imported or entered from the client-provided
website/link and approved by the client. It may include categories such
as:

- Skin care and facial treatments.
- Advanced hair care solutions.
- Laser hair removal.
- Clinical nutrition and weight management.
- Body contouring and fat reduction.
- Cellulite treatment.
- Slimming and weight-management services.
- Consultations, packages, memberships, add-ons, and future services.

Each service or package shall support:

- Internal service ID and public name.
- English and Arabic names/descriptions.
- Category, images, benefits, preparation/aftercare text, and disclaimers
  where approved.
- Duration, buffer time, and required provider type.
- Public price, starting price, price-on-request flag, or branch-specific
  price in AED.
- Whether a consultation, deposit, full payment, or no online payment is
  required.
- Branch availability and active/inactive status.
- Booking rules, cancellation policy, eligibility, and add-ons.
- Assigned provider types and optional specific providers.

## 8. Appointment booking and availability

### 8.1 Customer booking flow

The customer shall be able to:

1. Select a service, package, or consultation.
2. Select a branch.
3. Select a preferred provider when the service allows it, or accept the
   first available provider.
4. Select an available date and time.
5. Review customer, branch, service, duration, price, and policy details.
6. Select payment method and complete required payment or deposit.
7. Receive a confirmation containing the appointment ID, client number,
   branch, service, time, payment status, and next steps.

The backend shall re-check availability and price before creating the
appointment. A slot must never be bookable by two customers.

### 8.2 Appointment data

An appointment shall include:

- Unique appointment ID and audit history.
- Customer/client number and internal customer ID.
- Branch, service/package, provider, and source channel.
- Scheduled start/end time in Asia/Dubai.
- Status, notes, cancellation/reschedule reason, and created-by user.
- Payment, invoice, or subscription references where applicable.
- Check-in, completion, and no-show timestamps where applicable.

### 8.3 Appointment statuses

The system shall support, at minimum:

- Pending payment.
- Pending confirmation.
- Confirmed.
- Checked in.
- Completed.
- Cancelled.
- Rescheduled.
- No show.

Payment status shall be stored separately from appointment status.

### 8.4 Booking rules

- Availability shall respect branch hours, holidays, closures, provider
  schedules, service duration, buffers, blocked periods, and capacity.
- Cancellation and rescheduling notice periods shall be configurable by
  branch or service.
- Cancelled appointments shall release their active slot.
- Rescheduling shall reserve the new slot and release the old slot
  atomically.
- Duplicate active bookings shall be prevented according to the approved
  clinic policy.
- The system shall retain an audit trail without deleting historical
  appointment records.

## 9. Pricing, checkout, and payments

The platform shall show a clear quote before payment, including the
service/package price, configured fees or tax, discount, deposit, amount
paid, and remaining balance where applicable.

Supported business options shall include:

- Pay the full service amount online.
- Pay a configured deposit online and the balance at the clinic.
- Pay at the clinic when enabled for the selected service/branch.
- Discount or promotional code when enabled.
- Refund, partial refund, failed payment, and manual payment recording
  for authorized staff.

The payment implementation shall:

- Use a UAE-compatible provider selected by the client.
- Keep provider secret keys on the server/integration layer only.
- Use signed webhooks, idempotency keys, and replay-safe event handling.
- Store payment attempts, provider reference, amount, currency, status,
  failure reason, refund status, and timestamps.
- Never store raw card details.
- Prevent an appointment from being marked paid until the provider
  confirms the payment.

The provider, payment methods, VAT/fee rules, refund rules, and whether
payment is required at launch are open client decisions.

## 10. Monthly nutrition and wellness subscription

The clinic shall be able to offer one or more monthly subscription plans
for the nutrition and wellness feature.

Each plan shall support:

- Plan ID, English/Arabic name and description.
- Monthly price in AED, currency, and optional trial/introductory price.
- Included entitlements, such as calculations, meal schedules, progress
  tracking, nutritionist review, or consultations.
- Active dates, renewal behavior, grace period, and cancellation policy.
- Whether the plan can be purchased by an existing customer only.

The subscription flow shall support:

1. View plans and included features.
2. Start a monthly subscription through the selected payment provider.
3. Confirm payment and activate entitlements.
4. View current status, next billing date, invoices, and payment history.
5. Cancel or pause according to policy, without losing already-paid
   access unless the policy says otherwise.
6. Handle renewal success, renewal failure, grace period, expiration,
   refund, and webhook replay.

Subscription statuses shall include at least trialing (if enabled),
active, past due, paused, cancelled, expired, and payment failed.

## 11. Nutrition, calorie, and body-composition features

### 11.1 Input profile

With explicit consent, the customer may provide:

- Age or date of birth.
- Height and weight with metric/unit conversion.
- Sex/biological profile input where required by the selected formula.
- Activity level.
- Goal: weight loss, maintenance, muscle gain, or custom target.
- Target weight, body-fat percentage, muscle target, or other optional
  measurements.
- Dietary preferences, allergies, restrictions, and meal timing where the
  clinic chooses to collect them.

Sensitive health and body data shall be optional unless required for a
specific paid service, and shall be separately protected from ordinary
profile data.

### 11.2 Calculations

The system shall calculate and explain, at minimum:

- BMI and BMI category with an appropriate disclaimer.
- Basal metabolic rate (BMR).
- Estimated total daily energy expenditure (TDEE).
- A configurable calorie target based on the selected goal.
- Suggested protein, fat, and carbohydrate targets.
- Weight-change or muscle-gain target guidance.
- Progress calculations when the customer records new measurements.

Formula selection, units, rounding, age/health limitations, and target
ranges must be reviewed and approved by the clinic's qualified
nutritionist or medical advisor. The implementation must record the
formula/version used so results can be reproduced.

### 11.3 Eating schedule and meal plan

An active plan may include:

- Daily calorie and macro targets.
- Number and timing of meals.
- Meal suggestions, portions, ingredients, allergens, and substitutions.
- Weekly eating schedule and progress check-ins.
- Nutritionist-created or nutritionist-reviewed content.
- Version history when the customer's targets or plan change.

The system shall display a clear message that automated calculations are
estimates and do not replace professional medical or nutrition advice.
Emergency symptoms or eating-disorder risk must be directed to a qualified
professional rather than handled by an automated recommendation.

Personalized plans and premium calculations shall be gated by the
subscription entitlements configured by the clinic. The clinic may choose
to keep a basic calculator public.

## 12. Customer dashboard

After authentication, the customer shall be able to view:

- Client number and profile.
- Upcoming and past appointments, with branch and provider.
- Appointment actions allowed by policy.
- Payment history, receipts/invoices, and outstanding balance.
- Active and previous subscriptions.
- Nutrition profile, calculations, plan, eating schedule, and progress.
- Notification preferences and language.
- Privacy consents and account deletion/data request entry point.

## 13. Staff and admin portal

The protected portal shall support:

- Dashboard for today's and upcoming appointments, filterable by branch.
- Customer search by client number, name, mobile, email, or appointment.
- Branch CRUD, hours, holidays, closures, staff assignment, and capacity.
- Service/category/package CRUD, branch pricing, booking rules, and
  catalogue publishing.
- Staff/provider invitations, roles, branch scope, schedules, leave, and
  blocked time.
- Appointment creation on behalf of a customer and all approved status
  transitions.
- Payment, invoice, refund, manual-payment, and subscription views for
  authorized roles.
- Nutrition plan templates, meal content, formula configuration, and
  nutritionist review workflow.
- Reports and exports for appointments, revenue, branch performance,
  subscriptions, and migration results, subject to permissions.
- Audit log, configuration, consent, and integration status.

## 14. Notifications

The system shall support in-app notifications and configurable external
channels such as email, SMS, and WhatsApp:

- Registration and account events.
- Booking confirmation, change, cancellation, and reminder.
- Payment receipt, failure, refund, and outstanding balance.
- Subscription started, renewal, failed renewal, cancellation, and
  expiry.
- Nutrition-plan availability or nutritionist review.

Notification status, provider response, retry count, and timestamps shall
be recorded. A notification failure must not silently create a duplicate
booking or duplicate charge.

## 15. Data strategy and legacy Excel migration

The existing Excel file is a read-only legacy source for controlled
migration/reference only. It shall not be the live application database.

The migration process shall:

1. Read the approved workbook and required sheets.
2. Map customers, legacy identifiers, services, branches, staff, and
   historical appointments to the target schema.
3. Normalize names, email, UAE/international phone numbers, dates, times,
   service names, branch names, and statuses.
4. Generate or map unique client numbers without collisions.
5. Detect duplicate customers, appointments, and invalid rows using
   approved matching rules.
6. Insert only validated records into the online database.
7. Produce imported, skipped, duplicate, failed, and row-level error
   reports.
8. Support a dry run and an idempotent/re-runnable migration.
9. Preserve the source file byte-for-byte and never write changes to it.

Historical payment or subscription data shall only be imported if the
client supplies reliable columns and approves the mapping.

## 16. Online database and API requirements

The online database is the system of record for all future operations.
The recommended high-level entities are:

- profiles/customers, including immutable client_number.
- branches, branch hours, holidays, and closures.
- service_categories, services, packages, add-ons, and branch pricing.
- staff, roles, branch assignments, availability, and blocked periods.
- appointments and appointment status/audit history.
- payment_intents, payments, refunds, invoices, and webhook events.
- subscription_plans, subscriptions, subscription events, and
  entitlements.
- nutrition_profiles, calculation results, formula versions, plans,
  meal schedules, meal content, and progress entries.
- notifications, consents, audit logs, and app settings.
- migration_runs and row-level migration results.

The API shall expose equivalent operations for:

- Authentication, profile, client number, and consents.
- Branches, services, packages, pricing, and public content.
- Availability and appointments.
- Checkout, payments, refunds, invoices, subscriptions, and webhooks.
- Nutrition profile, calculations, plans, schedules, progress, and
  entitlements.
- Staff/admin management, reports, migration, and audit logs.

The frontend/mobile clients shall use the API/data-access layer and shall
never contain service-role credentials or trust client-side price,
availability, entitlement, or role values.

## 17. Security, privacy, and compliance

- HTTPS shall be used for all traffic.
- Supabase/database RLS and server-side authorization shall enforce both
  role and branch scope.
- Customers shall only read or modify their own records.
- Staff shall receive the minimum customer and health data required for
  their role.
- Health, body-composition, nutrition, payment, and identity data shall
  have separate access policies and audit events.
- Payment data shall be delegated to the payment provider; raw card data
  shall not be stored.
- Webhook signatures, replay protection, rate limits, input validation,
  secure headers, and secret management shall be implemented.
- Important administrative, payment, subscription, nutrition, and
  customer-data actions shall be auditable.
- Data export, correction, consent withdrawal, retention, and deletion
  behavior shall be documented and implemented according to the clinic's
  approved UAE legal/privacy advice.
- The client must approve Terms, Privacy Policy, health-data consent,
  nutrition disclaimer, cancellation/refund policy, and marketing
  consent wording before production.

This specification identifies technical controls; it is not legal advice
and does not by itself certify compliance with UAE law or a regulator.

## 18. Non-functional requirements

- Responsive web UI at 360px, 768px, 1024px, and 1280px widths.
- Installable PWA for the approval demo, with a defined path to the
  customer iOS/Android app.
- English/Arabic localization with complete RTL support.
- Asia/Dubai timezone and AED formatting throughout customer and staff
  flows.
- Availability and booking operations must be transactional and resistant
  to concurrent requests.
- Payment/subscription webhook processing must be idempotent.
- Initial screens should remain responsive on ordinary UAE mobile
  networks; loading, empty, error, and offline states are required.
- Accessibility target: keyboard navigation, visible focus, form labels,
  contrast, readable errors, and screen-reader-friendly status changes.
- Automated tests shall cover calculations, authorization, branch scope,
  pricing, booking concurrency, payment events, and subscription
  entitlement transitions.
- Monitoring, error logging, database backup, recovery, and release
  rollback procedures shall be documented.

## 19. Acceptance criteria for the client-approval MVP

The approval build is accepted when all applicable items below can be
demonstrated with test data:

1. The branded website and mobile-sized experience render in English and
   Arabic/RTL.
2. A customer can register, sign in, and receive a unique client number.
3. The customer can browse approved services and branches from the
   database.
4. The customer can choose a branch, see valid slots, and book without
   double booking.
5. The confirmation shows client number, appointment ID, branch, service,
   time, and payment status.
6. The customer can view, cancel, and reschedule within configured rules.
7. The customer can see a price summary and complete a sandbox payment or
   use the configured pay-at-clinic option, depending on launch decision.
8. A customer can view the nutrition plan, start a test monthly
   subscription, and see entitlement changes after success/failure/
   cancellation events.
9. The wellness feature calculates BMI, BMR/TDEE, calories, and macros
   from test inputs and presents the approved disclaimer.
10. An authorized staff/admin user can manage branches, services, staff
    schedules, appointments, payments, subscriptions, and client lookup.
11. Unauthorized users cannot access another customer's appointment,
    payment, subscription, or health data.
12. Legacy Excel data can be dry-run, validated, imported, and reported
    without changing the source workbook.
13. Appointment, payment, subscription, and nutrition actions are
    auditable.

The native iOS/Android release, live payment credentials, app-store
publishing, and production legal approval are release gates tracked in the
task plan rather than assumed to be complete in the browser demo.

## 20. Open client decisions and required inputs

The following items must be answered before production scope is locked:

1. The clinic website/link containing the authoritative service catalogue.
2. Approved logo, app icon, colors, typography, imagery, and brand rules.
3. Official clinic name, branch list, addresses, contact details, and map
   links for Dubai, Abu Dhabi, and any other emirates.
4. Final service/package list, English/Arabic copy, duration, buffers,
   pricing, VAT/fees, branch availability, and assigned provider types.
5. Working hours, holidays, closures, slot interval, branch capacity, and
   provider schedules.
6. Cancellation, rescheduling, no-show, deposit, refund, and
   pay-at-clinic policies.
7. Payment provider, supported methods, sandbox/live credentials, webhook
   endpoint, and go-live requirements.
8. Nutrition subscription plan names, monthly prices, entitlements,
   trial/grace/cancellation rules, and whether the basic calculator is
   free.
9. Nutritionist-approved formulas, ranges, disclaimers, meal content,
   allergy/diet fields, and review workflow.
10. Client-number prefix/format and how legacy customers should be mapped.
11. Login identifier, OTP/verification requirements, and customer
    duplicate-matching rules.
12. Notification channels and providers: email, SMS, WhatsApp, or
    in-app only.
13. Whether native iOS/Android is required for the first client demo or
    the PWA is an interim milestone; app-store accounts and ownership.
14. UAE-approved Terms, Privacy Policy, health consent, marketing consent,
    nutrition disclaimer, and data-retention requirements.
15. Legacy Excel workbook, sheets, columns, and any historical payments or
    subscriptions to migrate.

Until the client confirms these values, development may use clearly
labelled demo defaults only. No demo default may be treated as a
production clinic policy.

## 21. Implementation principles

- The online database is the source of truth after migration.
- All availability, price, payment, subscription entitlement, role, and
  branch-scope decisions are verified server-side.
- Business rules are shared by the website, PWA, and native mobile app;
  clients should not reimplement them independently.
- The service catalogue and brand assets come from the client-approved
  source link and are versioned/reviewed before publication.
- Health/wellness calculations are transparent, versioned, tested, and
  clearly labelled as estimates.
- New work must be added to the task plan with dependencies and
  acceptance evidence before it is marked done.
