import axios from 'axios'
import { supabase } from '@/lib/supabase'

export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8000/api',
  headers: { 'Content-Type': 'application/json' },
  timeout: 30_000,
})

// Inject Supabase JWT on every request (no-op when no session / local dev)
apiClient.interceptors.request.use(async (config) => {
  const { data: { session } } = await supabase.auth.getSession()
  if (session?.access_token) {
    config.headers.Authorization = `Bearer ${session.access_token}`
  }
  return config
})

// Normalize response: unwrap .data so hooks get the payload directly
apiClient.interceptors.response.use(
  (res) => res.data,
  (err) => {
    const message =
      (err.response?.data as { detail?: string } | undefined)?.detail ?? err.message
    return Promise.reject(new Error(message))
  }
)
