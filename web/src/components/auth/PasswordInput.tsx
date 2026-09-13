/**
 * PasswordInput (T6). Password field with a show/hide toggle so mobile
 * users can review their input before submitting.
 */

import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import AuthField from './AuthField'

export interface PasswordInputProps {
  id: string
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string
  error?: string | null
  hint?: string | null
  autoComplete?: string
  name?: string
}

export default function PasswordInput({
  id,
  label,
  value,
  onChange,
  placeholder,
  error,
  hint,
  autoComplete,
  name,
}: PasswordInputProps) {
  const { t } = useTranslation()
  const [visible, setVisible] = useState(false)

  return (
    <AuthField label={label} htmlFor={id} error={error} hint={hint} required>
      <div className="auth-input-group">
        <input
          id={id}
          name={name ?? id}
          type={visible ? 'text' : 'password'}
          className="auth-input"
          value={value}
          placeholder={placeholder}
          autoComplete={autoComplete}
          aria-invalid={Boolean(error)}
          onChange={(e) => onChange(e.target.value)}
        />
        <button
          type="button"
          className="auth-input-group__toggle"
          aria-pressed={visible}
          onClick={() => setVisible((v) => !v)}
        >
          {visible ? t('auth.login.hidePassword') : t('auth.login.showPassword')}
        </button>
      </div>
    </AuthField>
  )
}