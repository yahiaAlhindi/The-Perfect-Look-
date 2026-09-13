/**
 * Return-to-booking helper (T6).
 * The auth pages read a `redirect` query param (set when a guest hits an
 * action that needs authentication, e.g. confirming a booking) and bounce
 * back there after a successful sign in / sign up. To avoid open-redirect
 * abuse only same-app hash paths are accepted.
 */

const ALLOWED_ROOTS = ['/booking', '/book', '/appointments', '/profile']

/**
 * Extract and sanitise a `redirect` target from a query string.
 * Accepts only in-app paths; anything external or malformed falls back
 * to the given `fallback`.
 */
export function resolveRedirectPath(
  search: string,
  fallback = '/',
): string {
  if (!search) return fallback
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search)
  const raw = params.get('redirect')
  if (!raw || !raw.startsWith('/')) return fallback

  // Block protocol-relative (//host) and scheme URLs passed in the path.
  if (raw.startsWith('//')) return fallback
  try {
    const parsed = new URL(raw, window.location.href)
    if (parsed.origin !== window.location.origin) return fallback
  } catch {
    return fallback
  }

  if (ALLOWED_ROOTS.some((root) => raw === root || raw.startsWith(root + '/'))) {
    return raw
  }
  return fallback
}