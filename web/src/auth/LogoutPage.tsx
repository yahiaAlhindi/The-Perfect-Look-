/**
 * LogoutPage (T6). Confirms before signing out; if the visitor is already
 * anonymous (e.g. expired session) it shows the signed-out state directly.
 */

import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link, useNavigate } from 'react-router-dom'
import AuthLayout from '../components/auth/AuthLayout'
import AlertBanner from '../components/auth/AlertBanner'
import { useAuth } from '../context/AuthContext'
import type { MappedError } from '../lib/supabase/errors'
import { apiErrorMessage } from '../lib/apiError'

export default function LogoutPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { phase, signOut } = useAuth()

  const [signingOut, setSigningOut] = useState(false)
  const [error, setError] = useState<MappedError | null>(null)

  const alreadySignedOut = phase === 'anonymous'

  async function handleConfirm() {
    setError(null)
    setSigningOut(true)
    const result = await signOut()
    setSigningOut(false)

    if (result && !result.success) {
      setError(result.error ?? { code: 'UNKNOWN', message: t('auth.apiError.UNKNOWN') })
    }
    // On success, the auth-state listener flips `phase` to anonymous and
    // this page re-renders into the signed-out state.
  }

  if (alreadySignedOut) {
    return (
      <AuthLayout>
        <h1 className="auth-title">{t('auth.logout.doneTitle')}</h1>
        <AlertBanner variant="success">{t('auth.logout.doneBody')}</AlertBanner>
        <Link className="btn btn--primary btn--block" to="/auth/login">
          {t('auth.logout.goToLogin')}
        </Link>
      </AuthLayout>
    )
  }

  return (
    <AuthLayout>
      <h1 className="auth-title">{t('auth.logout.title')}</h1>

      {error && (
        <AlertBanner variant="error">{apiErrorMessage(t, error)}</AlertBanner>
      )}

      <p className="auth-subtitle">{t('auth.logout.confirmBody')}</p>

      <div className="auth-actions">
        <button
          type="button"
          className="btn btn--primary btn--block"
          disabled={signingOut}
          onClick={handleConfirm}
        >
          {signingOut ? t('common.submitting') : t('auth.logout.confirmButton')}
        </button>
        <button
          type="button"
          className="btn btn--secondary btn--block"
          onClick={() => navigate(-1)}
        >
          {t('auth.logout.cancelButton')}
        </button>
      </div>
    </AuthLayout>
  )
}