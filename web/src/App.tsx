import { lazy, Suspense, type ReactNode } from 'react'
import { HashRouter, Navigate, Route, Routes, Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { GuestRoute, ProtectedRoute } from './components/routing/AuthRoute'
import { useAuth } from './context/AuthContext'

const LoginPage = lazy(() => import('./auth/LoginPage'))
const RegisterPage = lazy(() => import('./auth/RegisterPage'))
const ForgotPasswordPage = lazy(() => import('./auth/ForgotPasswordPage'))
const ResetPasswordPage = lazy(() => import('./auth/ResetPasswordPage'))
const LogoutPage = lazy(() => import('./auth/LogoutPage'))
const ProfilePage = lazy(() => import('./profile/ProfilePage'))
const DesignSystemPage = lazy(() => import('@/pages/DesignSystemPage'))

function PageFallback() {
  const { t } = useTranslation()
  return (
    <div className="auth-shell">
      <div className="auth-shell__card auth-shell__card--centered">
        <div className="spinner" aria-hidden="true" />
        <p aria-live="polite">{t('common.loading')}</p>
      </div>
    </div>
  )
}

/**
 * Home — interim shell (T2 owns the full portal). Keeps the auth + profile
 * pages reachable and gives signed-in visitors a way out via logout.
 */
function Home() {
  const { t } = useTranslation()
  const { phase, profile } = useAuth()

  return (
    <main className="app-shell">
      <h1>{t('common.appName')}</h1>
      <p>Appointments booking app — MVP foundation (T2).</p>
      <nav className="home-nav">
        {phase === 'authenticated' ? (
          <>
            <p>
              {profile ? `Welcome, ${profile.full_name}.` : 'You are signed in.'}
            </p>
            <Link className="btn btn--secondary" to="/auth/logout">
              {t('auth.logout.title')}
            </Link>
            <Link className="btn btn--primary" to="/profile">
              {t('profile.title')}
            </Link>
          </>
        ) : (
          <>
            <Link className="btn btn--primary" to="/auth/login">
              {t('auth.linkLogin')}
            </Link>
            <Link className="btn btn--secondary" to="/auth/register">
              {t('auth.linkRegister')}
            </Link>
          </>
        )}
      </nav>
    </main>
  )
}

/**
 * Demo guarded page exercising return-to-booking: anonymous visitors who
 * land here are sent to /auth/login?redirect=/booking and bounced back
 * after signing in.
 */
function BookingDemo() {
  const { t } = useTranslation()
  const { profile } = useAuth()

  return (
    <main className="app-shell">
      <h1>{t('common.appName')}</h1>
      <p>
        Booking area — protected demo (T6 return-to-booking).{' '}
        {profile ? `Signed in as ${profile.full_name}.` : ''}
      </p>
      <Link className="btn btn--secondary" to="/">
        Home
      </Link>
    </main>
  )
}

/**
 * Lazy pages need a boundary while their chunk loads.
 */
function withFallback(page: ReactNode) {
  return <Suspense fallback={<PageFallback />}>{page}</Suspense>
}

export default function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route
          path="/components"
          element={withFallback(<DesignSystemPage />)}
        />

        <Route
          path="/auth/login"
          element={
            <GuestRoute>{withFallback(<LoginPage />)}</GuestRoute>
          }
        />
        <Route
          path="/auth/register"
          element={
            <GuestRoute>{withFallback(<RegisterPage />)}</GuestRoute>
          }
        />
        <Route
          path="/auth/forgot-password"
          element={
            <GuestRoute>{withFallback(<ForgotPasswordPage />)}</GuestRoute>
          }
        />
        <Route
          path="/auth/reset-password"
          element={withFallback(<ResetPasswordPage />)}
        />
        <Route
          path="/auth/logout"
          element={withFallback(<LogoutPage />)}
        />

        <Route path="/booking" element={<ProtectedRoute>{withFallback(<BookingDemo />)}</ProtectedRoute>} />

        <Route
          path="/profile"
          element={<ProtectedRoute>{withFallback(<ProfilePage />)}</ProtectedRoute>}
        />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </HashRouter>
  )
}