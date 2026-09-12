/**
 * Shared TypeScript types for the Supabase schema (T3/T5).
 * Mirrors supabase/migrations/001_schema.sql + 002_auth_profiles.sql.
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

export interface Profile {
  id: string
  full_name: string
  mobile_number: string
  email: string
  dob: string | null
  gender: string | null
  preferred_language: string
  role: UserRole
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
  scheduled_start: string
  scheduled_end: string
  status: AppointmentStatus
  notes: string | null
  cancel_reason: string | null
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

/**
 * Database type bag for createClient<Database>().
 * Only the tables/functions the MVP uses are modelised here; omitted
 * tables fall back to the untyped Postgrest client at the call site.
 */
export interface Database {
  public: {
    Tables: {
      profiles: { Row: Profile }
      services: { Row: Service }
      staff: { Row: Staff }
      staff_availability: { Row: StaffAvailability }
      blocked_periods: { Row: BlockedPeriod }
      holidays: { Row: Holiday }
      appointments: { Row: Appointment }
      notifications: { Row: Notification }
      audit_logs: { Row: AuditLog }
      app_settings: { Row: AppSetting }
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
    }
    Enums: {
      user_role: UserRole
      appointment_status: AppointmentStatus
      notification_channel: NotificationChannel
      notification_status: NotificationStatus
    }
  }
}