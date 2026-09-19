/**
 * Package provenance helpers.
 *
 * An exercise id can be declared by several philosophy packages (76 of them are).
 * The API sends `_packages` listing every declarer; `_package` is only the first
 * one seen during loading and is kept for display back-compat. Anything deciding
 * "does this belong to philosophy X" must read `_packages`.
 */

export interface HasPackages {
  _package?: string
  _packages?: string[]
}

/** Every package that declares this entity, falling back to the legacy single field. */
export function packagesOf(entity: HasPackages | null | undefined): string[] {
  if (!entity) return []
  if (entity._packages?.length) return entity._packages
  return entity._package ? [entity._package] : []
}

/** True when the entity is declared by `packageId`, or has no provenance at all. */
export function belongsToPackage(
  entity: HasPackages | null | undefined,
  packageId: string | null | undefined,
): boolean {
  if (!packageId) return true
  const owners = packagesOf(entity)
  return owners.length === 0 || owners.includes(packageId)
}
