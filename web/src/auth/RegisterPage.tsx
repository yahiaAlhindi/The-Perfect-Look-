/**
 * RegisterPage (T6). Account creation with full validation (SRS §5),
 * required + optional consent, language preference and a success screen
 * that shows the client number once T37 provides it.
 */

import { useMemo, useState, type FormEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { Link, useNavigate } from 'react-router-dom'
import AuthLayout from '../components/auth/AuthLayout'
import AuthField from '../components/auth/AuthField'
import PasswordInput from '../components/auth/PasswordInput'
import AlertBanner from '../components/auth/AlertBanner'
import { useAuth } from '../context/AuthContext'
import { signUp } from '../lib/supabase/auth'
import { recordSignupConsents } from '../lib/supabase/consents'
import type { MappedError } from '../lib/supabase/errors'
import { normalizeMobile, validateSignUp } from '../lib/supabase/validation'
import { apiErrorMessage } from '../lib/apiError'

interface RegisterFormState {
  fullName: string
  email: string
  mobile: string
  password: string
  confirmPassword: string
  dob: string
  gender: string
  consentService: boolean
  consentMarketing: boolean
}

const initialState: RegisterFormState = {
  fullName: '',
  email: '',
  mobile: '',
  password: '',
  confirmPassword: '',
  dob: '',
  gender: '',
  consentService: false,
  consentMarketing: false,
}

export default function RegisterPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { language } = useAuth()

  const [form, setForm] = useState<RegisterFormState>(initialState)
  const [fieldErrors, setFieldErrors] = useState<
    Partial<Record<keyof RegisterFormState, string>>
  >({})
  const [consentError, setConsentError] = useState(false)
  const [generalError, setGeneralError] = useState<MappedError | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [registered, setRegistered] = useState(false)

  const today = useMemo(() => new Date().toISOString().slice(0, 10), [])

  function set<K extends keyof RegisterFormState>(
    key: K,
    value: RegisterFormState[K],
  ) {
    setForm((prev) => ({ ...prev, [key]: value }))
    if (key === 'consentService' && value) {
      setConsentError(false)
    }
  }

  function updateErrors(next: Partial<Record<keyof RegisterFormState, string>>) {
    setFieldErrors(next)
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setGeneralError(null)
    updateErrors({})

    // API-boundary validation (mirrors DB rules, SRS §5)
    const validation = validateSignUp({
      fullName: form.fullName,
      email: form.email,
      mobile: form.mobile,
      password: form.password,
      confirmPassword: form.confirmPassword,
    })

    const errors: Partial<Record<keyof RegisterFormState, string>> = {
      ...validation.errors,
    }

    // Required consent blocks submission (SRS §5.1)
    const consentMissing = !form.consentService
    setConsentError(consentMissing)

    if (!validation.valid || consentMissing) {
      updateErrors(errors)
      return
    }

    setSubmitting(true)
    const result = await signUp({
      fullName: form.fullName,
      email: validation.normalizedEmail ?? form.email.trim().toLowerCase(),
      mobile: normalizeMobile(form.mobile),
      password: form.password,
      dob: form.dob || undefined,
      gender: form.gender || undefined,
      preferredLanguage: language,
    })
    setSubmitting(false)

    if (!result.success) {
      setGeneralError(
        result.error ?? { code: 'UNKNOWN', message: t('auth.apiError.UNKNOWN') },
      )
      updateErrors(errors)
      return
    }

    setRegistered(true)

    // Best-effort: persist the consent choices made here (only possible
    // when a session exists right away, e.g. auto-confirmed email).
    void recordSignupConsents({
      service: form.consentService,
      marketing: form.consentMarketing,
    })
  }

  if (registered) {
    return (
      <RegisterSuccess
        email={form.email.toLowerCase()}
        onHome={() => navigate('/')}
      />
    )
  }

  return (
    <AuthLayout>
      <h1 className="auth-title">{t('auth.register.title')}</h1>
      <p className="auth-subtitle">{t('auth.register.subtitle')}</p>

      {generalError && (
        <AlertBanner variant="error">{apiErrorMessage(t, generalError)}</AlertBanner>
      )}

      <form className="auth-form" onSubmit={handleSubmit} noValidate>
        <AuthField
          label={t('auth.register.fullName')}
          htmlFor="reg-name"
          error={fieldErrors.fullName}
          required
        >
          <input
            id="reg-name"
            name="fullName"
            type="text"
            autoComplete="name"
            className="auth-input"
            placeholder={t('auth.register.fullNamePlaceholder')}
            value={form.fullName}
            aria-invalid={Boolean(fieldErrors.fullName)}
            onChange={(e) => set('fullName', e.target.value)}
          />
        </AuthField>

        <AuthField
          label={t('auth.register.email')}
          htmlFor="reg-email"
          error={fieldErrors.email}
          required
        >
          <input
            id="reg-email"
            name="email"
            type="email"
            autoComplete="email"
            className="auth-input"
            inputMode="email"
            placeholder={t('auth.register.emailPlaceholder')}
            value={form.email}
            aria-invalid={Boolean(fieldErrors.email)}
            onChange={(e) => set('email', e.target.value)}
          />
        </AuthField>

        <AuthField
          label={t('auth.register.mobile')}
          htmlFor="reg-mobile"
          error={fieldErrors.mobile}
          required
        >
          <input
            id="reg-mobile"
            name="mobile"
            type="tel"
            autoComplete="tel"
            className="auth-input"
            inputMode="tel"
            dir="ltr"
            placeholder={t('auth.register.mobilePlaceholder')}
            value={form.mobile}
            aria-invalid={Boolean(fieldErrors.mobile)}
            onChange={(e) => set('mobile', e.target.value)}
          />
        </AuthField>

        <PasswordInput
          id="reg-password"
          label={t('auth.register.password')}
          name="password"
          value={form.password}
          onChange={(v) => set('password', v)}
          placeholder={t('auth.register.passwordPlaceholder')}
          error={fieldErrors.password}
          hint={t('auth.register.passwordHint')}
          autoComplete="new-password"
        />

        <PasswordInput
          id="reg-confirm"
          label={t('auth.register.confirmPassword')}
          name="confirmPassword"
          value={form.confirmPassword}
          onChange={(v) => set('confirmPassword', v)}
          placeholder={t('auth.register.confirmPasswordPlaceholder')}
          error={fieldErrors.confirmPassword}
          autoComplete="new-password"
        />

        <AuthField
          label={t('auth.register.dobOptional')}
          htmlFor="reg-dob"
          error={fieldErrors.dob}
        >
          <input
            id="reg-dob"
            name="dob"
            type="date"
            className="auth-input"
            max={today}
            value={form.dob}
            onChange={(e) => set('dob', e.target.value)}
          />
        </AuthField>

        <AuthField
          label={t('auth.register.genderOptional')}
          htmlFor="reg-gender"
        >
          <select
            id="reg-gender"
            name="gender"
            className="auth-input"
            value={form.gender}
            onChange={(e) => set('gender', e.target.value)}
          >
            <option value="">{t('auth.register.selectGender')}</option>
            <option value="female">{t('auth.register.genderFemale')}</option>
            <option value="male">{t('auth.register.genderMale')}</option>
            <option value="unspecified">
              {t('auth.register.genderUnspecified')}
            </option>
          </select>
        </AuthField>

        <section className="auth-consent" aria-label={t('auth.consentSectionLabel')}>
          <label
            className={`auth-consent__item${consentError ? ' has-error' : ''}`}
          >
            <input
              type="checkbox"
              checked={form.consentService}
              onChange={(e) => set('consentService', e.target.checked)}
            />
            <span>
              {t('auth.register.consentService')}{' '}
              <strong className="auth-consent__tag">
                {t('auth.register.consentServiceRequired')}
              </strong>
            </span>
          </label>
          {consentError && (
            <p className="auth-field__error" role="alert">
              {t('auth.validation.consentRequired')}
            </p>
          )}

          <label className="auth-consent__item">
            <input
              type="checkbox"
              checked={form.consentMarketing}
              onChange={(e) => set('consentMarketing', e.target.checked)}
            />
            <span>
              {t('auth.register.consentMarketing')}{' '}
              <span className="auth-consent__tag auth-consent__tag--muted">
                {t('auth.register.consentMarketingOptional')}
              </span>
            </span>
          </label>
        </section>

        <button type="submit" className="btn btn--primary btn--block" disabled={submitting}>
          {submitting ? t('common.submitting') : t('auth.register.submit')}
        </button>
      </form>

      <p className="auth-alt">
        {t('auth.alreadyHaveAccount')}{' '}
        <Link className="auth-link" to="/auth/login">
          {t('auth.linkLogin')}
        </Link>
      </p>
    </AuthLayout>
  )
}

