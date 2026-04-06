import { create } from 'zustand'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'

const ACCOUNTS_KEY = 'training-accounts'

export interface SavedAccount {
  email: string
  access_token: string
  refresh_token: string
  expires_at: number
}

function loadAccounts(): SavedAccount[] {
  try {
    return JSON.parse(localStorage.getItem(ACCOUNTS_KEY) ?? '[]')
  } catch {
    return []
  }
}

function persistAccounts(accounts: SavedAccount[]) {
  localStorage.setItem(ACCOUNTS_KEY, JSON.stringify(accounts))
}

function upsertAccount(accounts: SavedAccount[], account: SavedAccount): SavedAccount[] {
  const idx = accounts.findIndex((a) => a.email === account.email)
  if (idx >= 0) {
    const updated = [...accounts]
    updated[idx] = account
    return updated
  }
  return [...accounts, account]
}

interface AuthStore {
  session: Session | null
  user: User | null
  isLoading: boolean
  savedAccounts: SavedAccount[]
  signIn: (email: string, password: string) => Promise<void>
  signUp: (email: string, password: string) => Promise<void>
  /** Sign out the current account. If other saved accounts exist, switches to the first one. */
  signOutCurrent: () => Promise<void>
  /** Switch to a previously saved account by email. Throws if the session has expired. */
  switchToAccount: (email: string) => Promise<void>
  /** Call once on app mount. Returns an unsubscribe function. */
  init: () => () => void
}

export const useAuthStore = create<AuthStore>((set, get) => ({
  session: null,
  user: null,
  isLoading: true,
  savedAccounts: [],

  signIn: async (email, password) => {
    if (!supabase) throw new Error('Supabase is not configured')
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    // savedAccounts updated via onAuthStateChange SIGNED_IN handler
  },

  signUp: async (email, password) => {
    if (!supabase) throw new Error('Supabase is not configured')
    const { error } = await supabase.auth.signUp({ email, password })
    if (error) throw error
  },

  signOutCurrent: async () => {
    const { user, savedAccounts } = get()
    const remaining = savedAccounts.filter((a) => a.email !== user?.email)
    persistAccounts(remaining)
    set({ savedAccounts: remaining })

    if (!supabase) {
      set({ session: null, user: null })
    } else {
      await supabase.auth.signOut()
    }

    if (remaining.length > 0) {
      try {
        await get().switchToAccount(remaining[0].email)
      } catch {
        // Remaining token expired — already removed by switchToAccount; leave auth cleared
      }
    }
  },

  switchToAccount: async (email: string) => {
    if (!supabase) throw new Error('Supabase is not configured')
    const { savedAccounts } = get()
    const account = savedAccounts.find((a) => a.email === email)
    if (!account) throw new Error(`No saved session for ${email}`)

    const { error } = await supabase.auth.setSession({
      access_token: account.access_token,
      refresh_token: account.refresh_token,
    })

    if (error) {
      // Token expired — remove from saved accounts
      const updated = savedAccounts.filter((a) => a.email !== email)
      persistAccounts(updated)
      set({ savedAccounts: updated })
      throw error
    }
    // onAuthStateChange SIGNED_IN will update session + user in store
  },

  init: () => {
    // Dev mode: no Supabase URL configured — bypass auth entirely
    if (!import.meta.env.VITE_SUPABASE_URL) {
      set({ session: null, user: { id: 'local-dev-user', email: 'dev@local' } as User, isLoading: false })
      return () => {}
    }

    // Load persisted saved accounts
    set({ savedAccounts: loadAccounts() })

    // Resolve the persisted session immediately (no async flash)
    supabase!.auth.getSession().then(({ data: { session } }) => {
      set({ session, user: session?.user ?? null, isLoading: false })
    })

    // Keep in sync with Supabase auth events (login, logout, token refresh)
    const { data: { subscription } } = supabase!.auth.onAuthStateChange((event, session) => {
      set({ session, user: session?.user ?? null, isLoading: false })

      if ((event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') && session?.user?.email) {
        const account: SavedAccount = {
          email: session.user.email,
          access_token: session.access_token,
          refresh_token: session.refresh_token,
          expires_at: session.expires_at ?? 0,
        }
        const updated = upsertAccount(get().savedAccounts, account)
        persistAccounts(updated)
        set({ savedAccounts: updated })
      }
    })

    return () => subscription.unsubscribe()
  },
}))
