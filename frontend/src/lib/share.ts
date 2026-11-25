/**
 * Hands a link to the system's share sheet, else to the clipboard
 * (docs/roadmap.md item 25). → how it went, for the button to say.
 */
export type ShareOutcome = 'shared' | 'copied' | 'cancelled' | 'failed'

export async function shareLink(url: string, title: string): Promise<ShareOutcome> {
  const nav = typeof navigator === 'undefined' ? undefined : navigator
  if (nav?.share) {
    try {
      await nav.share({ url, title })
      return 'shared'
    } catch (err) {
      // The athlete closed the sheet: nothing to say, nothing to copy.
      if ((err as { name?: string } | null)?.name === 'AbortError') return 'cancelled'
    }
  }
  try {
    await nav?.clipboard?.writeText(url)
    return nav?.clipboard ? 'copied' : 'failed'
  } catch {
    return 'failed'
  }
}

/** The app's own address for a link: what "Open in the app" opens. */
export function appLink(token: string): string {
  return `trainingcompanion://share?token=${encodeURIComponent(token)}`
}
