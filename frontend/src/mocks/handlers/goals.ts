import { http, HttpResponse } from 'msw'
import goalsData from '../fixtures/goals.json'

export const goalHandlers = [
  http.get('*/goals', () => {
    return HttpResponse.json(goalsData)
  }),

  http.get('*/goals/:id', ({ params }) => {
    const goal = goalsData.find((g) => g.id === params.id)
    if (!goal) return new HttpResponse(null, { status: 404 })
    return HttpResponse.json(goal)
  }),
]
