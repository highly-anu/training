import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { safeReturnPath } from '@/lib/returnPath'
import { useAuthStore } from '@/store/authStore'

export function LoginPage() {
  const [tab, setTab] = useState<'signin' | 'signup'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [signupSent, setSignupSent] = useState(false)
  const signIn = useAuthStore((s) => s.signIn)
  const signUp = useAuthStore((s) => s.signUp)
  const signInWithApple = useAuthStore((s) => s.signInWithApple)
  const navigate = useNavigate()
  const location = useLocation()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      if (tab === 'signin') {
        await signIn(email, password)
        navigate(safeReturnPath((location.state as { from?: unknown } | null)?.from), { replace: true })
      } else {
        await signUp(email, password)
        setSignupSent(true)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Authentication failed')
    } finally {
      setLoading(false)
    }
  }

  // The same Apple account the iPhone app signs up with. The browser leaves
  // for Apple and comes back to where the athlete was going.
  const handleApple = async () => {
    setError(null)
    setLoading(true)
    try {
      await signInWithApple(safeReturnPath((location.state as { from?: unknown } | null)?.from))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in with Apple failed')
      setLoading(false)
    }
  }

  const switchTab = (t: 'signin' | 'signup') => {
    setTab(t)
    setError(null)
    setSignupSent(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <div className="w-full max-w-sm space-y-8">
        {/* Header */}
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Training</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {tab === 'signin' ? 'Sign in to access your program' : 'Create an account'}
          </p>
        </div>

        <button
          type="button"
          onClick={handleApple}
          disabled={loading}
          className="w-full flex items-center justify-center gap-2 rounded-md bg-foreground px-4 py-2.5 text-sm font-medium text-background shadow hover:bg-foreground/90 disabled:opacity-50 transition-colors"
        >
          <svg aria-hidden="true" viewBox="0 0 814 1000" className="h-4 w-4 fill-current">
            <path d="M788 341c-6 4-108 62-108 190 0 148 130 200 134 202-1 3-21 72-69 142-43 62-88 124-156 124s-86-40-165-40c-77 0-104 41-166 41s-106-57-156-127C44 791 0 663 0 541c0-196 127-299 253-299 66 0 122 44 163 44 40 0 102-46 178-46 29 0 133 3 194 101zM554 160c31-37 53-88 53-139 0-7-1-14-2-20-50 2-110 34-146 76-28 32-55 83-55 135 0 8 1 16 2 18 3 1 9 2 14 2 45 0 102-30 134-72z" />
          </svg>
          Continue with Apple
        </button>

        <div className="flex items-center gap-3 text-xs text-muted-foreground" aria-hidden="true">
          <div className="h-px flex-1 bg-border" />
          or
          <div className="h-px flex-1 bg-border" />
        </div>

        {/* Tab switcher */}
        <div className="flex rounded-lg border border-border p-1 gap-1">
          {(['signin', 'signup'] as const).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => switchTab(t)}
              className={`flex-1 rounded-md py-1.5 text-sm font-medium transition-colors ${
                tab === t
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {t === 'signin' ? 'Sign in' : 'Sign up'}
            </button>
          ))}
        </div>

        {signupSent ? (
          <div className="rounded-lg border border-border bg-muted/40 p-5 text-sm space-y-3">
            <p className="font-medium">Check your email</p>
            <p className="text-muted-foreground">
              We sent a confirmation link to <span className="text-foreground font-medium">{email}</span>.
              Click it to activate your account, then sign in.
            </p>
            <button
              type="button"
              onClick={() => switchTab('signin')}
              className="text-xs text-primary hover:underline"
            >
              Back to sign in
            </button>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="email">Email</label>
              <input
                id="email"
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring placeholder:text-muted-foreground"
                placeholder="you@example.com"
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="password">Password</label>
              <input
                id="password"
                type="password"
                required
                autoComplete={tab === 'signin' ? 'current-password' : 'new-password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring placeholder:text-muted-foreground"
                placeholder={tab === 'signup' ? 'At least 6 characters' : ''}
              />
            </div>

            {error && <p className="text-sm text-destructive">{error}</p>}

            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow hover:bg-primary/90 disabled:opacity-50 transition-colors"
            >
              {loading ? '…' : tab === 'signin' ? 'Sign in' : 'Create account'}
            </button>
          </form>
        )}
      </div>
    </div>
  )
}
