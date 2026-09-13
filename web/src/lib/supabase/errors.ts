/**
 * Mapped error catalog for the auth API (T5).
 * Converts raw Supabase Auth / Postgres errors into stable, friendly
 * codes + messages that P2 screens can render (EN/AR) — never raw
 * DB messages leak to the UI (SRS §5/§17).
 */

interface ErrorEntry {
  code: string
  message: string
}

/** Postgres error codes surfaced through the sign-up/profile triggers. */
const PG_ERROR_MAP: Record<string, ErrorEntry> = {
  '23505': {
    code: 'DUPLICATE_ACCOUNT',
    message: 'An account with this email or mobile number already exists',
  },
  '23514': {
    code: 'VALIDATION_FAILED',
    message: 'Some of the provided details are not valid',
  },
}

/** Supabase Auth error codes (error.status is set for these). */
const AUTH_ERROR_MAP: Record<string, ErrorEntry> = {
  user_already_exists: {
    code: 'USER_EXISTS',
    message: 'An account with this email already exists',
  },
  duplicate_email: {
    code: 'USER_EXISTS',
    message: 'An account with this email already exists',
  },
  email_exists: {
    code: 'USER_EXISTS',
    message: 'An account with this email already exists',
  },
  invalid_credentials: {
    code: 'INVALID_CREDENTIALS',
    message: 'Incorrect email or password',
  },
  email_not_confirmed: {
    code: 'EMAIL_NOT_CONFIRMED',
    message: 'Please verify your email address before signing in',
  },
  weak_password: {
    code: 'WEAK_PASSWORD',
    message:
      'Password must be at least 8 characters and include uppercase, lowercase, number and special character',
  },
  email_address_invalid: {
    code: 'INVALID_EMAIL',
    message: 'Please enter a valid email address',
  },
  signup_disabled: {
    code: 'SIGNUP_DISABLED',
    message: 'Registration is currently unavailable',
  },
  over_email_send_rate_limit: {
    code: 'RATE_LIMITED',
    message: 'Too many requests. Please try again in a minute',
  },
  over_request_rate_limit: {
    code: 'RATE_LIMITED',
    message: 'Too many requests. Please try again later',
  },
  new_password_should_be_different: {
    code: 'SAME_PASSWORD',
    message: 'New password must be different from the current one',
  },
  user_not_found: {
    code: 'INVALID_CREDENTIALS',
    message: 'Incorrect email or password',
  },
}

export interface MappedError {
  code: string
  message: string
  /** The original error is kept for debugging, never shown to users. */
  original?: Error
}

/**
 * Map any error produced by the auth layer to a friendly entry.
 * Unknown errors are masked with a generic message (SRS §17 —
 * no internal details are exposed).
 */
export function mapError(error: Error): MappedError {
  const candidate = error as Error & {
    status?: number | string
    code?: string
  }

  // 1. Structured code (AuthError.code, PostgrestError.code) — e.g.
  //    "user_already_exists", "23505"
  if (candidate.code) {
    const byCode = AUTH_ERROR_MAP[candidate.code] ?? PG_ERROR_MAP[candidate.code]
    if (byCode) {
      return { code: byCode.code, message: byCode.message, original: error }
    }
  }

  // 2. HTTP status numeric (AuthError.status) — only mapped entries
  if (candidate.status !== undefined) {
    const byStatus = AUTH_ERROR_MAP[String(candidate.status)]
    if (byStatus) {
      return { code: byStatus.code, message: byStatus.message, original: error }
    }
  }

  // 3. Message-body matching (server message may embed a PG SQLSTATE
  //    or a friendly trigger message)
  return mapPostgresError(error.message, error)
}

/**
 * Attempt to interpret an error message that originates from Supabase
 * Auth or Postgres (Supabase wraps trigger/constraint failures into
 * the Auth error).
 */
function mapPostgresError(message: string, original: Error): MappedError {
  // Auth-level messages that reach us as free text
  const authMessageMatches: Array<{ re: RegExp; entry: ErrorEntry }> = [
    { re: /user already registered/i, entry: AUTH_ERROR_MAP.user_already_exists },
    { re: /already exists|duplicate/i, entry: PG_ERROR_MAP['23505'] },
    { re: /invalid login credentials|invalid email or password/i, entry: AUTH_ERROR_MAP.invalid_credentials },
    { re: /email not confirmed/i, entry: AUTH_ERROR_MAP.email_not_confirmed },
    { re: /password should be at least/i, entry: AUTH_ERROR_MAP.weak_password },
    { re: /rate limit/i, entry: AUTH_ERROR_MAP.over_request_rate_limit },
    { re: /new password should be different/i, entry: AUTH_ERROR_MAP.new_password_should_be_different },
  ]

  for (const { re, entry } of authMessageMatches) {
    if (re.test(message)) {
      return { code: entry.code, message: entry.message, original }
    }
  }

  // T8 trigger messages (009_consents_data_requests.sql) — allowed
  // field rules and consent immutability surface as friendly errors.
  if (/email cannot be changed/i.test(message)) {
    return {
      code: 'FORBIDDEN',
      message: 'Email cannot be changed here — use the account settings flow',
      original,
    }
  }
  if (/cannot change your own role/i.test(message)) {
    return { code: 'FORBIDDEN', message: 'You cannot change your role', original }
  }
  if (/profile (id|creation time) is immutable/i.test(message)) {
    return { code: 'FORBIDDEN', message: 'That field cannot be edited', original }
  }
  if (/consent records are immutable/i.test(message)) {
    return {
      code: 'CONSENT_IMMUTABLE',
      message: 'Consent history is immutable — record a new grant or withdrawal instead',
      original,
    }
  }

  // Trigger-generated friendly messages already read well; surface them
  if (/mobile number is required/i.test(message)) {
    return { code: 'MOBILE_REQUIRED', message: 'Mobile number is required', original }
  }
  if (/email address is required/i.test(message)) {
    return { code: 'EMAIL_REQUIRED', message: 'Email address is required', original }
  }
  if (/invalid international format/i.test(message)) {
    return {
      code: 'INVALID_MOBILE',
      message: 'Please enter a valid UAE mobile number (e.g. +971 50 123 4567)',
      original,
    }
  }

  // Postgres SQLSTATE codes embedded in the message body
  const codeMatch = message.match(/(\d{5})/)
  if (codeMatch) {
    const entry = PG_ERROR_MAP[codeMatch[1]]
    if (entry) {
      return { code: entry.code, message: entry.message, original }
    }
  }

  return {
    code: 'UNKNOWN',
    message: 'Something went wrong. Please try again.',
    original,
  }
}

/** Convenience for building mapped errors for non-thrown branches. */
export function mapped(code: string, message: string): MappedError {
  return { code, message }
}