#if os(macOS)
import AppKit
import CamapKit
import MapKit
import SwiftUI

struct AppleCalibrationMap: NSViewRepresentable {
  @ObservedObject var session: CalibrationSession
  func makeCoordinator() -> Coordinator { Coordinator(session: session) }
  func makeNSView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.delegate = context.coordinator
    map.isPitchEnabled = false
    map.isRotateEnabled = false
    map.showsZoomControls = true
    map.showsUserLocation = false
    let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick(_:)))
    click.delaysPrimaryMouseButtonEvents = false
    map.addGestureRecognizer(click)
    return map
  }
  func updateNSView(_ map: MKMapView, context: Context) {
    context.coordinator.session = session
    let mapType: MKMapType = session.satellite ? .hybrid : .standard
    if map.mapType != mapType { map.mapType = mapType }
    guard let binding = session.displayBinding else { return }
    if context.coordinator.zoomToken != session.zoomToken {
      context.coordinator.zoomToken = session.zoomToken
      let ps = session.features.flatMap(\.geometry.points).map { binding.project($0) }
      let xs = ps.map(\.x), ys = ps.map(\.y)
      let lon = ((xs.min() ?? binding.longitude) + (xs.max() ?? binding.longitude))/2
      let lat = ((ys.min() ?? binding.latitude) + (ys.max() ?? binding.latitude))/2
      map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        span: MKCoordinateSpan(latitudeDelta: max(0.006,(ys.max() ?? lat)-(ys.min() ?? lat))*1.3,
          longitudeDelta: max(0.006,(xs.max() ?? lon)-(xs.min() ?? lon))*1.3)), animated: false)
    }
    let signature = [
      session.sourceHash, session.frameID, session.selectedFeatureID, String(session.vertex),
      String(binding.longitude), String(binding.latitude), String(binding.rotation),
      String(session.showDrawing),
      session.selections.map { pair in
        guard let pair else { return "" }
        return "\(pair.featureID):\(pair.local.x),\(pair.local.y):\(pair.coordinate?.x ?? 0),\(pair.coordinate?.y ?? 0)"
      }.joined(separator: "|"),
    ].joined(separator: ";")
    guard context.coordinator.renderSignature != signature else { return }
    context.coordinator.renderSignature = signature
    map.removeOverlays(map.overlays)
    map.removeAnnotations(map.annotations)
    func coordinate(_ p: Point) -> CLLocationCoordinate2D {
      let q = binding.project(p)
      return CLLocationCoordinate2D(latitude: q.y, longitude: q.x)
    }
    if session.showDrawing {
      for feature in session.features {
        var ps = feature.geometry.points.map(coordinate)
        let selected = feature.id == session.selectedFeatureID
        if ps.count > 2, case .polygon = feature.geometry {
          let polygon = MKPolygon(coordinates: &ps, count: ps.count)
          polygon.title = selected ? "selected" : "drawing"
          map.addOverlay(polygon)
        } else if ps.count > 1 {
          let line = MKPolyline(coordinates: &ps, count: ps.count)
          line.title = selected ? "selected" : "drawing"
          map.addOverlay(line)
        }
      }
      if let feature = session.feature {
        let ps = feature.geometry.points
        let p = session.vertex < ps.count ? ps[max(0,session.vertex)] :
          Point(ps.map(\.x).reduce(0,+)/Double(ps.count), ps.map(\.y).reduce(0,+)/Double(ps.count))
        let current = MKPointAnnotation()
        current.title = "当前候选 · \(feature.name)"
        current.coordinate = coordinate(p)
        map.addAnnotation(current)
      }
    }
    for i in 0..<3 {
      guard let selection = session.selections[i] else { continue }
      let predicted = coordinate(selection.local)
      let annotation = MKPointAnnotation()
      annotation.title = "预测 \(i+1) · \(selection.name)"
      annotation.coordinate = predicted
      map.addAnnotation(annotation)
      if let observed = selection.coordinate {
        let actual = MKPointAnnotation()
        actual.title = "观测 \(i+1) · \(selection.name)"
        actual.coordinate = CLLocationCoordinate2D(latitude: observed.y, longitude: observed.x)
        map.addAnnotation(actual)
        var linePoints = [predicted, actual.coordinate]
        let residual = MKPolyline(coordinates: &linePoints, count: 2)
        residual.title = "residual"
        map.addOverlay(residual)
      }
    }
  }
  final class Coordinator: NSObject, MKMapViewDelegate {
    var session: CalibrationSession
    var zoomToken: UUID?
    var renderSignature = ""
    init(session: CalibrationSession) { self.session = session }
    @objc func pick(_ recognizer: NSClickGestureRecognizer) {
      guard let map = recognizer.view as? MKMapView, recognizer.state == .ended else { return }
      session.record(map.convert(recognizer.location(in: map), toCoordinateFrom: map))
    }
    func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
      DispatchQueue.main.async {
        self.session.mapStatus = "正在加载 Apple 底图…"
        self.session.mapReady = false
        self.session.armed = false
      }
    }
    func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
      DispatchQueue.main.async { self.session.mapStatus = "Apple 底图已加载"; self.session.mapReady = true }
    }
    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
      if fullyRendered {
        DispatchQueue.main.async { self.session.mapStatus = "Apple 底图已绘制"; self.session.mapReady = true }
      }
    }
    func mapView(_ mapView: MKMapView, didFailLoadingMapWithError error: Swift.Error) {
      DispatchQueue.main.async { self.session.mapStatus = "Apple 底图加载失败，请检查网络"; self.session.mapReady = false }
    }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
      let color: NSColor = overlay.title == "selected" ? .systemOrange : (overlay.title == "residual" ? .systemRed : .systemTeal)
      if let polygon = overlay as? MKPolygon {
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.strokeColor = color
        renderer.fillColor = color.withAlphaComponent(0.08)
        renderer.lineWidth = 1.5
        return renderer
      }
      let renderer = MKPolylineRenderer(overlay: overlay)
      renderer.strokeColor = color
      renderer.lineWidth = 2
      return renderer
    }
  }
}
#endif
