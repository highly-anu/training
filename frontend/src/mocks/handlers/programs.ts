import { http, HttpResponse } from 'msw'
import programData from '../fixtures/generated-program.json'

export const programHandlers = [
  http.post('*/programs/generate', async () => {
    // Simulate generation delay
    await new Promise((resolve) => setTimeout(resolve, 1200))
    return HttpResponse.json(programData)
  }),
  // No history in mock mode: a briefing that adds nothing shows no block.
  http.get('*/sessions/briefing', () => HttpResponse.json({ headline: null, items: [], pending: [] })),
]
