import { http, HttpResponse } from 'msw'
import recorded from '../fixtures/shares.json'

// Recorded by test_sharing.py --write, which fails when the routes no longer
// answer in this shape. With mock data /s/tok_session, /s/tok_method and
// /s/tok_program open; any other token is a link that is no longer shared.
const byToken = Object.fromEntries(Object.values(recorded).map((doc) => [doc.token, doc]))

export const shareHandlers = [
  http.get('*/shares/:token', ({ params }) => {
    const doc = byToken[String(params.token)]
    return doc ? HttpResponse.json(doc) : HttpResponse.json({ error: 'not_found', detail: 'This link is no longer shared.' }, { status: 404 })
  }),
  http.get('*/shares', () => HttpResponse.json({ shares: [], limit: 50 })),
  http.post('*/shares', () => HttpResponse.json({
    token: 'tok_session', kind: 'session', title: recorded.session.title, createdAt: recorded.session.createdAt,
    url: `${window.location.origin}/s/tok_session`,
  })),
  http.delete('*/shares/:token', () => HttpResponse.json({ revoked: true })),
]
