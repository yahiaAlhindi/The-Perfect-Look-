/**
 * ResetPasswordPage (T6). Entry point for the password-reset email link.
 * Extracts the recovery token (HashRouter-safe), exchanges it for a
 * session, then lets the visitor set a new password.
 */

import { useEffect, useState, type FormEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { Link, useNavigate } from 'react-router-dom'
import AuthLayout from '../components/auth/AuthLayout'
import AlertBanner from '../components/auth/AlertBanner'
import AuthField from '../components/auth/AuthField'
import { useAuth } from '../context/AuthContext'
import { updatePassword } from '../lib/supabase/auth'
import type { MappedError } from '../lib/supabase/errors'
import {
  establishRecoverySession,
  extractRecoveryTokens,
} from '../lib/recovery'
import { isValidPassword } from '../lib/supabase/validation'
import { apiErrorMessage } from '../lib/apiError'

type ResetStatus = 'checking' | 'ready' | 'invalid' | 'done'

export default function ResetPasswordPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { signOut } = useAuth()

  const [status, setStatus] = useState<ResetStatus>('checking')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [fieldErrors, setFieldErrors] = useState<{
    password?: string
    confirmPassword?: string
  }>({})
  const [generalError, setGeneralError] = useState<MappedError | null>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    let cancelled = false

    async function init() {
      const tokens = extractRecoveryTokens()
      if (!tokens) {
        if (!cancelled) setStatus('invalid')
        return
      }

      const ok = await establishRecoverySession(tokens)
      if (!cancelled) setStatus(ok ? 'ready' : 'invalid')
    }

    void init()
    return () => {
      cancelled = true
    }
  }, [])

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setGeneralError(null)

    const errors: typeof fieldErrors = {}
    if (!isValidPassword(password)) {
      errors.password = t('auth.validation.passwordInvalid')
    }
    if (!confirmPassword) {
      errors.confirmPassword = t('auth.validation.confirmPasswordRequired')
    }
    if (confirmPassword && password !== confirmPassword) {
      errors.confirmPassword = t('auth.validation.confirmPasswordMismatch')
    }
    setFieldErrors(errors)
    if (errors.password || errors.confirmPassword) return

    setSubmitting(true)
    const result = await updatePassword(password)
    setSubmitting(false)

    if (!result.success) {
      setGeneralError(
        result.error ?? { code: 'UNKNOWN', message: t('auth.apiError.UNKNOWN') },
      )
      return
    }

    setStatus('done')
  }

  if (status === 'checking') {
    return (
      <AuthLayout>
        <div className="auth-shell__card--centered">
          <div className="spinner" aria-hidden="true" />
          <p aria-live="polite">{t('common.loading')}</p>
        </div>
      </AuthLayout>
    )
  }

  if (status === 'invalid') {
    return (
      <AuthLayout>
        <h1 className="auth-title">{t('auth.reset.invalidTitle')}</h1>
        <AlertBanner variant="error">{t('auth.reset.invalidBody')}</AlertBanner>
        <Link className="btn btn--primary btn--block" to="/auth/forgot-password">
          {t('auth.reset.requestNewLink')}
        </Link>
        <Link className="btn btn--secondary btn--block" to="/auth/login">
          {t('auth.backToLogin')}
        </Link>
      </AuthLayout>
    )
  }

  if (status === 'done') {
    return (
      <AuthLayout>
        <h1 className="auth-title">{t('auth.reset.successTitle')}</h1>
        <AlertBanner variant="success">{t('auth.reset.successBody')}</AlertBanner>
        <button
          type="button"
          className="btn btn--primary btn--block"
          onClick={async () => {
            await signOut()
            navigate('/auth/login', { replace: true })
          }}
        >
          {t('auth.reset.goToLogin')}
        </button>
      </AuthLayout>
    )
  }

  return (
    <AuthLayout>
      <h1 className="auth-title">{t('auth.reset.title')}</h1>
      <p className="auth-subtitle">{t('auth.reset.subtitle')}</p>

      {generalError && (
        <AlertBanner variant="error">{apiErrorMessage(t, generalError)}</AlertBanner>
      )}

      <form className="auth-form" onSubmit={handleSubmit} noValidate>
        <AuthField label={t('auth.reset.password')} htmlFor="reset-new-password" error={fieldErrors.password} required>
          <input
            id="reset-new-password"
            type="password"
            className="auth-input"
            autoComplete="new-password"
            placeholder={t('auth.reset.passwordPlaceholder')}
            value={password}
            aria-invalid={Boolean(fieldErrors.password)}
            onChange={(e) => setPassword(e.target.value)}
          />
          <p className="auth-field__hint">{t('auth.reset.passwordHint')}</p>
        </AuthField>

        <AuthField label={t('auth.reset.confirmPassword')} htmlFor="reset-confirm" error={fieldErrors.confirmPassword} required>
          <input
            id="reset-confirm"
            type="password"
            className="auth-input"
            autoComplete="new-password"
            placeholder={t('auth.reset.confirmPasswordPlaceholder')}
            value={confirmPassword}
            aria-invalid={Boolean(fieldErrors.confirmPassword)}
            onChange={(e) => setConfirmPassword(e.target.value)}
          />
        </AuthField>

        <button type="submit" className="btn btn--primary btn--block" disabled={submitting}>
          {submitting ? t('common.submitting') : t('auth.reset.submit')}
        </button>
      </form>

      <p className="auth-alt">
        <Link className="auth-link" to="/auth/login">
          {t('auth.backToLogin')}
        </Link>
      </p>
    </AuthLayout>
  )
}