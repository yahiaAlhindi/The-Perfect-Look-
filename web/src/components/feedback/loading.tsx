import type { ReactNode } from 'react'

import { Spinner } from '@/components/ui/spinner'

/**
 * Full-viewport loading veil (min-h-svh = stable on mobile browsers for PWA).
 */
function PageLoader({
  label = 'Loading…',
}: {
  label?: string
}) {
  return (
    <div
      data-slot="page-loader"
      className="flex min-h-svh w-full flex-col items-center justify-center gap-3 py-16"
      role="status"
      aria-live="polite"
    >
      <Spinner size="lg" label={label} />
      <p className="text-sm text-muted-foreground">{label}</p>
    </div>
  )
}

/** Inline block loader for partial regions. */
function InlineLoader({
  label = 'Loading…',
  children,
}: {
  label?: string
  children?: ReactNode
}) {
  return (
    <div
      data-slot="inline-loader"
      className="flex flex-col items-center justify-center gap-3 rounded-xl border border-dashed py-12"
      role="status"
      aria-live="polite"
    >
      <Spinner label={label} />
      <p className="text-sm text-muted-foreground">{label}</p>
      {children}
    </div>
  )
}

export { InlineLoader, PageLoader }