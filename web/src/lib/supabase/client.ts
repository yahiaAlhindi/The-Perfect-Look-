import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as
  | string
  | undefined

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Supabase is not configured. Copy web/.env.example to web/.env and set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.',
  )
}

/**
 * The single authenticated Supabase client for the whole app.
 * All P2 screens use this module instead of constructing their own
 * client (T5 — "Expose a client API module (supabase/client.ts)").
 *
 * - `persistSession`: the session is kept in browser storage so a
 *   refresh keeps the user logged in (SRS §6).
 * - `autoRefreshToken`: silently refreshes the JWT before it expires.
 * - `detectSessionInUrl`: picks up the recovery/verify tokens that
 *   Supabase appends to the URL after e.g. a password-reset email.
 */
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})

export * from './auth'
export * from './services'
export * from './profiles'
export * from './availability'
export * from './errors'
export * from './validation'
export type * from './types'