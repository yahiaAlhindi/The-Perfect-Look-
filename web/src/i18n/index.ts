/**
 * i18n setup (T6). English + Arabic with automatic RTL handling.
 * The language is persisted under `tpl-auth:lang` so a guest who picks
 * Arabic keeps it across the auth flow; a signed-in user's preference is
 * persisted to their profile by the AuthProvider (T7 will sync fully).
 */

import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import en from './locales/en'
import ar from './locales/ar'

export type AppLanguage = 'en' | 'ar'

export const LANG_STORAGE_KEY = 'tpl-auth:lang'

export function getStoredLanguage(): AppLanguage {
  try {
    const stored = window.localStorage.getItem(LANG_STORAGE_KEY)
    if (stored === 'en' || stored === 'ar') return stored
  } catch {
    // ignore storage access errors (e.g. private mode)
  }
  return 'en'
}

export function storeLanguage(lang: AppLanguage): void {
  try {
    window.localStorage.setItem(LANG_STORAGE_KEY, lang)
  } catch {
    // ignore storage access errors (e.g. private mode)
  }
}

/**
 * Apply the active language to <html lang> and `dir` so the entire UI
 * (including browser form controls and scrollbars) follows the locale.
 */
export function applyLanguageToDocument(lang: AppLanguage): void {
  document.documentElement.lang = lang
  document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr'
}

i18n.use(initReactI18next).init({
  resources: {
    en: { translation: en },
    ar: { translation: ar },
  },
  lng: getStoredLanguage(),
  fallbackLng: 'en',
  interpolation: { escapeValue: false },
  react: { useSuspense: false },
})

applyLanguageToDocument(getStoredLanguage())

export default i18n