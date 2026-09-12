/**
 * API-boundary validation & normalisation (T5).
 * Mirrors the DB rules in supabase/migrations/002_auth_profiles.sql:
 * UAE mobile -> E.164, lower-cased email, password policy (SRS §5).
 */

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// Min 8 chars, at least one lowercase, uppercase, digit and special char.
const PASSWORD_RE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^\w\s]).{8,}$/

/** E.164-ish: '+' + country code (1-3 digits) + 6-14 national digits. */
const E164_MOBILE_RE = /^\+[1-9]\d{6,14}$/

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
    mobile = '+971' + mobile // 05XXXXXXXX -> +9715XXXXXXXX
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