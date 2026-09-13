/**
 * ProfilePage (T7). The signed-in customer's account screen: editable
 * personal details (full name, DOB, gender, preferred language — the
 * fields `PUT /profile` allows, T8), read-only client number / email /
 * mobile, consent preferences (append-only, T8), password change (T8)
 * and the "request my data" entry point (SRS §17).
 *
 * Sensitive nutrition/health data is intentionally NOT shown here — it
 * lives in a separate secured flow to keep protected data apart (SRS §17
 * separation-of-concerns for health records).
 */

import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { CalendarDays, Download, History, LogOut, ShieldCheck } from 'lucide-react'

import { Badge } from '../components/ui/badge'
import { Button } from '../components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '../components/ui/card'
import { Checkbox } from '../components/ui/checkbox'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '../components/ui/dialog'
import { Input } from '../components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '../components/ui/select'
import { Separator } from '../components/ui/separator'
import { toast } from '../components/ui/toaster'
import { PageHeader } from '../components/layout/page-header'
import AuthField from '../components/auth/AuthField'
import AlertBanner from '../components/auth/AlertBanner'
import PasswordInput from '../components/auth/PasswordInput'
import LanguageSwitcher from '../components/auth/LanguageSwitcher'

import { useAuth } from '../context/AuthContext'
import type { AppLanguage } from '../i18n'
import { localizedApiErrorMessage } from '../lib/apiError'
import { changePassword, updateProfile } from '../lib/supabase/auth'
import {
  getConsentHistory,
  latestConsent,
  recordConsent,
  requestDataExport,
  type ConsentListResult,
} from '../lib/supabase/consents'
import type { ConsentRow, ConsentType } from '../lib/supabase/types'
import {
  validatePasswordChange,
  validateProfileUpdate,
} from '../lib/supabase/validation'

/* ---------------------------------------------------------------------------
 * helpers
 * ------------------------------------------------------------------------- */

