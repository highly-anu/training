import { http, HttpResponse } from 'msw'
import portability from '../fixtures/portability.json'
import modelMap from '../fixtures/model-map.json'
import builds from '../fixtures/builds.json'

// Recorded by test_portability.py --write, which fails when the server's
// report no longer has this shape.
export const devlabHandlers = [
  http.get('*/dev/portability', () => HttpResponse.json(portability)),
  // Recorded by test_model_map.py --write.
  http.get('*/dev/model-map', () => HttpResponse.json(modelMap)),
  // Recorded by test_package_builder.py --write: a build that fixed what its
  // first check found, and one that ran out of turns.
  http.get('*/dev/builds', () => HttpResponse.json(builds.list)),
  http.get('*/dev/builds/:id', ({ params }) =>
    params.id === builds.failed.build.id ? HttpResponse.json(builds.failed) : HttpResponse.json(builds.done)),
]
