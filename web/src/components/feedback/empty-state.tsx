import type { LucideIcon } from 'lucide-react'
import { CircleAlert } from 'lucide-react'
import type { ComponentProps, ReactNode } from 'react'

import { cn } from '@/lib/utils'

interface EmptyStateProps extends ComponentProps<'div'> {
  /** Icon rendered inside the soft brand circle. */
  icon?: LucideIcon
  title: string
  description?: string
  /** Optional primary/secondary action buttons rendered below the copy. */
  action?: ReactNode
}

/**
 * Full-width friendly empty/`no results` placeholder used by lists and
 * dashboards. RTL-safe and centred on small phones.
 */
function EmptyState({
  className,
  icon: Icon = CircleAlert,
  title,
  description,
  action,
  ...props
}: EmptyStateProps) {
  return (
    <div
      data-slot="empty-state"
      className={cn(
        'flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed px-6 py-14 text-center',
        className,
      )}
      {...props}
    >
      <div className="flex size-12 items-center justify-center rounded-full bg-brand-soft text-brand">
        <Icon aria-hidden="true" />
      </div>
      <h3 className="mt-2 text-base font-semibold">{title}</h3>
      {description && (
        <p className="max-w-sm text-sm text-muted-foreground">{description}</p>
      )}
      {action && <div className="mt-3 flex flex-wrap items-center justify-center gap-2">{action}</div>}
    </div>
  )
}

export { EmptyState }