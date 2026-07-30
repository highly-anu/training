import { useMemo } from 'react'
import { MapContainer, TileLayer, Polyline, Marker, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { GPSPoint } from '@/api/types'
import { DEFAULT_ZONE_BOUNDARIES, ZONE_COLORS } from '@/lib/hrZones'
import { useTheme } from 'next-themes'

// CartoDB serves both basemaps at an identical URL shape. Military is a dark
// surface so it groups with dark; Zen is warm off-white so it groups with light.
const DARK_THEMES = new Set(['dark', 'military'])
const basemapUrl = (isDark: boolean) =>
  `https://{s}.basemaps.cartocdn.com/${isDark ? 'dark_all' : 'light_all'}/{z}/{x}/{y}{r}.png`

function hrColor(bpm: number | null | undefined, maxHR: number, boundaries: number[]): string {
  if (bpm == null) return ZONE_COLORS[0]
  const pct = bpm / maxHR
  for (let i = 0; i < boundaries.length; i++) {
    if (pct < boundaries[i]) return ZONE_COLORS[i]
  }
  return ZONE_COLORS[4]
}

// Fit bounds to track
function FitBounds({ points }: { points: [number, number][] }) {
  const map = useMap()
  useMemo(() => {
    if (points.length > 0) {
      const bounds = L.latLngBounds(points.map(([lat, lng]) => [lat, lng]))
      map.fitBounds(bounds, { padding: [30, 30] })
    }
  }, [points, map])
  return null
}

// Custom small circle marker for start/end
function dotIcon(color: string) {
  return L.divIcon({
    className: '',
    html: `<div style="width:12px;height:12px;border-radius:50%;background:${color};border:2px solid white;box-shadow:0 1px 3px rgba(0,0,0,.4)"></div>`,
    iconSize: [12, 12],
    iconAnchor: [6, 6],
  })
}

interface GPSMapProps {
  track: GPSPoint[]
  maxHR?: number
  zoneBoundaries?: number[]
  className?: string
}

export function GPSMap({ track, maxHR = 190, zoneBoundaries = DEFAULT_ZONE_BOUNDARIES, className }: GPSMapProps) {
  // Build colored segments — each segment is a pair of adjacent points
  const segments = useMemo(() => {
    const segs: { positions: [number, number][]; color: string }[] = []
    for (let i = 0; i < track.length - 1; i++) {
      const color = hrColor(track[i].bpm, maxHR, zoneBoundaries)
      const from: [number, number] = [track[i].lat, track[i].lng]
      const to: [number, number] = [track[i + 1].lat, track[i + 1].lng]

      // Merge with previous segment if same color
      if (segs.length > 0 && segs[segs.length - 1].color === color) {
        segs[segs.length - 1].positions.push(to)
      } else {
        segs.push({ positions: [from, to], color })
      }
    }
    return segs
  }, [track, maxHR, zoneBoundaries])

  const allPoints: [number, number][] = useMemo(
    () => track.map((p) => [p.lat, p.lng]),
    [track]
  )

  const start = track[0]
  const end = track[track.length - 1]

  const { resolvedTheme } = useTheme()
  const tileUrl = basemapUrl(DARK_THEMES.has(resolvedTheme ?? 'dark'))

  return (
    <div className={`rounded-lg overflow-hidden border border-border isolate ${className ?? ''}`} style={className ? undefined : { height: 360 }}>
      <MapContainer
        center={[start.lat, start.lng]}
        zoom={13}
        scrollWheelZoom={true}
        style={{ height: '100%', width: '100%' }}
        attributionControl={false}
      >
        {/* key forces Leaflet to swap tiles cleanly when the theme changes */}
        <TileLayer key={tileUrl} url={tileUrl} />
        <FitBounds points={allPoints} />
        {segments.map((seg, i) => (
          <Polyline
            key={i}
            positions={seg.positions}
            pathOptions={{ color: seg.color, weight: 3, opacity: 0.9 }}
          />
        ))}
        <Marker position={[start.lat, start.lng]} icon={dotIcon('#22c55e')} />
        <Marker position={[end.lat, end.lng]} icon={dotIcon('#ef4444')} />
      </MapContainer>
    </div>
  )
}
