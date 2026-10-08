/**
 * Where to go after signing in. ProtectedRoute hands the login page the
 * location it bounced from, so a scanned watch QR (`/pair?code=…`) survives
 * the sign-in instead of landing on Home with the code lost.
 *
 * Only an in-app path is followed: it must start with one "/" — "//host" and
 * "/\host" are protocol-relative URLs a browser would leave the site for — and
 * the login page itself is never a destination. Anything else goes Home.
 */
export function safeReturnPath(from: unknown): string {
  if (typeof from !== 'string') return '/'
  if (!from.startsWith('/') || from.startsWith('//') || from.startsWith('/\\')) return '/'
  if (from === '/login' || from.startsWith('/login?') || from.startsWith('/login/')) return '/'
  return from
}

/** A pairing code as the watch shows it: six of the unambiguous characters
 *  src/device_store.py draws from (no O/0/I/1), upper-cased. Null when the
 *  link carries anything else. */
export function pairingCode(raw: string | null): string | null {
  const code = (raw ?? '').trim().toUpperCase()
  return /^[A-HJ-NP-Z2-9]{6}$/.test(code) ? code : null
}
