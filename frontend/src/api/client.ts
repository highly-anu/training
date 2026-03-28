import axios from 'axios'

export const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:8000/api',
  headers: { 'Content-Type': 'application/json' },
  timeout: 30_000,
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
