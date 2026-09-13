/**
 * AlertBanner (T6). Success / error feedback used across the auth pages.
 */

import type { ReactNode } from 'react'

export type AlertVariant = 'success' | 'error' | 'info'

export default function AlertBanner({
  variant,
  children,
}: {
  variant: AlertVariant
  children: ReactNode
}) {
  return (
    <div className={`alert-banner alert-banner--${variant}`} role={variant === 'error' ? 'alert' : 'status'}>
      {children}
    </div>
  )
}