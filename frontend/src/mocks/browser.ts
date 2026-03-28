import { setupWorker } from 'msw/browser'
import { goalHandlers } from './handlers/goals'
import { exerciseHandlers } from './handlers/exercises'
import { programHandlers } from './handlers/programs'
import { constraintHandlers } from './handlers/constraints'
import { modalityHandlers } from './handlers/modalities'

export const worker = setupWorker(
  ...goalHandlers,
  ...exerciseHandlers,
  ...programHandlers,
  ...constraintHandlers,
  ...modalityHandlers,
)
