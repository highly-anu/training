/**
 * "HKWorkoutActivityTypeTraditionalStrengthTraining" → "Traditional Strength Training".
 * Imported workouts carry the recording device's raw type string; every list
 * that shows one needs the same cleanup.
 */
export function formatActivityType(raw: string): string {
  return (
    raw
      .replace(/HKWorkoutActivityType/g, '')
      .replace(/([a-z])([A-Z])/g, '$1 $2')
      .trim() || raw
  )
}
