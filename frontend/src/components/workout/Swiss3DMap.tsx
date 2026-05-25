import { useEffect, useRef, useState } from 'react'
import type { GPSPoint } from '@/api/types'

const CESIUM_VERSION = '1.113'
const CESIUM_CDN = `https://cesium.com/downloads/cesiumjs/releases/${CESIUM_VERSION}/Build/Cesium`

declare global {
  interface Window {
    CESIUM_BASE_URL?: string
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    Cesium: any
  }
}

// Singleton load promise — survives React strict-mode double-mounts
let loadPromise: Promise<void> | null = null

function loadCesium(): Promise<void> {
  if (window.Cesium) return Promise.resolve()
  if (loadPromise) return loadPromise

  loadPromise = new Promise<void>((resolve, reject) => {
    window.CESIUM_BASE_URL = `${CESIUM_CDN}/`

    const link = document.createElement('link')
    link.rel = 'stylesheet'
    link.href = `${CESIUM_CDN}/Widgets/widgets.css`
    document.head.appendChild(link)

    const script = document.createElement('script')
    script.src = `${CESIUM_CDN}/Cesium.js`
    script.async = true
    script.onload = () => resolve()
    script.onerror = () => {
      loadPromise = null
      reject(new Error('Failed to load CesiumJS'))
    }
    document.head.appendChild(script)
  })

  return loadPromise
}

export interface Swiss3DMapProps {
  track: GPSPoint[]
  className?: string
}

export function Swiss3DMap({ track, className }: Swiss3DMapProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading')

  useEffect(() => {
    if (!containerRef.current || track.length < 2) return
    const el = containerRef.current
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let viewer: any = null
    let destroyed = false

    ;(async () => {
      try {
        await loadCesium()
        if (destroyed) return

        const Cesium = window.Cesium

        // Disable Cesium ion (we use swisstopo + OSM — no ion token needed)
        Cesium.Ion.defaultAccessToken = ''

        // Hidden credit container (OSM attribution rendered manually)
        const creditDiv = document.createElement('div')
        creditDiv.style.cssText = 'position:absolute;bottom:0;right:0;visibility:hidden;height:0;overflow:hidden'

        viewer = new Cesium.Viewer(el, {
          timeline: false,
          animation: false,
          baseLayerPicker: false,
          geocoder: false,
          homeButton: false,
          sceneModePicker: false,
          navigationHelpButton: false,
          fullscreenButton: false,
          infoBox: false,
          selectionIndicator: false,
          creditContainer: creditDiv,
        })

        // Replace default imagery with OpenStreetMap tiles
        viewer.imageryLayers.removeAll()
        viewer.imageryLayers.add(
          new Cesium.ImageryLayer(
            new Cesium.UrlTemplateImageryProvider({
              url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              credit: new Cesium.Credit('© OpenStreetMap contributors'),
              maximumLevel: 19,
            })
          )
        )

        // Load swisstopo quantized-mesh terrain with fallback to ellipsoid
        try {
          const terrain = await Cesium.CesiumTerrainProvider.fromUrl(
            'https://3d.geo.admin.ch/1.0.0/ch.swisstopo.terrain.3d/default/20200520/4326/',
            { requestVertexNormals: true }
          )
          if (!destroyed) viewer.terrainProvider = terrain
        } catch {
          if (!destroyed) viewer.terrainProvider = new Cesium.EllipsoidTerrainProvider()
        }

        if (destroyed) { viewer.destroy(); return }

        // Use GPS altitude + 10 m clearance when available; otherwise clamp to terrain
        const hasAlt = track.some(p => p.altitude != null)
        const positions = track.map(p =>
          hasAlt
            ? Cesium.Cartesian3.fromDegrees(p.lng, p.lat, (p.altitude ?? 0) + 10)
            : Cesium.Cartesian3.fromDegrees(p.lng, p.lat)
        )

        // GPS track as glowing polyline
        viewer.entities.add({
          polyline: {
            positions,
            width: 4,
            clampToGround: !hasAlt,
            material: new Cesium.PolylineGlowMaterialProperty({
              glowPower: 0.25,
              color: Cesium.Color.fromCssColorString('#38bdf8'),
            }),
          },
        })

        // Start marker (green)
        viewer.entities.add({
          position: Cesium.Cartesian3.fromDegrees(
            track[0].lng, track[0].lat,
            hasAlt ? (track[0].altitude ?? 0) + 25 : undefined
          ),
          point: {
            pixelSize: 10,
            color: Cesium.Color.fromCssColorString('#22c55e'),
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 2,
            heightReference: hasAlt ? Cesium.HeightReference.NONE : Cesium.HeightReference.CLAMP_TO_GROUND,
          },
        })

        // End marker (red)
        const last = track[track.length - 1]
        viewer.entities.add({
          position: Cesium.Cartesian3.fromDegrees(
            last.lng, last.lat,
            hasAlt ? (last.altitude ?? 0) + 25 : undefined
          ),
          point: {
            pixelSize: 10,
            color: Cesium.Color.fromCssColorString('#ef4444'),
            outlineColor: Cesium.Color.WHITE,
            outlineWidth: 2,
            heightReference: hasAlt ? Cesium.HeightReference.NONE : Cesium.HeightReference.CLAMP_TO_GROUND,
          },
        })

        // Fly to track with 35° down-tilt and slight heading offset (mirrors iOS camera)
        await viewer.flyTo(viewer.entities, {
          duration: 0,
          offset: new Cesium.HeadingPitchRange(
            Cesium.Math.toRadians(20),   // heading — slight NNE rotation
            Cesium.Math.toRadians(-35),  // pitch  — 35° below horizon
            0,
          ),
        })

        if (!destroyed) setStatus('ready')
      } catch (err) {
        console.error('[Swiss3DMap]', err)
        if (!destroyed) setStatus('error')
      }
    })()

    return () => {
      destroyed = true
      if (viewer && !viewer.isDestroyed()) viewer.destroy()
    }
  }, [track])

  return (
    <div
      className={`rounded-lg overflow-hidden border border-border relative ${className ?? ''}`}
      style={{ height: 360 }}
    >
      <div ref={containerRef} style={{ height: '100%', width: '100%' }} />
      {status === 'loading' && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-slate-950/90 pointer-events-none">
          <div className="size-5 animate-spin rounded-full border-2 border-sky-400 border-t-transparent" />
          <p className="text-[11px] text-muted-foreground">Loading Swiss terrain…</p>
        </div>
      )}
      {status === 'error' && (
        <div className="absolute inset-0 flex items-center justify-center bg-card text-sm text-muted-foreground">
          3D terrain unavailable
        </div>
      )}
    </div>
  )
}
