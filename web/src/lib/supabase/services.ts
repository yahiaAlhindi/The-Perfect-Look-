/**
 * Services API client module (T9).
 * Public patient endpoints + admin CRUD. Services are read from the
 * online DB — the frontend never hard-codes a service list (SRS §8)
 * and admin edits are reflected immediately on the patient side.
 *
 * RBAC enforcement: writes require the admin role.  Enforcement
 * lives on the server via Postgres RLS (supabase/migrations/001_schema.sql);
 * these helpers only surface the mapped errors.
 *
 * Price visibility (T35): patient-facing functions respect the
 * clinic's `price_visibility` `app_setting` and the per-service
 * `booking_rules.price_on_request` flag; when hidden, `price` and
 * `currency` are `null` so the UI renders "Contact us".
 */

import { supabase } from './client'
import type {
  Service,
  ServiceInput,
  ServicePatch,
  PublicService,
} from './types'
import { mapError, type MappedError } from './errors'

// ── constants ──────────────────────────────────────────────────

const DEFAULT_CURRENCY = 'AED'

// ── internal helpers ───────────────────────────────────────────

interface PriceSettings {
  currency: string
  priceVisible: boolean
}

const SERVICE_ERROR_MAP: Record<string, { code: string; message: string }> = {
  PGRST116: { code: 'SERVICE_NOT_FOUND', message: 'Service not found' },
  '42501': {
    code: 'FORBIDDEN',
    message: 'You do not have permission to perform this action',
  },
  '23514': {
    code: 'VALIDATION_FAILED',
    message: 'Some of the provided service details are not valid',
  },
}

function mapServiceError(error: unknown): MappedError {
  const candidate = error as Error & { code?: string }
  const entry = candidate?.code ? SERVICE_ERROR_MAP[candidate.code] : undefined
  if (entry) {
    return { code: entry.code, message: entry.message, original: error as Error }
  }
  return mapError(error as Error)
}

/**
 * Read price-visibility and currency from `app_settings` (SRS §12).
 * Returns `null` on error so callers can degrade gracefully.
 */
async function readPriceSettings(): Promise<PriceSettings | null> {
  const { data, error } = await supabase
    .from('app_settings')
    .select('key, value')
    .in('key', ['price_visibility', 'currency'])

  if (error || !data) return null

  const map: Record<string, unknown> = {}
  for (const row of data) map[row.key] = row.value

  const rawVisibility = map['price_visibility']
  const priceVisible =
    typeof rawVisibility === 'string' && rawVisibility === 'visible'

  const currency =
    typeof map['currency'] === 'string'
      ? (map['currency'] as string)
      : DEFAULT_CURRENCY

  return { currency, priceVisible }
}

/** Strip/keep price fields based on clinic settings. */
function toPublic(service: Service, settings: PriceSettings): PublicService {
  const onRequest =
    typeof service.booking_rules === 'object' &&
    service.booking_rules !== null &&
    'price_on_request' in service.booking_rules &&
    (service.booking_rules as Record<string, unknown>).price_on_request === true

  const priceVisible = settings.priceVisible && !onRequest

  return {
    ...service,
    price_visible: priceVisible,
    price: priceVisible ? service.price : null,
    currency: priceVisible ? settings.currency : null,
  }
}

// ── public result shapes ───────────────────────────────────────

interface ServiceResult {
  service: Service | null
  error: MappedError | null
}

interface PublicServiceResult {
  service: PublicService | null
  error: MappedError | null
}

interface ServiceListResult {
  services: Service[]
  error: MappedError | null
}

interface PublicServiceListResult {
  services: PublicService[]
  error: MappedError | null
}

// ── public API ─────────────────────────────────────────────────

/**
 * Patient-facing list of active services (SRS §8).
 * Prices are masked when the clinic's `price_visibility` setting is
 * `contact_us` or the service is flagged `price_on_request`.
 */
export async function listServices(): Promise<PublicServiceListResult> {
  const settings = await readPriceSettings()
  const effective: PriceSettings =
    settings ?? { currency: DEFAULT_CURRENCY, priceVisible: false }

  const { data, error } = await supabase
    .from('services')
    .select('*')
    .eq('active', true)
    .order('sort_order', { ascending: true })
    .order('name', { ascending: true })

  if (error) {
    return { services: [], error: mapServiceError(error) }
  }

  return {
    services: (data ?? []).map((s) => toPublic(s, effective)),
    error: null,
  }
}

/**
 * Patient-facing service detail.
 * Returns `SERVICE_NOT_FOUND` for missing / inactive services
 * (RLS blocks non-admins from reading inactive rows).
 */
export async function getService(id: string): Promise<PublicServiceResult> {
  const settings = await readPriceSettings()
  const effective: PriceSettings =
    settings ?? { currency: DEFAULT_CURRENCY, priceVisible: false }

  const { data, error } = await supabase
    .from('services')
    .select('*')
    .eq('id', id)
    .maybeSingle()

  if (error) {
    return { service: null, error: mapServiceError(error) }
  }
  if (!data) {
    return {
      service: null,
      error: { code: 'SERVICE_NOT_FOUND', message: 'Service not found' },
    }
  }

  return { service: toPublic(data, effective), error: null }
}

/**
 * Admin / staff list — includes inactive services.
 * RLS restricts results to staff and admin roles.
 */
export async function listServicesAdmin(): Promise<ServiceListResult> {
  const { data, error } = await supabase
    .from('services')
    .select('*')
    .order('sort_order', { ascending: true })
    .order('name', { ascending: true })

  if (error) {
    return { services: [], error: mapServiceError(error) }
  }
  return { services: data ?? [], error: null }
}

