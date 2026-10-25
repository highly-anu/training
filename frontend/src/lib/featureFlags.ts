import type { User } from '@supabase/supabase-js'
import { useAuthStore } from '@/store/authStore'

/**
 * Build-time feature flags. Vite inlines `import.meta.env.*` at build time, so
 * a flag that is off removes the route as well as the nav entry — a URL typed
 * by hand does not mount the page.
 */

/**
 * Dev Lab (pipeline trace, object browser, ontology graph, model interactions)
 * is developer tooling, not user navigation. It is on in every `npm run dev`
 * and off in a production build unless that build sets `VITE_DEVLAB=1`, or
 * the signed-in user has the `dev` role (`useDevLabEnabled`).
 */
export const DEVLAB_ENABLED: boolean =
  import.meta.env.DEV || import.meta.env.VITE_DEVLAB === '1'

/**
 * A user's roles: `app_metadata.roles` on the Supabase user. Only the service
 * role key writes app_metadata (user_metadata is the user's own to change),
 * so a role cannot be granted from the browser.
 */
export function hasRole(user: User | null, role: string): boolean {
  const roles: unknown = user?.app_metadata?.roles
  return Array.isArray(roles) && roles.includes(role)
}

/** Whether this build, or the signed-in user, gets the Dev Lab. It shows
 *  nothing the server would not answer any signed-in user: the authoring
 *  routes stay behind the server's own gate (api.require_authoring). */
export function useDevLabEnabled(): boolean {
  const user = useAuthStore((s) => s.user)
  return DEVLAB_ENABLED || hasRole(user, 'dev')
}
