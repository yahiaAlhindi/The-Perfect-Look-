import type { LucideIcon } from 'lucide-react'
import { TriangleAlert } from 'lucide-react'
import type { ComponentProps, ReactNode } from 'react'

import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'

interface ErrorStateProps extends ComponentProps<'div'> {
  icon?: LucideIcon
  title?: string
  /** Human-readable message (e.g. from Supabase MappedError). */
  message?: string
  /** Optional retry callback rendered as a button. */
  onRetry?: () => void
  /** Extra actions (e.g. "contact support") rendered next to retry. */
  action?: ReactNode
}

function ErrorState({
  className,
  icon: Icon = TriangleAlert,
  title = 'Something went wrong',
  message,
  onRetry,
  action,
  ...props
}: ErrorStateProps) {
  return (
    <div
      data-slot="error-state"
      className={cn(
        'flex flex-col items-center justify-center gap-2 rounded-xl border border-dashed px-6 py-14 text-center',
        className,
      )}
      {...props}
    >
      <div className="flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
        <Icon aria-hidden="true" />
      </div>
      <h3 className="mt-2 text-base font-semibold">{title}</h3>
      {message && <p className="max-w-sm text-sm text-muted-foreground">{message}</p>}
      {(onRetry || action) && (
        <div className="mt-3 flex flex-wrap items-center justify-center gap-2">
          {onRetry && <Button onClick={onRetry}>Try again</Button>}
          {action}
        </div>
      )}
    </div>
  )
}

export { ErrorState }