function formatDateTime(iso: string, lang: string): string {
  try {
    return new Intl.DateTimeFormat(lang === 'ar' ? 'ar-AE' : 'en-GB', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(new Date(iso))
  } catch {
    return iso
  }
}

function consentTopicLabel(type: ConsentType, t: ReturnType<typeof useTranslation>['t']): string {
  return type === 'terms_service'
    ? t('profile.consentService')
    : t('profile.consentMarketing')
}

const GENDER_LABEL_KEYS = {
  female: 'profile.genderFemale',
  male: 'profile.genderMale',
  unspecified: 'profile.genderUnspecified',
} as const

/* ---------------------------------------------------------------------------
 * Page
 * ------------------------------------------------------------------------- */

export default function ProfilePage() {
  const { t } = useTranslation()
  const { phase } = useAuth()

  return (
    <div className="min-h-svh bg-background">
      <header className="sticky top-0 z-40 border-b bg-background/90 backdrop-blur">
        <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-between gap-3 px-4 py-3">
          <span className="text-base font-bold tracking-tight">
            {t('common.appName')}
          </span>
          <div className="flex items-center gap-2">
            <LanguageSwitcher />
            <Button asChild variant="ghost" size="sm">
              <Link to="/auth/logout">
                <LogOut aria-hidden="true" />
                {t('profile.signOut')}
              </Link>
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-3xl space-y-6 px-4 py-8">
        <PageHeader
          eyebrow="Patient"
          title={t('profile.title')}
          description={t('profile.subtitle')}
        />

        {phase !== 'authenticated' && (
          <AlertBanner variant="info">{t('profile.apiError.NOT_AUTHENTICATED')}</AlertBanner>
        )}

        <DetailsSection />

        <Divider />

        <ConsentSection />

        <Divider />

        <DataSection />

        <Divider />

        <PasswordSection />
      </main>
    </div>
  )
}

function Divider() {
  return <Separator />
}

/* ---------------------------------------------------------------------------
 * Personal details
 * ------------------------------------------------------------------------- */

function DetailsSection() {
  const { t } = useTranslation()
  const { profile, clientNumber, language, setLanguage, refreshProfile } = useAuth()

  const [fullName, setFullName] = useState(profile?.full_name ?? '')
  const [dob, setDob] = useState(profile?.dob ?? '')
  const [gender, setGender] = useState(profile?.gender ?? '')
  const [languageDraft, setLanguageDraft] = useState<AppLanguage>(
    profile?.preferred_language === 'ar' ? 'ar' : 'en',
  )
  const [errors, setErrors] = useState<{ fullName?: string; dob?: string }>({})
  const [saving, setSaving] = useState(false)
  const [banner, setBanner] = useState<{ variant: 'success' | 'error'; text: string } | null>(null)

  useEffect(() => {
    setFullName(profile?.full_name ?? '')
    setDob(profile?.dob ?? '')
    setGender(profile?.gender ?? '')
    setLanguageDraft(profile?.preferred_language === 'ar' ? 'ar' : 'en')
  }, [profile])

  const today = useMemo(() => new Date().toISOString().slice(0, 10), [])

  async function handleSave(event: FormEvent) {
    event.preventDefault()
    setBanner(null)

    const validation = validateProfileUpdate({
      fullName,
      dob: dob || null,
      gender: gender || null,
      preferredLanguage: languageDraft,
    })
    setErrors({ fullName: validation.errors.fullName, dob: validation.errors.dob })
    if (!validation.valid) return

    setSaving(true)
    const result = await updateProfile({
      full_name: fullName,
      dob: dob || null,
      gender: gender || null,
      preferred_language: languageDraft,
    })
    setSaving(false)

    if (!result.success) {
      setBanner({
        variant: 'error',
        text: result.error
          ? localizedApiErrorMessage(t, 'profile', result.error)
          : t('profile.saveFailed'),
      })
      return
    }

    await refreshProfile()
    if (languageDraft !== language) {
      setLanguage(languageDraft)
    }
    setBanner({ variant: 'success', text: t('profile.saved') })
    toast.success(t('profile.saved'))
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('profile.detailsTitle')}</CardTitle>
        <CardDescription>{t('profile.detailsIntro')}</CardDescription>
      </CardHeader>
      <CardContent>
        <form className="grid gap-5 sm:grid-cols-2" onSubmit={handleSave} noValidate>
          {banner && (
            <div className="sm:col-span-2">
              <AlertBanner variant={banner.variant}>{banner.text}</AlertBanner>
            </div>
          )}

          <div className="sm:col-span-2">
            <AuthField
              label={t('profile.clientNumber')}
              htmlFor="profile-client-number"
            >
              <div className="client-number" data-testid="client-number">
                <span className="client-number__label">{t('profile.clientNumber')}</span>
                <span className="client-number__value">
                  {clientNumber ?? t('profile.clientNumberPlaceholder')}
                </span>
                {!clientNumber && (
                  <span className="client-number__note">{t('profile.clientNumberNote')}</span>
                )}
              </div>
            </AuthField>
          </div>

          <div className="sm:col-span-2 grid gap-1">
            <AuthField label={t('profile.email')} htmlFor="profile-email">
              <Input id="profile-email" type="email" value={profile?.email ?? ''} readOnly disabled />
            </AuthField>
            <AuthField label={t('profile.mobile')} htmlFor="profile-mobile">
              <Input id="profile-mobile" type="tel" value={profile?.mobile_number ?? ''} readOnly disabled />
            </AuthField>
          </div>

          <AuthField
            label={t('profile.fullName')}
            htmlFor="profile-full-name"
            error={errors.fullName}
            required
          >
            <Input
              id="profile-full-name"
              name="fullName"
              autoComplete="name"
              value={fullName}
              aria-invalid={Boolean(errors.fullName)}
              className={errors.fullName ? 'border-destructive' : undefined}
              onChange={(e) => setFullName(e.target.value)}
            />
          </AuthField>

          <AuthField
            label={t('profile.dob')}
            htmlFor="profile-dob"
            error={errors.dob}
          >
            <Input
              id="profile-dob"
              type="date"
              max={today}
              value={dob}
              aria-invalid={Boolean(errors.dob)}
              onChange={(e) => setDob(e.target.value)}
            />
          </AuthField>

          <AuthField label={t('profile.gender')} htmlFor="profile-gender">
            <Select value={gender} onValueChange={setGender}>
              <SelectTrigger id="profile-gender" className="w-full" aria-label={t('profile.gender')}>
                <SelectValue placeholder={t('profile.selectGender')} />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value=""></SelectItem>
                <SelectItem value="female">{t(GENDER_LABEL_KEYS.female)}</SelectItem>
                <SelectItem value="male">{t(GENDER_LABEL_KEYS.male)}</SelectItem>
                <SelectItem value="unspecified">{t(GENDER_LABEL_KEYS.unspecified)}</SelectItem>
              </SelectContent>
            </Select>
          </AuthField>

          <AuthField
            label={t('profile.preferredLanguage')}
            htmlFor="profile-language"
          >
            <Select value={languageDraft} onValueChange={(v) => setLanguageDraft(v as 'en' | 'ar')}>
              <SelectTrigger id="profile-language" className="w-full" aria-label={t('profile.preferredLanguage')}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="en">English</SelectItem>
                <SelectItem value="ar">العربية</SelectItem>
              </SelectContent>
            </Select>
          </AuthField>

          <div className="sm:col-span-2 flex justify-end">
            <Button type="submit" loading={saving}>
              {t('profile.save')}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )
}

