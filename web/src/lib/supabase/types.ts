/**
 * Shared TypeScript types for the Supabase schema (T3/T5/T37).
 * Mirrors supabase/migrations/001_schema.sql, 002_auth_profiles.sql,
 * 004_branches_client_number_pricing.sql and 005_seed_demo_branches.sql.
 */

export type UserRole = 'patient' | 'staff' | 'admin'
export type AppointmentStatus =
  | 'Pending'
  | 'Confirmed'
  | 'Completed'
  | 'Cancelled'
  | 'Rescheduled'
  | 'No Show'
export type NotificationChannel = 'Email' | 'SMS' | 'WhatsApp'
export type NotificationStatus = 'pending' | 'sent' | 'failed' | 'read'
export type ServiceType = 'service' | 'package' | 'add_on' | 'consultation' | 'membership'
export type BranchAccessRole = 'viewer' | 'manager'

export interface Profile {
  id: string
  full_name: string
  mobile_number: string
  email: string
  dob: string | null
  gender: string | null
  preferred_language: string
  role: UserRole
  /** Immutable, collision-safe customer number (T37) — null for staff/admin. */
  client_number: string | null
  created_at: string
}

export interface Service {
  id: string
  name: string
  description: string | null
  duration_minutes: number
  price: number
  currency: string
  active: boolean
  assigned_staff_type: string | null
  booking_rules: Record<string, unknown>
  sort_order: number
  /** T37: service | package | add_on | consultation | membership */
  service_type: ServiceType
  /** T37: default cleanup/buffer between bookings */
  buffer_minutes: number
  /** T37: hide price from the public catalogue */
  price_on_request: boolean
}

/**
 * Payload for creating a service (admin, T9). Full create: name,
 * duration_minutes and price are required; the rest default.
 */
export interface ServiceInput {
  name: string
  description?: string | null
  duration_minutes: number
  price: number
  currency?: string
  active?: boolean
  assigned_staff_type?: string | null
  booking_rules?: Record<string, unknown>
  sort_order?: number
  service_type?: ServiceType
  buffer_minutes?: number
  price_on_request?: boolean
}

/** Partial update payload for editing a service (admin, T9). */
export interface ServicePatch {
  name?: string
  description?: string | null
  duration_minutes?: number
  price?: number
  currency?: string
  active?: boolean
  assigned_staff_type?: string | null
  booking_rules?: Record<string, unknown>
  sort_order?: number
  service_type?: ServiceType
  buffer_minutes?: number
  price_on_request?: boolean
}

/**
 * Patient-facing view of a service (T9). `price_visible` reflects the
 * clinic's `price_visibility` app_setting (T35) plus per-service
 * `price_on_request`; when false, `price`/`currency` are null so the
 * UI shows "Contact us" instead of a hard-coded value.
 */
export interface PublicService extends Omit<Service, 'price' | 'currency'> {
  price: number | null
  currency: string | null
  price_visible: boolean
}

/** Insert payload for `audit_logs` (admin CRUD writes, T9/T31). */
export interface AuditLogInsert {
  admin_user_id?: string | null
  action: string
  entity: string
  entity_id?: string | null
  details?: Record<string, unknown>
}

export interface Staff {
  id: string
  profile_id: string
  title: string | null
  specializations: string[] | null
  active: boolean
}

export interface StaffAvailability {
  id: string
  staff_id: string
  day_of_week: number
  start_time: string
  end_time: string
}

export interface BlockedPeriod {
  id: string
  staff_id: string | null
  start_datetime: string
  end_datetime: string
  reason: string | null
}

export interface Holiday {
  id: string
  date: string
  reason: string | null
}

export interface Appointment {
  id: string
  appointment_ref: string
  patient_id: string
  service_id: string
  staff_id: string | null
  branch_id: string
  scheduled_start: string
  scheduled_end: string
  status: AppointmentStatus
  notes: string | null
  cancel_reason: string | null
  client_number: string
  service_name_snapshot: string
  price_snapshot: number
  currency_snapshot: string
  package_id: string | null
  source_channel: string
  /** T12: buffer snapshot at booking time — conflicts computed against this. */
  buffer_minutes: number
  last_modified_by: string | null
  last_modified_at: string
  created_at: string
}

export interface Notification {
  id: string
  user_id: string
  type: string
  channel: NotificationChannel
  subject: string | null
  body: string
  status: NotificationStatus
  sent_at: string | null
  read_at: string | null
  created_at: string
}

export interface AuditLog {
  id: string
  admin_user_id: string | null
  action: string
  entity: string
  entity_id: string | null
  details: Record<string, unknown>
  created_at: string
}

export interface AppSetting {
  key: string
  value: Record<string, unknown>
}

// ── T37: branches ─────────────────────────────────────────────

export interface Branch {
  id: string
  name: string
  slug: string
  emirate: string
  city: string
  address: string | null
  phone: string | null
  email: string | null
  timezone: string
  map_url: string | null
  active: boolean
  /** T12: max concurrent active appointments (NULL = unlimited). */
  max_concurrent_appointments: number | null
  sort_order: number
  created_at: string
  updated_at: string
}

export interface BranchInput {
  name: string
  slug: string
  emirate: string
  city: string
  address?: string | null
  phone?: string | null
  email?: string | null
  timezone?: string
  map_url?: string | null
  active?: boolean
  sort_order?: number
}

export interface BranchPatch {
  name?: string
  slug?: string
  emirate?: string
  city?: string
  address?: string | null
  phone?: string | null
  email?: string | null
  timezone?: string
  map_url?: string | null
  active?: boolean
  sort_order?: number
}

