import { http, HttpResponse } from 'msw'
import portability from '../fixtures/portability.json'

// Recorded by test_portability.py --write, which fails when the server's
// report no longer has this shape.
export const devlabHandlers = [
  http.get('*/dev/portability', () => HttpResponse.json(portability)),
]
