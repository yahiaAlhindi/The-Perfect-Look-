/**
 * Availability picker (T13).
 *
 * Flow: branch -> provider (optional) -> date/time slot.
 *
 *  - Branch list comes from `branches` (public RLS, active only).
 *  - Providers come from the T12 `get_branch_providers` RPC.
 *  - Slots come exclusively from the T12 `get_availability` engine —
 *    the UI never fabricates availability; it renders the engine's
 *    slots against the branch calendar and marks the rest clearly
 *    (past / closed / no slots / few left).
 *  - Day/week navigation is mobile-friendly (a swipe-free horizontal
 *    week strip with previous/next + jump-to-today) and RTL-ready.
 *
 * The chosen branch, provider, and slot are passed to `onSelect` so
 * the parent (booking flow, T15) can carry them into the booking.
 */

import { useCallback, useEffect, useMemo, useState } from 'react'
import type {
  AvailabilitySlot,
  Branch,
  ProviderSummary,
} from '../lib/supabase/types'
import {
  getAvailability,
  listBranches,
  listBranchHours,
  listBranchProviders,
  listClosedDates,
} from '../lib/supabase/availability'
import { makeTranslator, type Lang } from '../i18n'
import './AvailabilityPicker.css'

const BRANCH_TZ = 'Asia/Dubai'

export interface BookingSelection {
  branch: Branch
  /** null when the caller left the provider open ("any provider"). */
  provider: ProviderSummary | null
  providerNames: string[]
  bookingDate: string
  slotStart: string
  slotEnd: string
}

/**
 * A single renderable time group: one slot_start with its free
 * provider(s) — the engine returns one row per (slot, provider);
 * the picker collapses rows sharing a start into one button.
 */
interface SlotGroup {
  slotStart: string
  slotEnd: string
  providers: { id: string; name: string }[]
}

interface AvailabilityPickerProps {
  /** Service whose duration/buffer sizes the slots (T12 engine). */
  serviceId: string | null
  /** Optional display hint for the slot/summary (service duration). */
  serviceDuration?: number | null
  language: Lang
  onSelect?: (selection: BookingSelection) => void
}

type DayState = 'past' | 'closed' | 'unavailable' | 'limited' | 'available'

// ── date helpers (branch-calendar strings, UTC math) ──────────

function addDays(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number)
  const date = new Date(Date.UTC(y, m - 1, d))
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString().slice(0, 10)
}

function parseUtc(dateStr: string): Date {
  const [y, m, d] = dateStr.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d))
}

function todayInTz(): string {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BRANCH_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date())
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? ''
  return `${get('year')}-${get('month')}-${get('day')}`
}

function mondayOfWeek(dateStr: string): string {
  const dow = parseUtc(dateStr).getUTCDay() // 0 = Sun … 6 = Sat
  const offset = dow === 0 ? -6 : 1 - dow
  return addDays(dateStr, offset)
}

interface DayLabel {
  weekday: string
  day: number
  month: string
}

function dayLabel(dateStr: string, lang: Lang, style: 'short' | 'long'): DayLabel {
  const locale = lang === 'ar' ? 'ar-AE' : 'en-GB'
  const parts = new Intl.DateTimeFormat(locale, {
    weekday: style,
    day: 'numeric',
    month: style === 'long' ? 'long' : 'short',
    timeZone: 'UTC',
  }).formatToParts(parseUtc(dateStr))
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? ''
  return {
    weekday: get('weekday'),
    day: Number(get('day')),
    month: get('month'),
  }
}

