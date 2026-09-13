import { Loader2 } from 'lucide-react'
import { cva, type VariantProps } from 'class-variance-authority'
import type { ComponentProps } from 'react'

import { cn } from '@/lib/utils'

const spinnerVariants = cva('animate-spin text-brand', {
  variants: {
    size: {
      xs: 'size-3.5',
      sm: 'size-4',
      default: 'size-6',
      lg: 'size-8',
      xl: 'size-12',
    },
  },
  defaultVariants: {
    size: 'default',
  },
})

function Spinner({
  className,
  size,
  label = 'Loading',
  ...props
}: ComponentProps<'svg'> & VariantProps<typeof spinnerVariants> & { label?: string }) {
  return (
    <Loader2
      data-slot="spinner"
      role="status"
      aria-label={label}
      className={cn(spinnerVariants({ size }), className)}
      {...props}
    />
  )
}

export { Spinner }