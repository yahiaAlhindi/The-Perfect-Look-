/* ============================================================================
   BRAND CONFIG — the JS/asset side of the swap layer for T46.
   CSS colour/font tokens live in src/styles/tokens.css.
   Everything referenced here is PLACEHOLDER until the approved client
   assets arrive from T36.
   ========================================================================== */

import type { LucideIcon } from 'lucide-react'
import { Sparkles } from 'lucide-react'

export const brand = {
  /** Human-readable brand name. */
  name: 'The Perfect Look',

  /** Short strapline used in headers/empty states. */
  tagline: 'Appointments booking',

  /**
   * Default placeholder brand mark for the component library.
   * Swap the component (or path) here once approved assets land in T46.
   */
  mark: {
    icon: Sparkles as LucideIcon,
    label: 'TPL',
  },

  /** Static asset URLs (serve from /public). */
  assets: {
    logo: '/The-Perfect-Look-/brand/logo.svg',
    icon192: '/The-Perfect-Look-/pwa-192x192.png',
    icon512: '/The-Perfect-Look-/pwa-512x512.png',
  },

  /** Font families driven by tokens.css. */
  fonts: {
    latin: 'Segoe UI',
    arabic: 'Noto Sans Arabic',
  },
} as const

export type BrandConfig = typeof brand