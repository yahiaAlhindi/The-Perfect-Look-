/**
 * ForgotPasswordPage (T6). Sends a password reset email. The response is
 * intentionally identical whether or not the account exists, to avoid
 * account enumeration.
 */

import { useState, type FormEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import AuthLayout from '../components/auth/AuthLayout'
import AuthField from '../components/auth/AuthField'
import AlertBanner from '../components/auth/AlertBanner'
import { resetPassword } from '../lib/supabase/auth'
import type { MappedError } from '../lib/supabase/errors'
import { validateEmail } from '../lib/supabase/validation'
import { buildRecoveryRedirectTo } from '../lib/recovery'
import { apiErrorMessage } from '../lib/apiError'

export default function ForgotPasswordPage() {
  const { t } = useTranslation()

  const [email, setEmail] = useState('')
  const [emailError, setEmailError] = useState<string | null>(null)
  const [generalError, setGeneralError] = useState<MappedError | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [sent, setSent] = useState(false)

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setGeneralError(null)

    if (!validateEmail(email)) {
      setEmailError(t('auth.validation.emailInvalid'))
      return
    }
    setEmailError(null)

    setSubmitting(true)
    const result = await resetPassword(email, buildRecoveryRedirectTo())
    setSubmitting(false)

    if (!result.success) {
      setGeneralError(
        result.error ?? { code: 'UNKNOWN', message: t('auth.apiError.UNKNOWN') },
      )
      return
    }

    setSent(true)
  }

  if (sent) {
    return (
      <AuthLayout>
        <h1 className="auth-title">{t('auth.forgot.sentTitle')}</h1>
        <AlertBanner variant="success">
          {t('auth.forgot.sentBody')}
        </AlertBanner>
        <p className="auth-subtitle">{t('auth.forgot.sentSpamNote')}</p>
        <Link className="btn btn--secondary btn--block" to="/auth/login">
          {t('auth.backToLogin')}
        </Link>
      </AuthLayout>
    )
  }

  return (
    <AuthLayout>
      <h1 className="auth-title">{t('auth.forgot.title')}</h1>
      <p className="auth-subtitle">{t('auth.forgot.subtitle')}</p>

      {generalError && (
        <AlertBanner variant="error">{apiErrorMessage(t, generalError)}</AlertBanner>
      )}

      <form className="auth-form" onSubmit={handleSubmit} noValidate>
        <AuthField
          label={t('auth.forgot.email')}
          htmlFor="forgot-email"
          error={emailError}
          required
        >
          <input
            id="forgot-email"
            name="email"
            type="email"
            autoComplete="email"
            className="auth-input"
            inputMode="email"
            placeholder={t('auth.forgot.emailPlaceholder')}
            value={email}
            aria-invalid={Boolean(emailError)}
            onChange={(e) => setEmail(e.target.value)}
          />
        </AuthField>

        <button type="submit" className="btn btn--primary btn--block" disabled={submitting}>
          {submitting ? t('common.submitting') : t('auth.forgot.submit')}
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