function fullDateLabel(dateStr: string, lang: Lang): string {
  const locale = lang === 'ar' ? 'ar-AE' : 'en-GB'
  return new Intl.DateTimeFormat(locale, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(parseUtc(dateStr))
}

function slotTimeLabel(iso: string, lang: Lang): string {
  const locale = lang === 'ar' ? 'ar-AE' : 'en-GB'
  return new Intl.DateTimeFormat(locale, {
    hour: '2-digit',
    minute: '2-digit',
    hour12: lang === 'ar',
    timeZone: BRANCH_TZ,
  }).format(new Date(iso))
}

// ── component ─────────────────────────────────────────────────

export default function AvailabilityPicker({
  serviceId,
  serviceDuration,
  language,
  onSelect,
}: AvailabilityPickerProps) {
  const t = useMemo(() => makeTranslator(language), [language])
  const today = useMemo(() => todayInTz(), [])
  const currentWeek = useMemo(() => mondayOfWeek(today), [today])

  // branches
  const [branches, setBranches] = useState<Branch[]>([])
  const [branchesLoading, setBranchesLoading] = useState(true)
  const [branchesError, setBranchesError] = useState<string | null>(null)

  // providers + calendar metadata
  const [providers, setProviders] = useState<ProviderSummary[]>([])
  const [providersLoading, setProvidersLoading] = useState(false)
  const [openDays, setOpenDays] = useState<Set<number>>(new Set())
  const [closures, setClosures] = useState<Set<string>>(new Set())
  const [holidaySet, setHolidaySet] = useState<Set<string>>(new Set())

  // selection state
  const [selectedBranchId, setSelectedBranchId] = useState<string | null>(null)
  const [providerFilter, setProviderFilter] = useState<string | null>(null)
  const [weekStart, setWeekStart] = useState<string>(currentWeek)
  const [selectedDate, setSelectedDate] = useState<string | null>(null)

  // availability fetch state
  const [slots, setSlots] = useState<AvailabilitySlot[]>([])
  const [slotsLoading, setSlotsLoading] = useState(false)
  const [slotsError, setSlotsError] = useState<string | null>(null)
  const [reloadKey, setReloadKey] = useState(0)

  const weekDates = useMemo(() => {
    const days: string[] = []
    for (let i = 0; i < 7; i++) days.push(addDays(weekStart, i))
    return days
  }, [weekStart])

  const slotGroups = useMemo(() => {
    const byDate: Record<string, SlotGroup[]> = {}
    for (const slot of slots) {
      const key = slot.slot_date
      const groups = (byDate[key] ??= [])
      let group = groups.find((g) => g.slotStart === slot.slot_start)
      if (!group) {
        group = { slotStart: slot.slot_start, slotEnd: slot.slot_end, providers: [] }
        groups.push(group)
      }
      group.providers.push({ id: slot.provider_id, name: slot.provider_name })
    }
    for (const key of Object.keys(byDate)) {
      byDate[key].sort((a, b) => a.slotStart.localeCompare(b.slotStart))
    }
    return byDate
  }, [slots])

  const selectedBranch = useMemo(
    () => branches.find((b) => b.id === selectedBranchId) ?? null,
    [branches, selectedBranchId],
  )

  // ── data loading ─────────────────────────────────────────────

  const loadBranches = useCallback(async () => {
    setBranchesLoading(true)
    setBranchesError(null)
    const { branches: result, error } = await listBranches()
    setBranches(result)
    setBranchesError(error?.message ?? null)
    setBranchesLoading(false)
  }, [])

  useEffect(() => {
    void loadBranches()
  }, [loadBranches])

  // Default to the first branch so the picker is never empty.
  useEffect(() => {
    if (!selectedBranchId && branches.length > 0) {
      setSelectedBranchId(branches[0].id)
      setWeekStart(currentWeek)
    }
  }, [branches, selectedBranchId, currentWeek])

  useEffect(() => {
    if (!selectedBranchId) return
    let cancelled = false

    void (async () => {
      setProvidersLoading(true)
      const [{ providers: p }, { hours }] = await Promise.all([
        listBranchProviders(selectedBranchId),
        listBranchHours(selectedBranchId),
      ])
      if (cancelled) return
      setProviders(p)
      setOpenDays(new Set(hours.map((h) => h.day_of_week)))
      setProvidersLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [selectedBranchId])

  useEffect(() => {
    if (!selectedBranchId) {
      setSlots([])
      return
    }
    if (!serviceId) {
      setSlots([])
      return
    }

    let cancelled = false
    setSlotsLoading(true)
    setSlotsError(null)

    void (async () => {
      const [avail, closed] = await Promise.all([
        getAvailability({
          branchId: selectedBranchId,
          serviceId,
          from: weekDates[0],
          to: weekDates[6],
          staffId: providerFilter,
        }),
        listClosedDates(selectedBranchId, weekDates[0], weekDates[6]),
      ])
      if (cancelled) return
      setSlots(avail.slots)
      setClosures(new Set(closed.closures.map((c) => c.date)))
      setHolidaySet(new Set(closed.holidays.map((h) => h.date)))
      const error =
        avail.error ?? closed.error
      setSlotsError(error?.message ?? null)
      setSlotsLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [selectedBranchId, serviceId, providerFilter, weekStart, weekDates, reloadKey])

  // ── state classification ─────────────────────────────────────

  const dayState = useCallback(
    (dateStr: string): DayState => {
      if (dateStr < today) return 'past'
      if (closures.has(dateStr) || holidaySet.has(dateStr)) return 'closed'
      const dow = parseUtc(dateStr).getUTCDay() // 0 = Sun … 6 = Sat
      if (!openDays.has(dow)) return 'closed'
      const count = slotGroups[dateStr]?.length ?? 0
      if (count === 0) return 'unavailable'
      return count <= 2 ? 'limited' : 'available'
    },
    [today, closures, holidaySet, openDays, slotGroups],
  )

  // ── interactions ─────────────────────────────────────────────

  const handleBranchSelect = (id: string) => {
    setSelectedBranchId(id)
    setProviderFilter(null)
    setSelectedDate(null)
    setWeekStart(currentWeek)
  }

  const navigateWeek = (offset: number) => {
    setSelectedDate(null)
    setWeekStart(addDays(weekStart, offset))
  }

  const jumpToToday = () => {
    setSelectedDate(null)
    setWeekStart(currentWeek)
  }

  const handleSlot = (group: SlotGroup) => {
    if (!selectedBranch) return
    const provider =
      providerFilter !== null
        ? providers.find((p) => p.id === providerFilter) ?? null
        : null
    onSelect?.({
      branch: selectedBranch,
      provider,
      providerNames: group.providers.map((p) => p.name),
      bookingDate: selectedDate ?? group.slotStart.slice(0, 10),
      slotStart: group.slotStart,
      slotEnd: group.slotEnd,
    })
  }

  // ── render ───────────────────────────────────────────────────

  const selectedGroups = selectedDate ? (slotGroups[selectedDate] ?? []) : []
  const selectedState = selectedDate ? dayState(selectedDate) : 'closed'

  return (
    <div className="ap" dir={language === 'ar' ? 'rtl' : 'ltr'}>
      {/* Step 1 — branch */}
      <section className="ap-card" aria-labelledby="ap-branch-title">
        <h3 id="ap-branch-title" className="ap-card-title">
          <span className="ap-step">1</span>
          {t('step.branch')}
          <span className="ap-card-hint">{t('step.branchHint')}</span>
        </h3>

        {branchesLoading && <p className="ap-hint">{t('loading.branches')}</p>}
        {!branchesLoading && branchesError && (
          <div className="ap-error">
            <span>{t('error.load')}</span>
            <button type="button" className="ap-btn" onClick={() => void loadBranches()}>
              {t('error.retry')}
            </button>
          </div>
        )}
        {!branchesLoading && !branchesError && branches.length === 0 && (
          <p className="ap-hint">{t('error.nobranch')}</p>
        )}

        {branches.length > 0 && (
          <div className="ap-branches" role="radiogroup" aria-label={t('step.branch')}>
            {branches.map((branch) => {
              const active = branch.id === selectedBranchId
              return (
                <button
                  key={branch.id}
                  type="button"
                  role="radio"
                  aria-checked={active}
                  className={`ap-branch${active ? ' ap-is-active' : ''}`}
                  onClick={() => handleBranchSelect(branch.id)}
                >
                  <span className="ap-branch-name">{branch.name}</span>
                  <span className="ap-branch-city">{branch.city}</span>
                </button>
              )
            })}
          </div>
        )}

        {selectedBranch && (
          <div className="ap-branch-hours">
            <span>{selectedBranch.timezone}</span>
          </div>
        )}
      </section>

      {/* Step 2 — provider (optional) */}
      {selectedBranchId && (
        <section className="ap-card" aria-labelledby="ap-provider-title">
          <h3 id="ap-provider-title" className="ap-card-title">
            <span className="ap-step">2</span>
            {t('step.provider')}
            <span className="ap-card-hint">{t('step.providerHint')}</span>
          </h3>

          {providersLoading && <p className="ap-hint">{t('loading.providers')}</p>}

          {!providersLoading && (
            <div className="ap-providers" role="radiogroup" aria-label={t('step.provider')}>
              <button
                type="button"
                role="radio"
                aria-checked={providerFilter === null}
                className={`ap-provider${providerFilter === null ? ' ap-is-active' : ''}`}
                onClick={() => setProviderFilter(null)}
              >
                <span className="ap-provider-name">{t('provider.any')}</span>
              </button>
              {providers.map((provider) => {
                const active = provider.id === providerFilter
                return (
                  <button
                    key={provider.id}
                    type="button"
                    role="radio"
                    aria-checked={active}
                    className={`ap-provider${active ? ' ap-is-active' : ''}`}
                    onClick={() => {
                      setProviderFilter(provider.id)
                      setSelectedDate(null)
                    }}
                  >
                    <span className="ap-provider-name">{provider.full_name}</span>
                    <span className="ap-provider-title">{provider.title}</span>
                  </button>
                )
              })}
            </div>
          )}
        </section>
      )}

      {/* Step 3 — date & slot */}
      {selectedBranchId && (
        <section className="ap-card" aria-labelledby="ap-date-title">
          <h3 id="ap-date-title" className="ap-card-title">
            <span className="ap-step">3</span>
            {t('step.date')}
            <span className="ap-card-hint">{t('step.dateHint')}</span>
          </h3>

          {!serviceId && <p className="ap-hint">{t('service.default')}</p>}

          {serviceId && (
            <>
              <div className="ap-week" aria-label={t('step.date')}>
                <button
                  type="button"
                  className="ap-week-nav ap-week-prev"
                  aria-label={t('nav.prevWeek')}
                  onClick={() => navigateWeek(-7)}
                >
                  ‹
                </button>

                <div className="ap-week-days">
                  {weekDates.map((dateStr) => {
                    const state = dayState(dateStr)
                    const label = dayLabel(dateStr, language, 'short')
                    const active = dateStr === selectedDate
                    return (
                      <button
                        key={dateStr}
                        type="button"
                        className={`ap-day ap-day-${state}${active ? ' ap-is-active' : ''}`}
                        aria-pressed={active}
                        aria-label={`${label.weekday} ${label.day} ${label.month}`}
                        disabled={state === 'past'}
                        onClick={() => setSelectedDate(dateStr)}
                      >
                        <span className="ap-day-weekday">{label.weekday}</span>
                        <span className="ap-day-number">{label.day}</span>
                        <span className="ap-day-state">{t(`state.${state}`)}</span>
                      </button>
                    )
                  })}
                </div>

                <button
                  type="button"
                  className="ap-week-nav ap-week-next"
                  aria-label={t('nav.nextWeek')}
                  onClick={() => navigateWeek(7)}
                >
                  ›
                </button>
              </div>

              {weekStart !== currentWeek && (
                <button type="button" className="ap-btn ap-today" onClick={jumpToToday}>
                  {t('nav.today')}
                </button>
              )}

              {slotsLoading && <p className="ap-hint">{t('loading.slots')}</p>}

              {!slotsLoading && slotsError && (
                <div className="ap-error">
                  <span>{t('error.load')} ({t('error.noslots')})</span>
                  <button
                    type="button"
                    className="ap-btn"
                    onClick={() => setReloadKey((k) => k + 1)}
                  >
                    {t('error.retry')}
                  </button>
                </div>
              )}

              {!slotsLoading && !slotsError && (
                <div className="ap-slots" aria-live="polite">
                  {!selectedDate && <p className="ap-hint">{t('slot.selectDate')}</p>}

                  {selectedDate && (
                    <>
                      <h4 className="ap-slots-date">{fullDateLabel(selectedDate, language)}</h4>

                      {selectedState === 'closed' && (
                        <p className="ap-hint">{t('state.closed')} — {t('slot.empty')}</p>
                      )}

                      {selectedState !== 'closed' && selectedGroups.length === 0 && (
                        <p className="ap-hint">{t('slot.empty')}</p>
                      )}

                      {selectedGroups.length > 0 && (
                        <>
                          <p className="ap-slots-title">
                            {t('slot.choose')}
                            {serviceDuration ? ` · ${serviceDuration} min` : ''}
                          </p>
                          <div className="ap-slot-grid">
                            {selectedGroups.map((group) => (
                              <button
                                key={group.slotStart}
                                type="button"
                                className="ap-slot"
                                onClick={() => handleSlot(group)}
                              >
                                <span className="ap-slot-time">
                                  {slotTimeLabel(group.slotStart, language)}
                                </span>
                                <span className="ap-slot-providers">
                                  {group.providers
                                    .map((p) => p.name)
                                    .join(language === 'ar' ? '، ' : ', ')}
                                </span>
                              </button>
                            ))}
                          </div>
                        </>
                      )}
                    </>
                  )}
                </div>
              )}

              <div className="ap-legend">
                <span className="ap-legend-item">
                  <i className="ap-dot ap-dot-available" /> {t('state.available')}
                </span>
                <span className="ap-legend-item">
                  <i className="ap-dot ap-dot-limited" /> {t('state.limited')}
                </span>
                <span className="ap-legend-item">
                  <i className="ap-dot ap-dot-unavailable" /> {t('state.unavailable')}
                </span>
                <span className="ap-legend-item">
                  <i className="ap-dot ap-dot-closed" /> {t('state.closed')}
                </span>
              </div>
            </>
          )}
        </section>
      )}
    </div>
  )
}