import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import './i18n'
import App from './App'
import { AuthProvider } from './context/AuthContext'
import { Toaster } from '@/components/ui/toaster'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AuthProvider>
      <App />
      <Toaster />
    </AuthProvider>
  </StrictMode>,
)