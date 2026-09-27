import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    rules: {
      // A compiler optimisation advisory, not a correctness rule: it fires
      // where React Compiler cannot PROVE a dependency is never mutated, and
      // declines to optimise that component. The three current sites were
      // checked by hand — the values derive from query data via `.find()` and
      // nothing mutates them — so this is kept visible as a warning rather
      // than contorting working code to satisfy a conservative analysis.
      // The correctness rules it ships alongside (rules-of-hooks,
      // set-state-in-effect, refs-during-render) stay errors.
      'react-hooks/preserve-manual-memoization': 'warn',
      // The codebase already marks deliberately-unused bindings with a leading
      // underscore — `catch (_)`, props destructured only to drop them from a
      // rest spread. Honour that rather than reporting intent as dead code.
      '@typescript-eslint/no-unused-vars': ['error', {
        argsIgnorePattern: '^_',
        varsIgnorePattern: '^_',
        caughtErrorsIgnorePattern: '^_',
        destructuredArrayIgnorePattern: '^_',
      }],
    },
  },
  {
    // shadcn/ui components are vendored, and its generator co-locates each
    // component with its `cva` variants. Splitting them to satisfy a
    // fast-refresh convention would mean diverging from upstream for no gain.
    files: ['src/components/ui/**/*.{ts,tsx}'],
    rules: { 'react-refresh/only-export-components': 'off' },
  },
])
