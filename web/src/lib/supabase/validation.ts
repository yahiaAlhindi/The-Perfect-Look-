/**
 * API-boundary validation & normalisation (T5/T8).
 * Mirrors the DB rules in supabase/migrations/002_auth_profiles.sql and
 * 004_consents_data_requests.sql: UAE mobile -> E.164, lower-cased
 * email, password policy (SRS §5), allowed profile fields (SRS §7),
 * consent types (SRS §5.1/§17) and data-request kinds (SRS §12/§17).
 */

import type { ConsentType, DataRequestType, ProfileUpdate } from './types'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// Min 8 chars, at least one lowercase, uppercase, digit and special char.
const PASSWORD_RE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$/

/** E.164-ish: '+' + country code (1-3 digits) + 6-14 national digits. */
const E164_MOBILE_RE = /^\+[1-9]\d{6,14}$/

/** ISO date (YYYY-MM-DD). */
const DATE_ONLY_RE = /^\d{4}-\d{2}-\d{2}$/

/** Consent families the app may record (SRS §5.1/§17). */
export const CONSENT_TYPES: readonly ConsentType[] = [
  'terms_of_service',
  'privacy_policy',
  'health_data_disclaimer',
  'nutrition_disclaimer',
  'cancellation_refund_policy',
  'marketing',
]

/** Data-request kinds a customer may file (SRS §12/§17). */
export const DATA_REQUEST_TYPES: readonly DataRequestType[] = [
  'export',
  'correction',
  'deletion',
  'consent_withdrawal',
]

/** Allowed gender values on the profile (empty string -> null). */
export const ALLOWED_GENDERS = [
  'female',
  'male',
  'other',
  'prefer_not_to_say',
] as const

/** App-supported UI languages (SRS §18). */
export const ALLOWED_LANGUAGES = ['en', 'ar'] as const

export function validateEmail(email: string): boolean {
  return EMAIL_RE.test(email.trim())
}

/**
 * Normalise a user-entered mobile number to UAE E.164.
 * Accepts: +9715XXXXXXXX, 9715XXXXXXXX, 05XXXXXXXX, 5XXXXXXXX.
 */
export function normalizeMobile(raw: string): string {
  let mobile = raw.replace(/[\s\-().]/g, '').trim()

  if (/^0[5-9]\d{8}$/.test(mobile)) {
    mobile = '+971' + mobile.slice(1) // 05XXXXXXXX -> +9715XXXXXXXX
  } else if (/^971[5-9]\d{8}$/.test(mobile)) {
    mobile = '+' + mobile // 9715XXXXXXXX -> +9715XXXXXXXX
  } else if (/^[5-9]\d{8}$/.test(mobile)) {
    mobile = '+971' + mobile // 5XXXXXXXX -> +9715XXXXXXXX
  }

  return mobile
}

export function isValidMobile(mobile: string): boolean {
  return E164_MOBILE_RE.test(mobile)
}

export function isValidPassword(password: string): boolean {
  return PASSWORD_RE.test(password)
}

export interface SignUpPayload {
  fullName: string
  email: string
  mobile: string
  password: string
  confirmPassword: string
}

export interface SignUpValidation {
  valid: boolean
  errors: Partial<Record<keyof SignUpPayload, string>>
  /** Normalised mobile number, when valid. */
  normalizedMobile?: string
  /** Normalised (lower-cased, trimmed) email, when valid. */
  normalizedEmail?: string
}

/**
 * Validates the full registration payload at the client API boundary
 * (SRS §5: required fields, email format, mobile format, password
 * policy, duplicate checks live on the server, password confirmation).
 */
export function validateSignUp(payload: SignUpPayload): SignUpValidation {
  const errors: SignUpValidation['errors'] = {}
  const fullName = payload.fullName.trim()
  const email = payload.email.trim().toLowerCase()
  const mobile = normalizeMobile(payload.mobile)

  if (!fullName || fullName.length < 2) {
    errors.fullName = 'Full name is required (min 2 characters)'
  }
  if (!validateEmail(email)) {
    errors.email = 'Please enter a valid email address'
  }
  if (!isValidMobile(mobile)) {
    errors.mobile =
      'Please enter a valid UAE mobile number (e.g. +971 5X XXX XXXX)'
  }
  if (!isValidPassword(payload.password)) {
    errors.password =
      'Password must be at least 8 characters and include uppercase, lowercase, number and special character'
  }
  if (payload.password !== payload.confirmPassword) {
    errors.confirmPassword = 'Passwords do not match'
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
    normalizedMobile: errors.mobile ? undefined : mobile,
    normalizedEmail: errors.email ? undefined : email,
  }
}

/** Error thrown when a sign-in identifier is neither email nor mobile. */
export class InvalidIdentifierError extends Error {
  constructor() {
    super('Enter a valid email address or mobile number')
    this.name = 'InvalidIdentifierError'
  }
}

