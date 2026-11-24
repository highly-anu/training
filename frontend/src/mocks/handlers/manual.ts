import { http, HttpResponse } from 'msw'
import recorded from '../fixtures/manual-sessions.json'

// Recorded by test_manual_builder.py --write, which fails when the routes no
// longer answer in this shape. With mock data a save answers the first
// recorded session and nothing is kept.
export const manualHandlers = [
  http.get('*/manual/sessions', () => HttpResponse.json(recorded.list)),
  http.post('*/manual/preview', () => HttpResponse.json(recorded.preview)),
  http.post('*/manual/sessions', () => HttpResponse.json({ session: recorded.list.sessions[0] })),
  http.put('*/manual/sessions/:id', () => HttpResponse.json({ session: recorded.list.sessions[0] })),
  http.delete('*/manual/sessions/:id', () => HttpResponse.json({ removed: true })),
]
