import { toast, Toaster as Sonner, type ToasterProps as SonnerProps } from 'sonner'

import { cn } from '@/lib/utils'

function Toaster({ className, ...props }: SonnerProps) {
  return (
    <Sonner
      theme="system"
      position="top-center"
      richColors
      expand
      closeButton
      className={cn('toaster group', className)}
      toastOptions={{
        classNames: {
          toast:
            'group toast group-[.toaster]:bg-card group-[.toaster]:text-card-foreground group-[.toaster]:border-border group-[.toaster]:shadow-lg group-[.toaster]:rounded-lg',
          description: 'group-[.toast]:text-muted-foreground',
          actionButton: 'group-[.toast]:bg-primary group-[.toast]:text-primary-foreground',
          cancelButton: 'group-[.toast]:bg-secondary group-[.toast]:text-secondary-foreground',
          closeButton:
            'group-[.toast]:bg-card group-[.toast]:text-muted-foreground group-[.toast]:border-border',
        },
      }}
      {...props}
    />
  )
}

export { Toaster, toast }