/**
 * Create a new service (admin only — enforced via RLS).
 * Automatically writes an audit log row on success (T31).
 */
export async function createService(input: ServiceInput): Promise<ServiceResult> {
  const validation = validateServiceInput(input, false)
  if (!validation.valid) {
    return {
      service: null,
      error: { code: 'VALIDATION_FAILED', message: formatValidationErrors(validation.errors) },
    }
  }

  const { data, error } = await supabase
    .from('services')
    .insert({
      name: input.name.trim(),
      description: input.description ?? null,
      duration_minutes: input.duration_minutes,
      price: input.price,
      currency: input.currency ?? DEFAULT_CURRENCY,
      active: input.active ?? true,
      assigned_staff_type: input.assigned_staff_type ?? null,
      booking_rules: input.booking_rules ?? {},
      sort_order: input.sort_order ?? 0,
    })
    .select()
    .single()

  if (error) {
    return { service: null, error: mapServiceError(error) }
  }
  if (!data) {
    return {
      service: null,
      error: { code: 'SERVICE_NOT_FOUND', message: 'Service not found' },
    }
  }

  void writeAuditLog('service.create', data.id, { name: data.name })
  return { service: data, error: null }
}

/**
 * Update a service (admin only — enforced via RLS).
 * Only provided fields are changed. Writes an audit log row on success.
 */
export async function updateService(
  id: string,
  patch: ServicePatch,
): Promise<ServiceResult> {
  const validation = validateServiceInput(patch, true)
  if (!validation.valid) {
    return {
      service: null,
      error: { code: 'VALIDATION_FAILED', message: formatValidationErrors(validation.errors) },
    }
  }

  const { data, error } = await supabase
    .from('services')
    .update(patch)
    .eq('id', id)
    .select()
    .single()

  if (error) {
    return { service: null, error: mapServiceError(error) }
  }
  if (!data) {
    return {
      service: null,
      error: { code: 'SERVICE_NOT_FOUND', message: 'Service not found' },
    }
  }

  void writeAuditLog('service.update', id, { ...patch })
  return { service: data, error: null }
}

/**
 * Soft-deactivate a service (admin only — enforced via RLS).
 * The service remains in the DB (appointments FKs may reference it)
 * but is hidden from the patient list. Writes an audit log row.
 */
export async function deactivateService(id: string): Promise<ServiceResult> {
  const { data, error } = await supabase
    .from('services')
    .update({ active: false })
    .eq('id', id)
    .select()
    .single()

  if (error) {
    return { service: null, error: mapServiceError(error) }
  }
  if (!data) {
    return {
      service: null,
      error: { code: 'SERVICE_NOT_FOUND', message: 'Service not found' },
    }
  }

  void writeAuditLog('service.deactivate', id, { active: false })
  return { service: data, error: null }
}

// ── validation ─────────────────────────────────────────────────

export interface ServiceValidation {
  valid: boolean
  errors: Record<string, string>
}

/**
 * Boundary validation for service create / update payloads.
 * @param partial — when true, only provided fields are validated (update).
 */
export function validateServiceInput(
  input: Partial<ServiceInput>,
  partial: boolean,
): ServiceValidation {
  const errors: Record<string, string> = {}

  if (!partial || input.name !== undefined) {
    const name = (input.name ?? '').trim()
    if (!name) {
      errors.name = 'Service name is required'
    } else if (name.length > 200) {
      errors.name = 'Service name must be 200 characters or fewer'
    }
  }

  if (!partial || input.duration_minutes !== undefined) {
    const dur = input.duration_minutes
    if (typeof dur !== 'number' || !Number.isInteger(dur) || dur <= 0) {
      errors.duration_minutes = 'Duration must be a positive whole number of minutes'
    }
  }

  if (!partial || input.price !== undefined) {
    const p = input.price
    if (typeof p !== 'number' || !Number.isFinite(p) || p < 0) {
      errors.price = 'Price must be zero or more'
    }
  }

  if (!partial || input.currency !== undefined) {
    const cur = input.currency
    if (cur !== undefined && (typeof cur !== 'string' || !/^[A-Za-z]{3}$/.test(cur))) {
      errors.currency = 'Currency must be a 3-letter code (e.g. AED)'
    }
  }

  if (!partial || input.sort_order !== undefined) {
    const order = input.sort_order
    if (order !== undefined && (!Number.isInteger(order) || order < 0)) {
      errors.sort_order = 'Sort order must be zero or more'
    }
  }

  return { valid: Object.keys(errors).length === 0, errors }
}

function formatValidationErrors(errors: Record<string, string>): string {
  return Object.values(errors).join('; ')
}

// ── audit (best-effort, T31) ──────────────────────────────────

/**
 * Write a row to `audit_logs`. Best-effort: errors are swallowed so
 * the primary operation (create / update / deactivate) is never
 * rolled back by a logging failure.  T31 adds hardening/alerting.
 */
async function writeAuditLog(
  action: string,
  entityId: string,
  details: Record<string, unknown>,
): Promise<void> {
  const { error } = await supabase
    .from('audit_logs')
    .insert({
      admin_user_id: (await supabase.auth.getUser()).data.user?.id ?? null,
      action,
      entity: 'service',
      entity_id: entityId,
      details,
    })

  if (error) {
    // Intentionally swallowed — audit is best-effort (T31).
    console.warn('[services] audit write failed:', error.message)
  }
}

export type { MappedError } from './errors'