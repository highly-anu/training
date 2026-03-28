import { http, HttpResponse } from 'msw'
import equipmentProfilesData from '../fixtures/equipment-profiles.json'
import injuryFlagsData from '../fixtures/injury-flags.json'

export const constraintHandlers = [
  http.get('*/constraints/equipment-profiles', () => {
    return HttpResponse.json(equipmentProfilesData)
  }),

  http.get('*/constraints/injury-flags', () => {
    return HttpResponse.json(injuryFlagsData)
  }),
]
