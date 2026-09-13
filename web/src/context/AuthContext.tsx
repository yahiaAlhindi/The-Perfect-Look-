/**
 * AuthProvider (T6). Wraps the app with live session + profile state from
 * Supabase Auth, and keeps i18n/`<html>` in sync with the user's language.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import i18n, {
  applyLanguageToDocument,
  getStoredLanguage,
  storeLanguage,
  type AppLanguage,
} from '../i18n'
import {
  getProfile,
  getSession,
  getUser,
  onAuthStateChange,
  signOut as apiSignOut,
  type AuthResult,
} from '../lib/supabase/auth'
import { supabase } from '../lib/supabase/client'
import type { Profile } from '../lib/supabase/types'

export type AuthPhase = 'loading' | 'authenticated' | 'anonymous'

interface AuthContextValue {
  phase: AuthPhase
  session: Awaited<ReturnType<typeof getSession>>['session']
  user: Awaited<ReturnType<typeof getUser>>['user'] | null
  profile: Profile | null
  /** Guest-level language (persisted locally). Profile wins when signed in. */
  language: AppLanguage
  setLanguage: (lang: AppLanguage, opts?: { persistToProfile?: boolean }) => void
  /** Visible client number; null until T37 exposes it. */
  clientNumber: string | null
  refreshProfile: () => Promise<void>
  signOut: () => Promise<AuthResult>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

function isAppLanguage(value: unknown): value is AppLanguage {
  return value === 'en' || value === 'ar'
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [phase, setPhase] = useState<AuthPhase>('loading')
  const [session, setSession] = useState<AuthContextValue['session']>(null)
  const [user, setUser] = useState<AuthContextValue['user']>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [language, setLanguageState] = useState<AppLanguage>(() =>
    getStoredLanguage(),
  )

  const applyLanguage = useCallback((lang: AppLanguage) => {
    if (i18n.language === lang) {
      applyLanguageToDocument(lang)
      return
    }
    storeLanguage(lang)
    setLanguageState(lang)
    void i18n.changeLanguage(lang)
    applyLanguageToDocument(lang)
  }, [])

  useEffect(() => {
    applyLanguage(getStoredLanguage())
  }, [applyLanguage])

  const refreshProfile = useCallback(async () => {
    const { profile: next, error } = await getProfile()
    if (!error) setProfile(next)
  }, [])

  useEffect(() => {
    let cancelled = false

    async function init() {
      const { session: s } = await getSession()
      if (cancelled) return
      setSession(s)

      const { user: u } = await getUser()
      if (cancelled) return
      setUser(u)

      if (u) {
        const { profile: p, error } = await getProfile()
        if (cancelled) return
        if (!error && p) {
          setProfile(p)
          if (isAppLanguage(p.preferred_language)) {
            applyLanguage(p.preferred_language)
          }
        }
        setPhase('authenticated')
      } else {
        setPhase('anonymous')
      }
    }

    void init()

    const unsubscribe = onAuthStateChange((event) => {
      if (event === 'SIGNED_IN') {
        setPhase('authenticated')
        void refreshProfile()
      } else if (event === 'SIGNED_OUT' || event === 'USER_DELETED') {
        setPhase('anonymous')
        setUser(null)
        setProfile(null)
        applyLanguage(getStoredLanguage())
      }
    })

    return () => {
      cancelled = true
      unsubscribe()
    }
  }, [applyLanguage, refreshProfile])

  const setLanguage = useCallback(
    (lang: AppLanguage, opts?: { persistToProfile?: boolean }) => {
      if (opts?.persistToProfile && user) {
        // Best-effort: persist to the user's metadata (T7 owns full sync).
        void supabase.auth.updateUser({
          data: { preferred_language: lang },
        })
      }
      applyLanguage(lang)
    },
    [applyLanguage, user],
  )

  const signOut = useCallback(async () => {
    const result = await apiSignOut()
    // Auth state events elsewhere in this provider flip `phase` back to
    // anonymous; propagate the outcome for callers that render errors.
    return result
  }, [])

  const clientNumber = useMemo(
    () => profile?.client_number ?? null,
    [profile],
  )

  const value = useMemo<AuthContextValue>(
    () => ({
      phase,
      session,
      user,
      profile,
      language,
      setLanguage,
      clientNumber,
      refreshProfile,
      signOut,
    }),
    [phase, session, user, profile, language, setLanguage, clientNumber, refreshProfile, signOut],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) {
    throw new Error('useAuth must be used inside <AuthProvider>')
  }
  return ctx
}