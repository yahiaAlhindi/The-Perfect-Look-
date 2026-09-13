import type { ReactNode } from 'react'

import { cn } from '@/lib/utils'

interface PageHeaderProps {
  title: string
  description?: string
  /**
   * Breadcrumb / eyebrow line rendered above the title (e.g. "Admin · Services").
   */
  eyebrow?: string
  /** Primary actions rendered stacked to the end (start on RTL). */
  actions?: ReactNode
  className?: string
}

/**
 * Consistent page heading used by every screen (patient & admin).
 * Stacks vertically on narrow phones, row layout at the md breakpoint.
 */
function PageHeader({
  title,
  description,
  eyebrow,
  actions,
  className,
}: PageHeaderProps) {
  return (
    <header
      data-slot="page-header"
      className={cn(
        'flex flex-col gap-4 md:flex-row md:items-end md:justify-between',
        className,
      )}
    >
      <div className="min-w-0 space-y-1.5">
        {eyebrow && (
          <p className="text-xs font-medium tracking-wide text-muted-foreground uppercase">
            {eyebrow}
          </p>
        )}
        <h1 className="text-2xl font-bold tracking-tight md:text-3xl">{title}</h1>
        {description && (
          <p className="max-w-2xl text-sm text-muted-foreground md:text-base">{description}</p>
        )}
      </div>
      {actions && (
        <div className="flex flex-wrap items-center gap-2 md:shrink-0">{actions}</div>
      )}
    </header>
  )
}

export type { PageHeaderProps }
export { PageHeader }