/** Why a save did not happen, in the reader's words. */
export function saveRefusal(err: { status?: number; body?: { error?: string; busy?: boolean; olderEngine?: boolean; name?: string; problems?: { message: string }[] }; message: string }): string {
  const body = err.body ?? {}
  if (body.busy) return 'The server is busy with another check. Try again in a moment.'
  if (body.error === 'too_many_packages') return 'You keep the most methods an account can hold. Remove one, then save this.'
  if (body.error === 'not_enabled') return 'Saving methods is not available for this account.'
  if (body.error === 'not_found') return 'This link is no longer shared.'
  if (body.error === 'not_installable') {
    return body.olderEngine
      ? `${body.name ?? 'This method'} was written for an earlier version of the app and no longer passes its checks. Ask for a new link.`
      : `${body.name ?? 'This method'} did not pass the app's checks${body.problems?.[0] ? `: ${body.problems[0].message}` : '.'}`
  }
  return err.message
}
