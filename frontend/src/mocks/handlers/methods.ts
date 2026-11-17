import { http, HttpResponse } from 'msw'
import recorded from '../fixtures/methods.json'

// Recorded by test_package_builder.py --write, which fails when the routes no
// longer answer in this shape. With mock data a build "runs" for three polls.
let polls = 0
let started = false

export const methodHandlers = [
  http.get('*/methods', () => HttpResponse.json(started && polls < 3 ? recorded.methodsWhileRunning : recorded.methods)),
  http.post('*/methods/builds', () => {
    started = true
    polls = 0
    return HttpResponse.json(recorded.running, { status: 202 })
  }),
  http.get('*/methods/builds/:id', ({ params }) => {
    if (params.id === 'build-failed') return HttpResponse.json(recorded.failed)
    polls += 1
    return HttpResponse.json(started && polls < 3 ? recorded.running : recorded.done)
  }),
  http.post('*/methods/builds/:id/cancel', () => {
    started = false
    return HttpResponse.json({ build: { ...recorded.running.build, status: 'cancelled',
      error: { code: 'cancelled', message: 'Cancelled.' } } })
  }),
  http.delete('*/methods/:id', () => HttpResponse.json({ removed: true })),
]
