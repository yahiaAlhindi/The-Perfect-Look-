**The Perfect Look -- Patient Booking Application\
Software Requirements Specification**

*Developer Requirements -- Initial Version*

# 1. Project Objective

Develop a patient-facing web/mobile application for The Perfect Look
that allows patients to create accounts, securely log in, browse
available treatments, check available appointment slots, and book,
cancel, or reschedule appointments. The application will use an online
database as the primary and permanent data store.

# 2. Data Strategy -- Important

The existing Excel file is a LEGACY DATA SOURCE only. It must not be
used as the application\'s ongoing database. At initial deployment, the
system shall read/import the existing historical data from the Excel
file, validate and map it to the new online database structure, and then
use the online database for all future operations.

-   Excel is read-only for migration/reference purposes.

-   Existing Excel records shall be mapped to the new database entities.

-   The migration process must validate required fields and identify
    invalid or duplicate records.

-   A migration log/report should identify imported, skipped, duplicate,
    and failed records.

-   After migration, new patients and appointments must be created
    directly in the online database.

-   Updates, cancellations, rescheduling, service changes, and other
    transactions must be performed against the online database.

-   The original Excel file should be retained as a backup/reference and
    must not be modified by the application.

# 3. High-Level Architecture

Recommended architecture: Frontend → Backend/API → Online Database. The
Excel file is connected only to a one-time/controlled migration process.

Initial migration flow:

-   Existing Excel → Data Validation/Mapping → Online Database

Normal application flow:

-   Patient/Admin → Frontend → Backend/API → Online Database

# 4. User Roles

-   Patient -- registers, logs in, views services, books appointments,
    and manages personal bookings.

-   Receptionist/Staff -- manages patient appointments and availability
    according to permissions.

-   Administrator -- manages services, staff, schedules, users, and
    system configuration.

# 5. Patient Registration / Create Account

-   Full Name -- required

-   Mobile Number -- required and unique

-   Email Address -- required and unique

-   Password -- required

-   Confirm Password -- required

-   Date of Birth -- configurable

-   Gender -- configurable

-   Preferred Language -- configurable

-   Privacy Policy / Terms consent -- required

The system shall validate required fields, email format, mobile number,
password policy, duplicate accounts, and password confirmation.

# 6. Login & Authentication

-   Login using email and password and/or mobile number, according to
    final business decision.

-   Forgot Password / Reset Password.

-   Logout.

-   Secure session/token management.

-   Passwords must be securely hashed and never stored as plain text.

-   Optional OTP verification can be added later.

# 7. Patient Profile

-   View personal information.

-   Edit allowed personal information.

-   Change password.

-   View upcoming appointments.

-   View appointment history.

# 8. Services / Treatments

Services must be managed dynamically from the online database/admin
portal. The frontend must not require a code deployment whenever a
service is added, removed, or updated.

-   Skin Care Treatment

-   Advanced Hair Care Solutions

-   Laser Hair Removal

-   Clinical Nutrition & Weight Management

-   Body Contouring / Fat Reduction

-   Cellulite Treatment

-   Slimming / Weight Management

-   Other services/packages defined by the clinic

Each service should support:

-   Service ID

-   Service Name

-   Description

-   Duration

-   Price (if applicable)

-   Active/Inactive status

-   Assigned staff type

-   Booking rules

# 9. Appointment Booking

1.  Patient logs in.

2.  Patient selects a service/treatment.

3.  System displays available dates and time slots.

4.  Patient selects a date and available time.

5.  Patient may select a preferred staff member if applicable.

6.  Backend re-checks slot availability before creating the booking.

7.  System creates a unique Appointment ID.

8.  Appointment is stored in the online database.

9.  Patient receives booking confirmation.

10. Optional email/SMS/WhatsApp notification can be triggered.

# 10. Appointment Status

-   Pending

-   Confirmed

-   Completed

-   Cancelled

-   Rescheduled

-   No Show

# 11. Appointment Business Rules

-   A time slot must not be bookable by more than one patient.

-   Availability must be checked again on the backend immediately before
    saving.

-   Cancelled appointments must no longer occupy an active slot.

-   Rescheduling must release the previous slot and reserve the new
    slot.

-   Availability must respect clinic working hours, holidays, blocked
    periods, and staff schedules.

-   Cancellation/rescheduling notice periods must be configurable.

-   Duplicate active bookings should be prevented according to clinic
    rules.

# 12. Online Database -- System of Record

The online database is the single source of truth for the application.
The final database schema will be incorporated once provided by the
project owner.

-   Patient/account records

-   Services and treatment configuration

-   Staff records

-   Staff availability

-   Appointments

-   Notifications

-   Audit/history data where required

# 13. Legacy Excel Migration

The migration component shall support the following process:

11. Receive the approved legacy Excel file.

