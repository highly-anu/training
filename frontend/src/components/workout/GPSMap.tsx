import { useMemo } from 'react'
import { MapContainer, TileLayer, Polyline, Marker, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import type { GPSPoint } from '@/api/types'

// HR zone color thresholds (% of max HR ~190)
const ZONE_COLORS = [
  { max: 114, color: '#94a3b8' }, // Z1 — Recovery  (< 60%)
  { max: 133, color: '#38bdf8' }, // Z2 — Aerobic   (60-70%)
  { max: 152, color: '#fbbf24' }, // Z3 — Tempo     (70-80%)
  { max: 171, color: '#f97316' }, // Z4 — Threshold (80-90%)
  { max: 999, color: '#ef4444' }, // Z5 — Max       (> 90%)
]

function hrColor(bpm: number | null | undefined, maxHR: number): string {
  if (bpm == null) return '#94a3b8'
  const thresholds = [
    maxHR * 0.6,
    maxHR * 0.7,
    maxHR * 0.8,
    maxHR * 0.9,
    999,
  ]
  for (let i = 0; i < thresholds.length; i++) {
    if (bpm < thresholds[i]) return ZONE_COLORS[i].color
  }
  return ZONE_COLORS[4].color
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
  className?: string
}

export function GPSMap({ track, maxHR = 190, className }: GPSMapProps) {
  // Build colored segments — each segment is a pair of adjacent points
  const segments = useMemo(() => {
    const segs: { positions: [number, number][]; color: string }[] = []
    for (let i = 0; i < track.length - 1; i++) {
      const color = hrColor(track[i].bpm, maxHR)
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
  }, [track, maxHR])

  const allPoints: [number, number][] = useMemo(
    () => track.map((p) => [p.lat, p.lng]),
    [track]
  )

  const start = track[0]
  const end = track[track.length - 1]

  return (
    <div className={`rounded-lg overflow-hidden border border-border ${className ?? ''}`} style={className ? undefined : { height: 360 }}>
      <MapContainer
        center={[start.lat, start.lng]}
        zoom={13}
        scrollWheelZoom={true}
        style={{ height: '100%', width: '100%' }}
        attributionControl={false}
      >
        <TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" />
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
