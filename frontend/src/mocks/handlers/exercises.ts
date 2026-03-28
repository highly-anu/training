import { http, HttpResponse } from 'msw'
import exercisesData from '../fixtures/exercises.json'

export const exerciseHandlers = [
  http.get('*/exercises', () => {
    return HttpResponse.json(exercisesData)
  }),

  http.get('*/exercises/:id', ({ params }) => {
    const exercise = exercisesData.find((e) => e.id === params.id)
    if (!exercise) return new HttpResponse(null, { status: 404 })
    return HttpResponse.json(exercise)
  }),
]
