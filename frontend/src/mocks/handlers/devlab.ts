import { http, HttpResponse } from 'msw'
import portability from '../fixtures/portability.json'
import modelMap from '../fixtures/model-map.json'

// Recorded by test_portability.py --write, which fails when the server's
// report no longer has this shape.
export const devlabHandlers = [
  http.get('*/dev/portability', () => HttpResponse.json(portability)),
  // Recorded by test_model_map.py --write.
  http.get('*/dev/model-map', () => HttpResponse.json(modelMap)),
]