12. Read the required sheets and columns.

13. Map Excel columns to the target database fields.

14. Normalize values such as dates, phone numbers, statuses, and service
    names.

15. Validate required fields.

16. Detect duplicate patients and appointments based on agreed matching
    rules.

17. Insert valid records into the online database.

18. Generate a migration result containing successful, duplicate,
    invalid, and failed records.

19. Do not modify the source Excel file.

20. Run migration in a controlled environment before production
    deployment.

Example mapping concept:

  --------------------------------------------------------------------------
  Excel Field       Target Entity     Target Field      Transformation
  ----------------- ----------------- ----------------- --------------------
  Patient Name      Patient           FullName          Trim/normalize text

  Mobile            Patient           MobileNumber      Normalize
                                                        country/phone format

  Email             Patient           Email             Lowercase/validate

  Treatment         Service           ServiceName       Map to configured
                                                        service

  Appointment Date  Appointment       AppointmentDate   Convert to database
                                                        date

  Appointment Time  Appointment       StartTime         Convert to standard
                                                        time

  Status            Appointment       Status            Map legacy status to
                                                        system status
  --------------------------------------------------------------------------

# 14. Admin / Staff Portal

-   Secure staff/admin login.

-   Dashboard for today\'s and upcoming appointments.

-   Search/filter appointments by patient, service, staff, date, and
    status.

-   Create, confirm, cancel, reschedule, and complete appointments.

-   Manage services and treatment information.

-   Manage staff.

-   Manage staff availability and blocked time.

-   View patient appointment history according to role permissions.

-   Export reports/data when required.

-   View migration results and errors during initial data migration.

# 15. Notifications

-   Booking confirmation.

-   Appointment reminder.

-   Cancellation confirmation.

-   Rescheduling confirmation.

-   Notification status should be recorded where integrations are used.

-   Supported channels can include Email, SMS, and WhatsApp depending on
    the selected provider.

# 16. Backend / API Requirements

-   POST /auth/register

-   POST /auth/login

-   POST /auth/forgot-password

-   GET /services

-   GET /services/{serviceId}

-   GET /availability?serviceId=&date=

-   POST /appointments

-   GET /appointments

-   GET /appointments/{appointmentId}

-   PUT /appointments/{appointmentId}

-   POST /appointments/{appointmentId}/cancel

-   GET /profile

-   PUT /profile

-   Admin APIs for services, staff, availability, appointments, users,
    and reports

-   Migration/import API or controlled migration utility for the legacy
    Excel data

# 17. Security & Privacy

-   HTTPS for all application traffic.

-   Secure password hashing.

-   Role-based access control.

-   Server-side validation for all API requests.

-   No direct browser access to database credentials.

-   No public exposure of patient records.

-   Audit logging for important administrative actions.

-   Database backup and recovery.

-   Apply applicable UAE healthcare/privacy requirements and clinic
    policies.

# 18. Non-Functional Requirements

-   Responsive web/mobile-friendly interface.

-   Arabic and English support.

-   Good performance when loading services and appointment availability.

-   Scalable backend architecture.

-   Database transactions must protect against double booking.

-   Centralized configuration for services and schedules.

-   Monitoring and error logging.

# 19. MVP Acceptance Criteria

-   Patient can create an account.

-   Patient can log in and log out.

-   Patient can view active services.

-   Patient can view available dates and slots.

-   Patient can book an available appointment.

-   System prevents double booking.

-   Booking is stored in the online database.

-   Patient can view appointment history and upcoming appointments.

-   Patient can cancel/reschedule according to configured rules.

-   Staff can view and manage bookings.

-   Legacy Excel data can be validated and imported into the online
    database.

-   Excel is not used for new transactions after migration.

-   Unauthorized users cannot access staff/admin functions.

# 20. Future Schema Integration

The final database schema will be added to this document once supplied.
The schema section should define tables, columns, data types, primary
keys, foreign keys, indexes, relationships, status values, and any
existing tables that must be reused rather than recreated.

The final version should also include an Excel-to-schema mapping matrix
and API-to-schema mapping.

# 21. Open Configuration Items

-   Final list of treatments/services that are bookable.

-   Treatment duration for each service.

-   Service pricing and whether price is displayed.

-   Doctors/therapists assigned to each service.

-   Clinic working hours and holidays.

-   Slot interval.

-   Cancellation/rescheduling policy.

-   Whether multiple treatments can be booked together.

-   Online payment requirement.

-   Notification channels.

-   Final online database/schema details.

-   Legacy Excel file and exact column structure.

# 22. Implementation Principle

The developer must design the application so that the frontend
communicates only with the backend/API, and the backend communicates
with the online database. The legacy Excel file is only an initial
migration input. Once the historical data has been migrated and
verified, the application must operate entirely on the online database.