export interface BranchHours {
  id: string
  branch_id: string
  day_of_week: number
  start_time: string
  end_time: string
}

export interface BranchClosure {
  id: string
  branch_id: string
  date: string
  reason: string | null
}

export interface StaffBranch {
  id: string
  staff_id: string
  branch_id: string
  primary_branch: boolean
  active: boolean
  created_at: string
}

export interface BranchAccess {
  id: string
  profile_id: string
  branch_id: string
  role: BranchAccessRole
  active: boolean
  created_at: string
}

/** Per-branch service availability + price/duration/buffer overrides (T37). */
export interface ServiceBranch {
  id: string
  service_id: string
  branch_id: string
  available: boolean
  price: number | null
  currency: string
  duration_minutes: number | null
  buffer_minutes: number
  deposit_amount: number | null
  booking_rules: Record<string, unknown>
  created_at: string
  updated_at: string
}

export interface ServiceBranchInput {
  service_id: string
  branch_id: string
  available?: boolean
  price?: number | null
  currency?: string
  duration_minutes?: number | null
  buffer_minutes?: number
  deposit_amount?: number | null
  booking_rules?: Record<string, unknown>
}

export interface ServiceBranchPatch {
  available?: boolean
  price?: number | null
  currency?: string
  duration_minutes?: number | null
  buffer_minutes?: number
  deposit_amount?: number | null
  booking_rules?: Record<string, unknown>
}

export interface PackageItem {
  id: string
  package_id: string
  included_service_id: string
  quantity: number
  sort_order: number
}

export interface ServiceAddon {
  id: string
  service_id: string
  addon_id: string
  active: boolean
  sort_order: number
}

export interface MigrationMapping {
  id: string
  entity_type:
    | 'customer'
    | 'branch'
    | 'service'
    | 'staff'
    | 'appointment'
    | 'package'
    | 'add_on'
  legacy_key: string
  target_id: string
  batch: string
  created_at: string
}

export interface ClientSearchResult {
  client_number: string
  full_name: string
  email: string
  mobile_number: string
}

// ── T12: availability engine ─────────────────────────────────

/**
 * One generated slot row from `public.get_availability(...)`.
 * `slot_start`/`slot_end` are absolute instants computed from the
 * branch timezone (Asia/Dubai mandated by the SRS); every row
 * carries the branch and the timezone used.
 */
export interface AvailabilitySlot {
  branch_id: string
  branch_name: string
  timezone: string
  slot_date: string
  slot_start: string
  slot_end: string
  provider_id: string
  provider_name: string
  service_id: string
  service_name: string
  duration_minutes: number
  buffer_minutes: number
  price: number
  currency: string
}

/** Row returned by `public.reserve_slot(...)` — a full appointment. */
export type ReservedAppointment = Appointment

/**
 * Provider (staff) summary returned by `get_branch_providers`
 * (T13 migration 007) — drives the optional provider step of the
 * availability picker.
 */
export interface ProviderSummary {
  id: string
  full_name: string
  title: string | null
  specializations: string[] | null
  active: boolean
  primary_branch: boolean
}

/**
 * Database type bag for createClient<Database>().
 * Only the tables/functions the MVP uses are modelised here; omitted
 * tables fall back to the untyped Postgrest client at the call site.
 */
export interface Database {
  public: {
    Tables: {
      profiles: { Row: Profile }
      services: { Row: Service; Insert: ServiceInput; Update: ServicePatch }
      staff: { Row: Staff }
      staff_availability: { Row: StaffAvailability }
      blocked_periods: { Row: BlockedPeriod }
      holidays: { Row: Holiday }
      appointments: { Row: Appointment }
      notifications: { Row: Notification }
      audit_logs: { Row: AuditLog; Insert: AuditLogInsert; Update: Partial<AuditLogInsert> }
      app_settings: { Row: AppSetting }
      branches: { Row: Branch; Insert: BranchInput; Update: BranchPatch }
      branch_hours: { Row: BranchHours }
      branch_closures: { Row: BranchClosure }
      staff_branches: { Row: StaffBranch }
      branch_access: { Row: BranchAccess }
      service_branches: { Row: ServiceBranch; Insert: ServiceBranchInput; Update: ServiceBranchPatch }
      package_items: { Row: PackageItem }
      service_addons: { Row: ServiceAddon }
      migration_mappings: { Row: MigrationMapping }
    }
    Functions: {
      resolve_login_identifier: {
        Args: { identifier: string }
        Returns: Array<{ email: string }>
      }
      is_admin: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      is_staff_or_admin: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      can_access_branch: {
        Args: { p_branch_id: string }
        Returns: boolean
      }
      can_manage_branch: {
        Args: { p_branch_id: string }
        Returns: boolean
      }
      search_clients: {
        Args: { p_query: string }
        Returns: Array<ClientSearchResult>
      }
      get_availability: {
        Args: {
          p_branch_id: string
          p_service_id: string
          p_from: string
          p_to: string
          p_staff_id?: string | null
        }
        Returns: Array<AvailabilitySlot>
      }
      get_branch_providers: {
        Args: { p_branch_id: string }
        Returns: Array<ProviderSummary>
      }
      reserve_slot: {
        Args: {
          p_branch_id: string
          p_service_id: string
          p_patient_id: string
          p_start: string
          p_staff_id?: string | null
          p_notes?: string | null
          p_source_channel?: string
        }
        Returns: ReservedAppointment
      }
    }
    Enums: {
      user_role: UserRole
      appointment_status: AppointmentStatus
      notification_channel: NotificationChannel
      notification_status: NotificationStatus
      service_type: ServiceType
      branch_access_role: BranchAccessRole
    }
  }
}