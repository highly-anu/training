import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
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
  const navigate = useNavigate()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      if (tab === 'signin') {
        await signIn(email, password)
        navigate('/', { replace: true })
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