/**
 * Post-registration screen. Shows a visible client number (T6 note) — the
 * value comes from the profile once T37 exposes it; until then a placeholder
 * plus guidance is shown.
 */

function RegisterSuccess({
  email,
  onHome,
}: {
  email: string
  onHome: () => void
}) {
  const { t } = useTranslation()
  const { clientNumber } = useAuth()
  const visibleNumber = clientNumber ?? t('auth.register.clientNumberPlaceholder')

  return (
    <AuthLayout>
      <h1 className="auth-title">{t('auth.register.successTitle')}</h1>

      <AlertBanner variant="success">
        {t('auth.register.successBody')}{' '}
        <strong>{email}</strong>
      </AlertBanner>

      <div className="client-number" data-testid="client-number">
        <span className="client-number__label">
          {t('auth.register.clientNumberLabel')}
        </span>
        <span className="client-number__value">{visibleNumber}</span>
        {!clientNumber && (
          <span className="client-number__note">
            {t('auth.register.clientNumberNote')}
          </span>
        )}
      </div>

      <div className="auth-actions">
        <button type="button" className="btn btn--primary btn--block" onClick={onHome}>
          {t('auth.register.backToHome')}
        </button>
        <Link className="btn btn--secondary btn--block" to="/auth/login">
          {t('auth.linkLogin')}
        </Link>
      </div>
    </AuthLayout>
  )
}