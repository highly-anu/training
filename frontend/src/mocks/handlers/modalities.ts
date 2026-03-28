import { http, HttpResponse } from 'msw'
import modalitiesData from '../fixtures/modalities.json'

export const modalityHandlers = [
  http.get('*/modalities', () => {
    return HttpResponse.json(modalitiesData)
  }),
]
