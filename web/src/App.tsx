/**
 * The Perfect Look — availability picker demo host (T13).
 *
 * Wires the picker to real data:
 *   1. loads services from the API (T9),
 *   2. renders the branch -> provider -> date -> slot picker (T13),
 *   3. shows the resulting booking summary (branch + provider +
 *      date/time) proving the selection is carried into booking.
 *
 * This is a demo page until T15 builds the full booking wizard on
 * top of the same picker component.
 */

import { useEffect, useMemo, useState } from 'react'
import AvailabilityPicker, { type BookingSelection } from './components/AvailabilityPicker'
import { listServices } from './lib/supabase/services'
import type { PublicService } from './lib/supabase/types'
import { isRtl, loadLang, makeTranslator, saveLang, type Lang } from './i18n'

const BRANCH_TZ = 'Asia/Dubai'

function timeRange(startIso: string, endIso: string, lang: Lang): string {
  const locale = lang === 'ar' ? 'ar-AE' : 'en-GB'
  const fmt: Intl.DateTimeFormatOptions = {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRANCH_TZ,
  }
  const start = new Intl.DateTimeFormat(locale, fmt).format(new Date(startIso))
  const end = new Intl.DateTimeFormat(locale, fmt).format(new Date(endIso))
  return `${start} – ${end}`
}

export default function App() {
  const [language, setLanguage] = useState<Lang>(() => loadLang())
  const [services, setServices] = useState<PublicService[]>([])
  const [serviceId, setServiceId] = useState<string | null>(null)
  const [servicesError, setServicesError] = useState<string | null>(null)
  const [selection, setSelection] = useState<BookingSelection | null>(null)

  const t = useMemo(() => makeTranslator(language), [language])

  useEffect(() => {
    document.documentElement.lang = language
    document.documentElement.dir = isRtl(language) ? 'rtl' : 'ltr'
  }, [language])

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const { services: data, error } = await listServices()
      if (cancelled) return
      setServices(data)
      setServicesError(error?.message ?? null)
      if (data.length > 0) {
        setServiceId((prev) => prev ?? data[0].id)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  const toggleLanguage = () => {
    const next: Lang = language === 'en' ? 'ar' : 'en'
    setLanguage(next)
    saveLang(next)
  }

  const selectedService =
    services.find((s) => s.id === serviceId) ?? null

  const timeLabel = selection
    ? timeRange(selection.slotStart, selection.slotEnd, language)
    : null

  return (
    <main className="app-shell">
      <header className="app-header">
        <div>
          <h1>{t('app.name')}</h1>
          <p className="app-tagline">{t('app.tagline')}</p>
        </div>
        <button
          type="button"
          className="lang-toggle"
          onClick={toggleLanguage}
          aria-label={t('lang.toggleAria')}
        >
          {t('lang.toggle')}
        </button>
      </header>

      <section className="booking-step" aria-label={t('service.label')}>
        <label className="service-label" htmlFor="service-select">
          {t('service.label')}
        </label>
        <select
          id="service-select"
          className="service-select"
          value={serviceId ?? ''}
          onChange={(event) => {
            setServiceId(event.target.value || null)
            setSelection(null)
          }}
        >
          {services.length === 0 && (
            <option value="">{t('service.default')}</option>
          )}
          {services.map((service) => (
            <option key={service.id} value={service.id}>
              {service.name} · {service.duration_minutes} min
            </option>
          ))}
        </select>
        {servicesError && <p className="app-hint">{t('error.load')}</p>}
      </section>

      <AvailabilityPicker
        serviceId={serviceId}
        serviceDuration={selectedService?.duration_minutes ?? null}
        language={language}
        onSelect={setSelection}
      />

      <section className="summary-card" aria-label={t('summary.title')}>
        <h2>{t('summary.title')}</h2>
        {selection ? (
          <dl className="summary-list">
            <div>
              <dt>{t('summary.branch')}</dt>
              <dd>{selection.branch.name}</dd>
            </div>
            <div>
              <dt>{t('summary.provider')}</dt>
              <dd>
                {selection.provider
                  ? selection.provider.full_name
                  : selection.providerNames.join(language === 'ar' ? '، ' : ', ')}
                {!selection.provider && selection.providerNames.length === 0
                  ? t('summary.providerAny')
                  : ''}
              </dd>
            </div>
            <div>
              <dt>{t('summary.date')}</dt>
              <dd>
                {new Intl.DateTimeFormat(language === 'ar' ? 'ar-AE' : 'en-GB', {
                  weekday: 'long',
                  day: 'numeric',
                  month: 'long',
                  year: 'numeric',
                  timeZone: 'UTC',
                }).format(new Date(`${selection.bookingDate}T00:00:00Z`))}
              </dd>
            </div>
            <div>
              <dt>{t('summary.time')}</dt>
              <dd>{timeLabel}</dd>
            </div>
            {selectedService && (
              <div>
                <dt>{t('summary.duration')}</dt>
                <dd>{selectedService.duration_minutes} min</dd>
              </div>
            )}
          </dl>
        ) : (
          <p className="app-hint">{t('empty.selection')}</p>
        )}
      </section>
    </main>
  )
}