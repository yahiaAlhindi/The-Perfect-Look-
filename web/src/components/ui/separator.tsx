import type { ComponentProps } from 'react'

import { cn } from '@/lib/utils'

function Separator({
  className,
  orientation = 'horizontal',
  decorative = true,
  ...props
}: ComponentProps<'div'> & { orientation?: 'horizontal' | 'vertical'; decorative?: boolean }) {
  const horizontal = orientation === 'horizontal'
  return (
    <div
      role={decorative ? 'none' : 'separator'}
      aria-orientation={decorative ? undefined : orientation}
      data-slot="separator"
      className={cn(
        'bg-border shrink-0',
        horizontal ? 'h-px w-full' : 'h-full w-px',
        className,
      )}
      {...props}
    />
  )
}

export { Separator }