// from 'vitest/config' rather than 'vite' so the `test` block below type-checks
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      // Data files shared with the Python backend — the canonical copy lives in
      // the repo's data/ dir so the two workout-matcher implementations cannot
      // drift apart. See src/lib/workoutMatcher.ts.
      '@shared': path.resolve(__dirname, '../data'),
    },
  },
  server: {
    proxy: {
      '/api': 'http://localhost:8000',
    },
    fs: {
      // Allow reading ../data for the @shared alias above.
      allow: [path.resolve(__dirname, '..')],
    },
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'test/**/*.test.ts'],
  },
})
