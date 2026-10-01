/**
 * Build-time feature flags. Vite inlines `import.meta.env.*` at build time, so
 * a flag that is off removes the route as well as the nav entry — a URL typed
 * by hand does not mount the page.
 */

/**
 * Dev Lab (pipeline trace, object browser, ontology graph, model interactions)
 * is developer tooling, not user navigation. It is on in every `npm run dev`
 * and off in a production build unless that build sets `VITE_DEVLAB=1`.
 */
export const DEVLAB_ENABLED: boolean =
  import.meta.env.DEV || import.meta.env.VITE_DEVLAB === '1'
