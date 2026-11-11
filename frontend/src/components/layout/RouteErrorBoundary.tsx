import { Component, type ErrorInfo, type ReactNode } from 'react'
import { FailedState } from '@/components/shared/states'

interface Props {
  /** The path: a new page is a new chance, so the boundary resets when it changes. */
  resetKey: string
  children: ReactNode
}

interface State {
  error: Error | null
  key: string
}

/**
 * A page that throws while rendering shows what happened and a way on; the
 * sidebar and top bar stay (docs/frontend-design.md §11.3). Without it a
 * render error unmounted the whole app to a blank window.
 */
export class RouteErrorBoundary extends Component<Props, State> {
  state: State = { error: null, key: this.props.resetKey }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error }
  }

  static getDerivedStateFromProps(props: Props, state: State): Partial<State> | null {
    return props.resetKey === state.key ? null : { error: null, key: props.resetKey }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[page] render failed', error, info.componentStack)
  }

  render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="flex-1 overflow-auto p-6">
        <FailedState
          title="This page could not be shown"
          error={this.state.error}
          onRetry={() => window.location.reload()}
          retryLabel="Reload"
        />
      </div>
    )
  }
}
