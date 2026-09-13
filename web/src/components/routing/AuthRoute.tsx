/**
 * AuthRoute (T6). Route guards for the auth area.
 *
 * - `guest`    : only anonymous visitors can view (login, register,
 *                forgot/reset password). Signed-in users bounce to home.
 * - `protected`: requires a session; anonymous visitors are sent to
 *                /auth/login?redirect=<current> (return-to-booking, T6).
 */

import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { useAuth } from '../../context/AuthContext'
import { resolveRedirectPath } from '../../lib/navigation'

export function GuestRoute({ children }: { children: ReactNode }) {
  const { phase } = useAuth()
  const location = useLocation()

  if (phase === 'loading') {
    return <AuthLoading />
  }

  if (phase === 'authenticated') {
    // Preserve an in-flight redirect intent if the visitor logs out later.
    const target = resolveRedirectPath(location.search)
    return <Navigate to={target} replace />
  }

  return <>{children}</>
}

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { phase } = useAuth()
  const location = useLocation()

  if (phase === 'loading') {
    return <AuthLoading />
  }

  if (phase === 'anonymous') {
    const search = new URLSearchParams({
      redirect: location.pathname + location.search,
    })
    return <Navigate to={`/auth/login?${search.toString()}`} replace />
  }

  return <>{children}</>
}

function AuthLoading() {
  const { t } = useTranslation()
  return (
    <div className="auth-shell">
      <div className="auth-shell__card auth-shell__card--centered">
        <div className="spinner" aria-hidden="true" />
        <p aria-live="polite">{t('common.loading')}</p>
      </div>
    </div>
  )
}