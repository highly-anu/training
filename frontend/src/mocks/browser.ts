import { setupWorker } from 'msw/browser'
import { exerciseHandlers } from './handlers/exercises'
import { programHandlers } from './handlers/programs'
import { constraintHandlers } from './handlers/constraints'
import { modalityHandlers } from './handlers/modalities'
import { devlabHandlers } from './handlers/devlab'

export const worker = setupWorker(
  ...exerciseHandlers,
  ...programHandlers,
  ...constraintHandlers,
  ...modalityHandlers,
  ...devlabHandlers,
)