/**
 * Normalise a login identifier (SRS §6): a valid email passes through,
 * anything else is treated as a mobile number and converted to E.164.
 */
export function normalizeIdentifier(identifier: string): string {
  const value = identifier.trim()

  if (validateEmail(value)) {
    return value.toLowerCase()
  }

  const mobile = normalizeMobile(value)
  if (isValidMobile(mobile)) {
    return mobile
  }

  throw new InvalidIdentifierError()
}

export function passwordPolicyHint(): string {
  return 'Min 8 chars with uppercase, lowercase, number and special character'
}

// ── T8: profile update (allowed field rules, SRS §7) ──────────

export interface ProfileUpdateValidation {
  valid: boolean
  errors: Partial<Record<keyof ProfileUpdate, string>>
  /** Normalised patch (trimmed name, E.164 mobile), when valid. */
  normalized?: ProfileUpdate
}

/**
 * Validates an own-profile PUT payload against the T8 allowed-fields
 * whitelist. Unknown fields are never accepted — callers must build
 * the patch from `ProfileUpdate` and always send `null`/`undefined`
 * for optional fields they keep as-is.
 */
export function validateProfileUpdate(
  patch: Partial<ProfileUpdate>,
): ProfileUpdateValidation {
  const errors: ProfileUpdateValidation['errors'] = {}
  const normalized: ProfileUpdate = {}

  if (patch.full_name !== undefined) {
    const name = patch.full_name.trim()
    if (name.length < 2) {
      errors.full_name = 'Full name is required (min 2 characters)'
    } else if (name.length > 200) {
      errors.full_name = 'Full name must be 200 characters or fewer'
    } else {
      normalized.full_name = name
    }
  }

  if (patch.mobile_number !== undefined) {
    const mobile = normalizeMobile(patch.mobile_number)
    if (!isValidMobile(mobile)) {
      errors.mobile_number =
        'Please enter a valid UAE mobile number (e.g. +971 5X XXX XXXX)'
    } else {
      normalized.mobile_number = mobile
    }
  }

  if (patch.dob !== undefined) {
    if (patch.dob === null || patch.dob === '') {
      normalized.dob = null
    } else if (!isValidDateOnly(patch.dob)) {
      errors.dob = 'Please enter a valid date of birth (YYYY-MM-DD)'
    } else {
      normalized.dob = patch.dob
    }
  }

  if (patch.gender !== undefined) {
    if (patch.gender === null || patch.gender === '') {
      normalized.gender = null
    } else if (!(ALLOWED_GENDERS as readonly string[]).includes(patch.gender)) {
      errors.gender = 'Gender must be female, male, other or prefer_not_to_say'
    } else {
      normalized.gender = patch.gender
    }
  }

  if (patch.preferred_language !== undefined) {
    if (!(ALLOWED_LANGUAGES as readonly string[]).includes(patch.preferred_language)) {
      errors.preferred_language = 'Preferred language must be en or ar'
    } else {
      normalized.preferred_language = patch.preferred_language
    }
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
    normalized: Object.keys(errors).length === 0 ? normalized : undefined,
  }
}

// ── T8: consent & data-request validation (SRS §5.1/§12/§17) ──

export interface ConsentValidation {
  valid: boolean
  errors: Partial<Record<'consent_type' | 'version', string>>
}

export function validateConsentInput(
  consentType: string,
  version: number,
): ConsentValidation {
  const errors: ConsentValidation['errors'] = {}

  if (!(CONSENT_TYPES as readonly string[]).includes(consentType)) {
    errors.consent_type = 'Unknown consent type'
  }
  if (!Number.isInteger(version) || version < 1) {
    errors.version = 'Consent version must be a positive whole number'
  }

  return { valid: Object.keys(errors).length === 0, errors }
}

export interface DataRequestValidation {
  valid: boolean
  errors: Partial<Record<'request_type' | 'details', string>>
}

export function validateDataRequestInput(
  requestType: string,
  details?: unknown,
): DataRequestValidation {
  const errors: DataRequestValidation['errors'] = {}

  if (!(DATA_REQUEST_TYPES as readonly string[]).includes(requestType)) {
    errors.request_type = 'Unknown data-request type'
  }
  if (details !== undefined && details !== null) {
    if (typeof details !== 'object') {
      errors.details = 'Details must be a structured object'
    } else if (Array.isArray(details)) {
      errors.details = 'Details must be a structured object'
    }
  }

  return { valid: Object.keys(errors).length === 0, errors }
}

// ── shared helpers ────────────────────────────────────────────

function isValidDateOnly(value: string): boolean {
  if (!DATE_ONLY_RE.test(value)) return false
  const [y, m, d] = value.split('-').map(Number)
  if (y < 1900) return false
  const dt = new Date(Date.UTC(y, m - 1, d))
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
    return false
  }
  return dt.getTime() <= Date.now() // not in the future
}