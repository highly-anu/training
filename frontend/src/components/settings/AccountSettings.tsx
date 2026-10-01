import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { LogOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useAuthStore } from '@/store/authStore'

/**
 * Settings → Account: who is signed in, the saved accounts to switch
 * between, and sign-out. Lived on Profile ▸ Athlete until Settings existed;
 * an account is configuration, not something about the athlete's training.
 */
export function AccountSettings() {
  const navigate = useNavigate()
  const { user, savedAccounts, signOutCurrent, switchToAccount } = useAuthStore()
  const [switching, setSwitching] = useState(false)

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Settings
          </p>
          <h2 className="text-2xl font-semibold tracking-tight">Account.</h2>
          <p className="text-sm text-muted-foreground max-w-prose">
            {user
              ? 'The account this browser is signed in to. Everything you log, generate and connect belongs to it.'
              : 'This build runs against a local server with no sign-in, as the local development user.'}
          </p>
        </div>

        <div className="space-y-3">
          <h3 className="text-xs uppercase tracking-wider text-muted-foreground/50 font-medium">Signed in as</h3>
          <div className="rounded-lg border border-border/30 bg-card/40 p-4 flex items-center justify-between gap-3">
            {user && savedAccounts.length > 1 ? (
              <Select
                value={user.email ?? ''}
                onValueChange={async (val) => {
                  if (val === '__add__') { navigate('/login'); return }
                  if (val === user.email) return
                  setSwitching(true)
                  try { await switchToAccount(val) } finally { setSwitching(false) }
                }}
                disabled={switching}
              >
                <SelectTrigger className="w-64 h-8 text-xs font-mono"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {savedAccounts.map((a) => (
                    <SelectItem key={a.email} value={a.email} className="text-xs font-mono">{a.email}</SelectItem>
                  ))}
                  <SelectSeparator />
                  <SelectItem value="__add__" className="text-xs text-muted-foreground">Add account →</SelectItem>
                </SelectContent>
              </Select>
            ) : user ? (
              <span className="text-xs font-mono text-muted-foreground">{user.email}</span>
            ) : (
              <span className="text-xs text-muted-foreground">Local development — no account.</span>
            )}
            {user && (
              <Button variant="ghost" size="sm" onClick={signOutCurrent} className="h-8 text-xs text-muted-foreground hover:text-destructive">
                <LogOut className="size-3.5 mr-1.5" /> Sign out
              </Button>
            )}
          </div>
          {user && savedAccounts.length <= 1 && (
            <p className="text-[11px] text-muted-foreground">
              Sign in with another account from the login page to switch between them here.
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
