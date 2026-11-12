/**
 * Where a shown value stands, for the direction a `RollingNumber` rolls in:
 * "1,234" is 1234 and "4:58" is 298 seconds (parseFloat read them as 1 and 4).
 * NaN when the text is not a number; the roll then goes up.
 */
export function rollRank(value: string | number): number {
  if (typeof value === 'number') return value
  const text = value.trim()
  const clock = /^(\d+):(\d{2})(?::(\d{2}))?$/.exec(text)
  if (clock) {
    const [a, b] = [Number(clock[1]), Number(clock[2])]
    return clock[3] === undefined ? a * 60 + b : a * 3600 + b * 60 + Number(clock[3])
  }
  return Number.parseFloat(text.replace(/,/g, ''))
}
