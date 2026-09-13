/**
 * Render a localized message for a mapped auth API error (T6).
 * Falls back to the API's own EN/AR message when the translation key is
 * unknown, so a new Supabase error code never surfaces as a raw key.
 */

import type { TFunction } from 'i18next'
import type { MappedError } from './supabase/errors'

export function apiErrorMessage(t: TFunction<'translation'>, error: MappedError): string {
  const key = `auth.apiError.${error.code ?? 'UNKNOWN'}`
  const translated = t(key)
  if (translated !== key) return translated
  return error.message || t('auth.apiError.UNKNOWN')
}

/**
 * Localize a mapped API error through a caller-supplied namespace first
 * (e.g. `profile.apiError.*`), falling back to the auth catalog and then
 * to the API's own message. Keeps each screen's wording domain-specific
 * while never surfacing a raw key (T7).
 */
export function localizedApiErrorMessage(
  t: TFunction<'translation'>,
  namespace: 'auth' | 'profile',
  error: MappedError,
): string {
  const nsKey = `${namespace}.apiError.${error.code ?? 'UNKNOWN'}`
  const nsText = t(nsKey)
  if (nsText !== nsKey) return nsText
  return apiErrorMessage(t, error)
}