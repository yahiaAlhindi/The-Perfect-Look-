/**
 * AuthLayout (T6). Shared shell for every auth screen: centered card,
 * app wordmark and a language switcher. Mobile-first, no external deps.
 */

import type { ReactNode } from 'react'
import { useTranslation } from 'react-i18next'
import LanguageSwitcher from './LanguageSwitcher'

export default function AuthLayout({
  children,
}: {
  children: ReactNode
}) {
  const { t } = useTranslation()

  return (
    <div className="auth-shell">
      <header className="auth-shell__header">
        <span className="auth-shell__brand">{t('common.appName')}</span>
        <LanguageSwitcher />
      </header>

      <main className="auth-shell__card">{children}</main>

      <footer className="auth-shell__footer">
        © {new Date().getFullYear()} {t('common.appName')}
      </footer>
    </div>
  )
}