/* ---------------------------------------------------------------------------
 * Consent preferences (append-only records, T8)
 * ------------------------------------------------------------------------- */

function ConsentSection() {
  const { t } = useTranslation()

  const [rows, setRows] = useState<ConsentRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [persisting, setPersisting] = useState<ConsentType | null>(null)

  useEffect(() => {
    let cancelled = false
    async function load() {
      const result: ConsentListResult = await getConsentHistory()
      if (cancelled) return
      setLoading(false)
      if (result.success) {
        setRows(result.rows)
      } else {
        setError(result.error?.message ?? t('profile.consentFailed'))
      }
    }
    void load()
    return () => {
      cancelled = true
    }
  }, [t])

  const marketing = latestConsent(rows, 'marketing')
  const serviceRow = rows.find((r) => r.consent_type === 'terms_service')

  async function handleMarketingToggle(checked: boolean) {
    setPersisting('marketing')
    const result = await recordConsent('marketing', checked, 'profile')
    setPersisting(null)
    if (!result.success) {
      toast.error(t('profile.consentFailed'))
      return
    }
    setRows((prev) => [result.row!, ...prev])
    toast.success(checked ? t('profile.consentMarketingOn') : t('profile.consentMarketingOff'))
  }

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>{t('profile.consentTitle')}</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="spinner" aria-hidden="true" />
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-3">
        <div className="space-y-1.5">
          <CardTitle>{t('profile.consentTitle')}</CardTitle>
          <CardDescription>{t('profile.consentIntro')}</CardDescription>
        </div>
        <ConsentHistoryDialog rows={rows} />
      </CardHeader>
      <CardContent className="grid gap-4">
        {error && <AlertBanner variant="error">{error}</AlertBanner>}

        {/* Mandatory terms & privacy consent — locked by design */}
        <div className="flex items-start gap-3 rounded-lg border p-3">
          <ShieldCheck className="mt-0.5 size-5 shrink-0 text-success" aria-hidden="true" />
          <div className="grid gap-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm font-medium">{t('profile.consentService')}</span>
              <Badge variant="success">{t('profile.historyGranted')}</Badge>
            </div>
            {serviceRow ? (
              <p className="text-xs text-muted-foreground">
                {t('profile.consentServiceMeta', {
                  version: serviceRow.version,
                  date: formatDateTime(serviceRow.created_at, 'en'),
                })}
              </p>
            ) : (
              <p className="text-xs text-muted-foreground">{t('profile.consentServiceNotice')}</p>
            )}
          </div>
        </div>

        {/* Marketing consent — opt in / withdraw anytime */}
        <div className="grid gap-2 rounded-lg border p-3">
          <div className="flex items-center justify-between gap-3">
            <label
              htmlFor="consent-marketing"
              className="grid cursor-pointer gap-1"
            >
              <span className="text-sm font-medium">{t('profile.consentMarketing')}</span>
              <span className="text-xs text-muted-foreground">
                {marketing === undefined
                  ? t('profile.consentMarketingNotSet')
                  : marketing
                    ? t('profile.consentMarketingOn')
                    : t('profile.consentMarketingOff')}
              </span>
            </label>
            <Checkbox
              id="consent-marketing"
              checked={marketing ?? false}
              disabled={persisting !== null}
              onCheckedChange={(v) => void handleMarketingToggle(Boolean(v))}
              aria-label={t('profile.allowMarketing')}
            />
          </div>
          <p className="text-xs text-muted-foreground">{t('profile.marketingHint')}</p>
        </div>
      </CardContent>
    </Card>
  )
}

