/**
 * LanguageSwitcher (T6). Segmented EN / العربية toggle.
 * Persists the guest's choice locally (profile sync handled by AuthProvider).
 */

import { useTranslation } from 'react-i18next'
import { useAuth } from '../../context/AuthContext'
import type { AppLanguage } from '../../i18n'

export default function LanguageSwitcher({
  ariaLabel,
}: {
  ariaLabel?: string
}) {
  const { t } = useTranslation()
  const { language, setLanguage } = useAuth()

  return (
    <div
      className="lang-switch"
      role="group"
      aria-label={ariaLabel ?? t('auth.languageLabel')}
    >
      {(['en', 'ar'] as const).map((lang) => {
        const active = language === lang
        return (
          <button
            key={lang}
            type="button"
            className={`lang-switch__option${active ? ' is-active' : ''}`}
            aria-pressed={active}
            onClick={() => setLanguage(lang)}
          >
            {lang === 'en' ? 'English' : 'العربية'}
          </button>
        )
      })}
    </div>
  )
}

export type { AppLanguage }