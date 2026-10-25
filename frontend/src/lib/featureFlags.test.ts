import { describe, expect, it } from 'vitest'
import type { User } from '@supabase/supabase-js'
import { hasRole } from './featureFlags'

const user = (fields: Partial<User>) => ({ app_metadata: {}, user_metadata: {}, ...fields }) as User

describe('hasRole', () => {
  it('reads app_metadata.roles', () => {
    expect(hasRole(user({ app_metadata: { roles: ['dev'] } }), 'dev')).toBe(true)
    expect(hasRole(user({ app_metadata: { roles: ['coach'] } }), 'dev')).toBe(false)
  })

  it('never reads user_metadata, which the user can write', () => {
    expect(hasRole(user({ user_metadata: { roles: ['dev'] } }), 'dev')).toBe(false)
  })

  it('is false signed out or with a malformed claim', () => {
    expect(hasRole(null, 'dev')).toBe(false)
    expect(hasRole(user({ app_metadata: { roles: 'dev' } }), 'dev')).toBe(false)
  })
})
