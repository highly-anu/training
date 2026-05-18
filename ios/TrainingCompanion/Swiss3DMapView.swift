import SwiftUI
import WebKit

// MARK: - Switzerland bounding-box helper

func isInSwitzerland(_ points: [GPSPoint]) -> Bool {
    guard let p = points.first else { return false }
    return (45.8...47.8).contains(p.lat) && (5.9...10.5).contains(p.lng)
}

// MARK: - Swiss3DMapView

/// Renders a GPS track in 3D using CesiumJS + swisstopo terrain tiles.
/// Only intended for tracks located within Switzerland.
struct Swiss3DMapView: UIViewRepresentable {
    let points: [GPSPoint]

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(buildHTML(), baseURL: nil)
    }

    // MARK: - HTML generation

    private func buildHTML() -> String {
        let coordsJSON = points.map { p -> String in
            let altStr = p.altitude.map { String($0) } ?? "null"
            return "{\"lat\":\(p.lat),\"lon\":\(p.lng),\"alt\":\(altStr)}"
        }.joined(separator: ",")

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
          <script src="https://cesium.com/downloads/cesiumjs/releases/1.113/Build/Cesium/Cesium.js"></script>
          <link href="https://cesium.com/downloads/cesiumjs/releases/1.113/Build/Cesium/Widgets/widgets.css" rel="stylesheet">
          <style>
            * { margin:0; padding:0; box-sizing:border-box; }
            html, body, #cesiumContainer { width:100%; height:100%; overflow:hidden; background:#151515; }
            .cesium-credit-expand-link,
            .cesium-credit-logoContainer,
            .cesium-credit-textContainer { display:none !important; }
          </style>
        </head>
        <body>
          <div id="cesiumContainer"></div>
          <script>
          const TRACK = [\(coordsJSON)];

          (async () => {
            // No Cesium Ion assets used — swisstopo tiles only.
            Cesium.Ion.defaultAccessToken = '';

            // Terrain: swisstopo 3D (Quantized Mesh via 3d.geo.admin.ch)
            let terrainProvider;
            try {
              terrainProvider = await Cesium.CesiumTerrainProvider.fromUrl(
                'https://3d.geo.admin.ch/1.0.0/ch.swisstopo.terrain.3d/default/20200520/4326/'
              );
            } catch (e) {
              terrainProvider = new Cesium.EllipsoidTerrainProvider();
            }

            const viewer = new Cesium.Viewer('cesiumContainer', {
              terrainProvider,
              imageryProvider: new Cesium.UrlTemplateImageryProvider({
                url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                maximumLevel: 19,
                credit: '© OpenStreetMap contributors'
              }),
              baseLayerPicker:       false,
              geocoder:              false,
              homeButton:            false,
              sceneModePicker:       false,
              navigationHelpButton:  false,
              animation:             false,
              timeline:              false,
              fullscreenButton:      false,
              infoBox:               false,
              selectionIndicator:    false,
            });

            viewer.scene.skyBox.show = false;
            viewer.scene.skyAtmosphere.show = false;
            viewer.scene.fog.enabled = false;

            if (TRACK.length < 2) return;

            // Build position array — use GPS altitude + 10 m clearance above terrain
            const degHeights = TRACK.flatMap(p => [
              p.lon,
              p.lat,
              (p.alt !== null ? p.alt : 1000) + 10
            ]);
            const positions = Cesium.Cartesian3.fromDegreesArrayHeights(degHeights);

            // Track polyline
            viewer.entities.add({
              polyline: {
                positions,
                width: 4,
                material: Cesium.Color.fromCssColorString('#3b82f6'),
                arcType: Cesium.ArcType.NONE,
                clampToGround: false
              }
            });

            // Start marker (green)
            viewer.entities.add({
              position: positions[0],
              point: {
                pixelSize: 12,
                color: Cesium.Color.fromCssColorString('#22c55e'),
                outlineColor: Cesium.Color.WHITE,
                outlineWidth: 2,
                disableDepthTestDistance: Number.POSITIVE_INFINITY
              }
            });

            // End marker (red)
            viewer.entities.add({
              position: positions[positions.length - 1],
              point: {
                pixelSize: 12,
                color: Cesium.Color.fromCssColorString('#ef4444'),
                outlineColor: Cesium.Color.WHITE,
                outlineWidth: 2,
                disableDepthTestDistance: Number.POSITIVE_INFINITY
              }
            });

            // Camera: view the bounding sphere at a 35° downward tilt
            const sphere = Cesium.BoundingSphere.fromPoints(positions);
            const offset = new Cesium.HeadingPitchRange(
              Cesium.Math.toRadians(20),
              Cesium.Math.toRadians(-35),
              sphere.radius * 5
            );
            viewer.camera.viewBoundingSphere(sphere, offset);
          })();
          </script>
        </body>
        </html>
        """
    }
}
