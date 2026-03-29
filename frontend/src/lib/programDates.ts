import { addDays, parseISO } from 'date-fns'

/**
 * Returns the calendar Date for a given week/day slot in the program.
 * weekIndex is 0-based. dayIndex is 0=Monday … 6=Sunday.
 * Returns null if programStartDate is not set.
 */
export function programDayDate(
  programStartDate: string | null,
  weekIndex: number,
  dayIndex: number
): Date | null {
  if (!programStartDate) return null
  return addDays(parseISO(programStartDate), weekIndex * 7 + dayIndex)
}
