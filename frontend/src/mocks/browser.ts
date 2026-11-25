import { setupWorker } from 'msw/browser'
import { exerciseHandlers } from './handlers/exercises'
import { programHandlers } from './handlers/programs'
import { constraintHandlers } from './handlers/constraints'
import { modalityHandlers } from './handlers/modalities'
import { devlabHandlers } from './handlers/devlab'
import { methodHandlers } from './handlers/methods'
import { manualHandlers } from './handlers/manual'
import { shareHandlers } from './handlers/shares'

export const worker = setupWorker(
  ...exerciseHandlers,
  ...programHandlers,
  ...constraintHandlers,
  ...modalityHandlers,
  ...devlabHandlers,
  ...methodHandlers,
  ...manualHandlers,
  ...shareHandlers,
)
