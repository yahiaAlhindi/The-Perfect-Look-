/**
 * AuthField (T6). Label + control + inline hint/error in one row.
 * RTL-aware; compact enough to fit an 320px viewport.
 */

import type { ReactNode } from 'react'

export interface AuthFieldProps {
  label: string
  htmlFor: string
  error?: string | null
  hint?: string | null
  required?: boolean
  children: ReactNode
}

export default function AuthField({
  label,
  htmlFor,
  error,
  hint,
  required,
  children,
}: AuthFieldProps) {
  return (
    <div
      className={`auth-field${error ? ' has-error' : ''}`}
    >
      <label className="auth-field__label" htmlFor={htmlFor}>
        {label}
        {required && <span aria-hidden="true"> *</span>}
      </label>
      {children}
      {error ? (
        <p className="auth-field__error" role="alert">
          {error}
        </p>
      ) : hint ? (
        <p className="auth-field__hint">{hint}</p>
      ) : null}
    </div>
  )
}