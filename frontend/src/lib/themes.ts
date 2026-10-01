/**
 * The four themes, in the order the sidebar picker and Settings ▸ Appearance
 * show them. Shared from here rather than from the picker: a component file
 * that also exports data breaks Fast Refresh.
 */
export const THEMES = [
  { id: 'light',    label: 'Light',    bg: '#ffffff',  primary: '#f59e0b', description: 'Paper and amber.' },
  { id: 'dark',     label: 'Dark',     bg: '#1c1b27',  primary: '#f59e0b', description: 'The default: ink and amber.' },
  { id: 'military', label: 'Military', bg: '#1e2318',  primary: '#5b8a3c', description: 'Olive on near-black.' },
  { id: 'zen',      label: 'Zen',      bg: '#f7f5f0',  primary: '#4a8c70', description: 'Warm white and sage.' },
] as const

export type ThemeId = (typeof THEMES)[number]['id']
