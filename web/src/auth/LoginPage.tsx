/**
 * LoginPage (T6). Sign in with email OR mobile number + password, with
 * "return to booking" support: after a successful sign-in the visitor is
 * sent back to `?redirect=` when set.
 */

import { useState, type FormEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import AuthLayout from '../components/auth/AuthLayout'
import AuthField from '../components/auth/AuthField'
import PasswordInput from '../components/auth/PasswordInput'
import AlertBanner from '../components/auth/AlertBanner'
import { useAuth } from '../context/AuthContext'
import { signIn } from '../lib/supabase/auth'
import type { MappedError } from '../lib/supabase/errors'
import { resolveRedirectPath } from '../lib/navigation'
import { apiErrorMessage } from '../lib/apiError'

export default function LoginPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const { refreshProfile } = useAuth()

  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [fieldError, setFieldError] = useState<{
    identifier?: string
    password?: string
  }>({})
  const [generalError, setGeneralError] = useState<MappedError | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const target = resolveRedirectPath(params.toString())

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setGeneralError(null)
    setFieldError({})

    const errors: typeof fieldError = {}
    if (!identifier.trim()) errors.identifier = t('auth.validation.emailRequired')
    if (!password) errors.password = t('auth.validation.passwordRequired')
    if (errors.identifier || errors.password) {
      setFieldError(errors)
      return
    }

    setSubmitting(true)
    const result = await signIn(identifier, password)
    setSubmitting(false)

    if (!result.success) {
      setGeneralError(result.error ?? {
        code: 'UNKNOWN',
        message: t('auth.apiError.UNKNOWN'),
      })
      return
    }

    await refreshProfile()
    navigate(target, { replace: true })
  }

  return (
    <AuthLayout>
      <h1 className="auth-title">{t('auth.login.title')}</h1>
      <p className="auth-subtitle">{t('auth.login.subtitle')}</p>

      {generalError && (
        <AlertBanner variant="error">{apiErrorMessage(t, generalError)}</AlertBanner>
      )}

      <form className="auth-form" onSubmit={handleSubmit} noValidate>
        <AuthField
          label={t('auth.login.identifier')}
          htmlFor="login-identifier"
          error={fieldError.identifier}
          required
        >
          <input
            id="login-identifier"
            name="identifier"
            type="text"
            inputMode="text"
            autoComplete="username"
            className="auth-input"
            placeholder={t('auth.login.identifierPlaceholder')}
            value={identifier}
            aria-invalid={Boolean(fieldError.identifier)}
            onChange={(e) => setIdentifier(e.target.value)}
          />
        </AuthField>

        <PasswordInput
          id="login-password"
          label={t('auth.login.password')}
          name="password"
          value={password}
          onChange={setPassword}
          placeholder={t('auth.login.passwordPlaceholder')}
          error={fieldError.password}
          autoComplete="current-password"
        />

        <div className="auth-form__row">
          <Link className="auth-link" to="/auth/forgot-password">
            {t('auth.login.forgotPassword')}
          </Link>
        </div>

        <button type="submit" className="btn btn--primary btn--block" disabled={submitting}>
          {submitting ? t('common.submitting') : t('auth.login.submit')}
        </button>
      </form>

      {target !== '/' && (
        <AlertBanner variant="info">
          {t('auth.login.returningToBooking')}
        </AlertBanner>
      )}

      <p className="auth-alt">
        {t('auth.login.noAccount')}{' '}
        <Link className="auth-link" to="/auth/register">
          {t('auth.linkRegister')}
        </Link>
      </p>
    </AuthLayout>
  )
}