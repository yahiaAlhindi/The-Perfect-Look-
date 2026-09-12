import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// GitHub Pages project sub-path. MUST match the repository name:
// https://yahiaAlhindi.github.io/The-Perfect-Look-/
const base = '/The-Perfect-Look-/'

export default defineConfig({
  base,
  plugins: [
    react(),
    // PWA readiness config (full install/offline polish lands in T30).
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['pwa-192x192.png', 'pwa-512x512.png'],
      manifest: {
        name: 'The Perfect Look',
        short_name: 'Perfect Look',
        description:
          'The Perfect Look clinic — book appointments online.',
        display: 'standalone',
        start_url: base,
        scope: base,
        theme_color: '#1a1a1a',
        background_color: '#ffffff',
        icons: [
          {
            src: 'pwa-192x192.png',
            sizes: '192x192',
            type: 'image/png',
          },
          {
            src: 'pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png',
          },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
        navigateFallback: 'index.html',
      },
    }),
  ],
  // Options for viewing the deploy target locally:
  //   npm run dev  -> http://localhost:5173/The-Perfect-Look-/
  //   npm run build && npm run preview
})