function ConsentHistoryDialog({ rows }: { rows: ConsentRow[] }) {
  const { t } = useTranslation()

  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <History aria-hidden="true" />
          {t('profile.viewHistory')}
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('profile.historyTitle')}</DialogTitle>
          <DialogDescription>{t('profile.consentIntro')}</DialogDescription>
        </DialogHeader>
        {rows.length === 0 ? (
          <p className="flex items-center gap-2 py-4 text-sm text-muted-foreground">
            <History className="size-4" aria-hidden="true" />
            {t('profile.historyEmpty')}
          </p>
        ) : (
          <ul className="max-h-[50svh] divide-y overflow-y-auto" data-testid="consent-history">
            {rows.map((row) => (
              <li key={row.id} className="flex items-center justify-between gap-3 py-2.5">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">
                    {consentTopicLabel(row.consent_type, t)}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    {t('profile.consentServiceMeta', {
                      version: row.version,
                      date: formatDateTime(row.created_at, 'en'),
                    })}
                    {row.source ? ` · ${row.source}` : ''}
                  </p>
                </div>
                <Badge variant={row.granted ? 'success' : 'destructive'}>
                  {row.granted ? t('profile.historyGranted') : t('profile.historyWithdrawn')}
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  )
}

/* ---------------------------------------------------------------------------
 * Your data
 * ------------------------------------------------------------------------- */

function DataSection() {
  const { t } = useTranslation()

  const [requesting, setRequesting] = useState(false)
  const [sent, setSent] = useState<string | null>(null)
  const [failed, setFailed] = useState<string | null>(null)

  async function handleRequest() {
    setRequesting(true)
    setFailed(null)
    const result = await requestDataExport('requested from web profile')
    setRequesting(false)
    if (!result.success) {
      setFailed(t('profile.requestDataFailed'))
      return
    }
    setSent(result.row ? formatDateTime(result.row.requested_at, 'en') : t('profile.requestDataSent'))
    toast.success(t('profile.requestDataSent'))
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('profile.dataTitle')}</CardTitle>
        <CardDescription>{t('profile.dataIntro')}</CardDescription>
      </CardHeader>
      <CardContent className="grid gap-4">
        {sent && <AlertBanner variant="success">{t('profile.requestDataSent')}</AlertBanner>}
        {failed && <AlertBanner variant="error">{failed}</AlertBanner>}

        <Button variant="outline" className="w-full sm:w-auto" onClick={() => void handleRequest()} disabled={requesting}>
          <Download aria-hidden="true" />
          {t('profile.requestData')}
        </Button>

        <div className="flex items-start gap-3 rounded-lg border bg-muted/40 p-3">
          <CalendarDays className="mt-0.5 size-5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <div className="grid gap-1">
            <p className="text-sm font-medium">{t('profile.nutritionNoticeTitle')}</p>
            <p className="text-xs text-muted-foreground">{t('profile.nutritionNoticeBody')}</p>
          </div>
        </div>

        <p className="text-xs text-muted-foreground">{t('profile.dataPrivacyNote')}</p>
      </CardContent>
    </Card>
  )
}

/* ---------------------------------------------------------------------------
 * Password change (T8)
 * ------------------------------------------------------------------------- */

function PasswordSection() {
  const { t } = useTranslation()

  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [errors, setErrors] = useState<{
    currentPassword?: string
    newPassword?: string
    confirmPassword?: string
  }>({})
  const [submitting, setSubmitting] = useState(false)
  const [banner, setBanner] = useState<{ variant: 'success' | 'error'; text: string } | null>(null)

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setBanner(null)

    const validation = validatePasswordChange({
      currentPassword,
      newPassword,
      confirmPassword,
    })
    setErrors(validation.errors)
    if (!validation.valid) return

    setSubmitting(true)
    const result = await changePassword(currentPassword, newPassword)
    setSubmitting(false)

    if (!result.success) {
      setBanner({
        variant: 'error',
        text: result.error
          ? localizedApiErrorMessage(t, 'profile', result.error)
          : t('profile.passwordChangeFailed'),
      })
      return
    }

    setCurrentPassword('')
    setNewPassword('')
    setConfirmPassword('')
    setErrors({})
    setBanner({ variant: 'success', text: t('profile.passwordChanged') })
    toast.success(t('profile.passwordChanged'))
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('profile.passwordTitle')}</CardTitle>
        <CardDescription>{t('profile.passwordIntro')}</CardDescription>
      </CardHeader>
      <CardContent>
        <form className="grid gap-4" onSubmit={handleSubmit} noValidate>
          {banner && <AlertBanner variant={banner.variant}>{banner.text}</AlertBanner>}

          <PasswordInput
            id="profile-password-current"
            label={t('profile.currentPassword')}
            name="currentPassword"
            value={currentPassword}
            onChange={setCurrentPassword}
            placeholder={t('profile.currentPasswordPlaceholder')}
            error={errors.currentPassword}
            autoComplete="current-password"
          />

          <PasswordInput
            id="profile-password-new"
            label={t('profile.newPassword')}
            name="newPassword"
            value={newPassword}
            onChange={setNewPassword}
            placeholder={t('profile.newPasswordPlaceholder')}
            error={errors.newPassword}
            hint={t('profile.passwordHint')}
            autoComplete="new-password"
          />

          <PasswordInput
            id="profile-password-confirm"
            label={t('profile.confirmPassword')}
            name="confirmPassword"
            value={confirmPassword}
            onChange={setConfirmPassword}
            placeholder={t('profile.confirmPasswordPlaceholder')}
            error={errors.confirmPassword}
            autoComplete="new-password"
          />

          <div className="flex justify-end">
            <Button type="submit" loading={submitting}>
              {t('profile.changePassword')}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  )
}