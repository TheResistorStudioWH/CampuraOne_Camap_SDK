#if os(macOS)
import AppKit
import CamapKit
import CryptoKit
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct LandmarkSelection {
  var featureID: String
  var name: String
  var local: Point
  var coordinate: Point?
  var observedAt: Date?
  var observation: CalibrationLandmark? {
    coordinate.map { CalibrationLandmark(featureID: featureID, name: name, localPoint: local, mapCoordinate: $0) }
  }
}

@MainActor final class CalibrationSession: ObservableObject {
  @Published var document: CamapDocument?
  @Published var sourceHash = ""
  @Published var sourceLabel = "打开 CAMAP，或读取学校已发布地图"
  @Published var frameID = ""
  @Published var selections: [LandmarkSelection?] = [nil, nil, nil]
  @Published var active = 0
  @Published var armed = false
  @Published var selectedFeatureID = ""
  @Published var vertex = 0
  @Published var search = ""
  @Published var schoolID = "1"
  @Published var status = "先选择一个锚点，再选择两个分散的验证地标。"
  @Published var loading = false
  @Published var mapReady = false
  @Published var mapStatus = "Apple 底图尚未加载"
  @Published var satellite = true
  @Published var showDrawing = true
  @Published var showFitted = true
  @Published var zoomToken = UUID()
  @Published var maximumError = 10.0
  // Changing this source assumption clears all observations.
  @Published var sourceIsVerifiedWGS84 = false

  let roles = ["锚点（修正平移）", "验证点 1", "验证点 2"]
  var frame: SpatialFrame? { document?.frames.first { $0.id == frameID } }
  var features: [Feature] { document?.features.filter { $0.frameId == frameID } ?? [] }
  var filteredFeatures: [Feature] {
    features.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
      .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
  }
  var feature: Feature? { features.first { $0.id == selectedFeatureID } }
  var candidate: CamapKit.Binding? {
    guard let frame else { return nil }
    if let binding = frame.bindings["mapkit"] { return binding }
    guard let amap = frame.bindings["amap"] else { return nil }
    if sourceIsVerifiedWGS84 { return amap }
    guard let p = try? CoordinateConversion.gcj02ToWGS84(Point(amap.longitude, amap.latitude)) else { return nil }
    return CamapKit.Binding(longitude: p.x, latitude: p.y, rotation: amap.rotation)
  }
  var fitted: CamapKit.Binding? {
    guard let candidate, let anchor = selections[0]?.observation else { return nil }
    return try? TranslationCalibration.fit(candidate: candidate, anchor: anchor)
  }
  var displayBinding: CamapKit.Binding? { showFitted ? (fitted ?? candidate) : candidate }
  var report: TranslationCalibration.Report? {
    guard let fitted, let anchor = selections[0]?.observation else { return nil }
    return try? TranslationCalibration.validate(binding: fitted, anchor: anchor,
      checks: selections.dropFirst().compactMap { $0?.observation }, maximumErrorMeters: maximumError)
  }
  var canExport: Bool { report?.accepted == true && selections.allSatisfy { $0?.observedAt != nil } }

  func install(_ document: CamapDocument, label: String, hash: String) throws {
    try Camap.validate(document)
    guard !document.frames.isEmpty else { throw CamapError.invalid("地图没有坐标区域") }
    self.document = document
    sourceLabel = label
    sourceHash = hash
    frameID = document.frames[0].id
    reset()
    status = "已载入 \(document.features.count) 个对象。近似转换仅用于初始候选；请在 Apple 底图点真实对应位置。"
  }
  func reset() {
    selections = [nil, nil, nil]
    active = 0
    armed = false
    selectedFeatureID = features.first(where: { $0.name == "卫生所门" })?.id
      ?? features.first(where: { $0.geometry.points.count == 1 })?.id ?? features.first?.id ?? ""
    vertex = 0
    zoomToken = UUID()
  }
  func openFile() {
    let picker = NSOpenPanel()
    picker.allowedContentTypes = [UTType(filenameExtension: "camap") ?? .data]
    picker.canChooseDirectories = false
    if picker.runModal() == .OK, let url = picker.url {
      do {
        let doc = try Camap.read(from: url)
        let bytes = try Camap.encode(doc)
        try install(doc, label: url.lastPathComponent, hash: hash(bytes))
      } catch { status = "打开失败：\(error.localizedDescription)" }
    }
  }
  func loadPublished() {
    guard let school = Int(schoolID), school > 0 else { status = "请输入有效学校 ID"; return }
    loading = true
    Task {
      defer { loading = false }
      do {
        let url = URL(string: "https://campura.one/api/download/campus_map.php?schoolID=\(school)&format=camap")!
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
          throw CamapError.invalid("服务器未返回已发布地图")
        }
        try install(Camap.decode(bytes), label: "学校 \(school) · 已发布地图", hash: hash(bytes))
      } catch { status = "读取失败：\(error.localizedDescription)" }
    }
  }
  private func hash(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
  func selectLocal() {
    guard let feature else { return }
    let ps = feature.geometry.points
    let local = vertex < ps.count ? ps[max(0, vertex)] :
      Point(ps.map(\.x).reduce(0,+) / Double(ps.count), ps.map(\.y).reduce(0,+) / Double(ps.count))
    selections[active] = LandmarkSelection(featureID: feature.id,
      name: feature.name + (ps.count == 1 ? "" : (vertex < ps.count ? " · 顶点 \(vertex + 1)" : " · 顶点均值中心")),
      local: local)
    armed = false
    status = "已选 \(roles[active])：\(selections[active]!.name)。请在 Apple 底图找到同一位置。"
  }
  func record(_ coordinate: CLLocationCoordinate2D) {
    guard armed, mapReady, selections[active] != nil,
      CLLocationCoordinate2DIsValid(coordinate), abs(coordinate.latitude) <= 80 else { return }
    selections[active]?.coordinate = Point(coordinate.longitude, coordinate.latitude)
    selections[active]?.observedAt = Date()
    armed = false
    if active == 0 && fitted == nil {
      status = "锚点无法拟合：请核对源坐标系及同名位置（候选与观测不能相差超过 2 公里）。"
    } else {
      status = "\(roles[active]) 已记录。验证点只检查误差，不参与拟合。"
    }
  }
  func export() {
    guard canExport, let doc = document, let candidate,
      let anchor = selections[0]?.observation, let report else { return }
    do {
      let result = try TranslationCalibration.applying(candidate: candidate, anchor: anchor,
        checks: selections.dropFirst().compactMap { $0?.observation },
        to: doc, frameID: frameID, maximumErrorMeters: maximumError)
      let picker = NSSavePanel()
      picker.allowedContentTypes = [UTType(filenameExtension: "camap") ?? .data]
      picker.nameFieldStringValue = "校园地图-MapKit校准.camap"
      guard picker.runModal() == .OK, let url = picker.url else { return }
      // Never overwrite the source implicitly: OS save panel determines destination.
      let bytes = try Camap.encode(result)
      struct Evidence: Encodable {
        let method = "MapKit translation-only; independent holdout checks"
        let coordinateSource = "MKMapView.convert(_:toCoordinateFrom:)"
        let sourceLabel: String
        let sourceArchiveOrReencodedSHA256: String
        let sourceMasterID: String?
        let sourceBaseRevision: Int?
        let frameID: String
        let sourceFrame: SpatialFrame
        let candidate: CamapKit.Binding
        let sourceIsVerifiedWGS84: Bool
        let observationsAt: [Date]
        let report: TranslationCalibration.Report
        let outputArchiveSHA256: String
        let createdAt: Date
        let visualVerificationOnly = true
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let evidence = Evidence(sourceLabel: sourceLabel, sourceArchiveOrReencodedSHA256: sourceHash,
        sourceMasterID: doc.masterId, sourceBaseRevision: doc.baseRevision, frameID: frameID,
        sourceFrame: frame!, candidate: candidate, sourceIsVerifiedWGS84: sourceIsVerifiedWGS84,
        observationsAt: selections.compactMap { $0?.observedAt }, report: report,
        outputArchiveSHA256: hash(bytes), createdAt: Date())
      // Choose the report destination independently: never overwrite an existing report silently.
      let reportPicker = NSSavePanel()
      reportPicker.allowedContentTypes = [.json]
      reportPicker.directoryURL = url.deletingLastPathComponent()
      reportPicker.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "-校准记录.json"
      guard reportPicker.runModal() == .OK, let evidenceURL = reportPicker.url else {
        status = "未选择校准记录保存位置，本次未导出地图"; return
      }
      try encoder.encode(evidence).write(to: evidenceURL, options: .atomic)
      try bytes.write(to: url, options: .atomic)
      status = "已导出独立 mapkit 绑定和校准记录；原点以外的地图几何、主图 ID 和发布基准均保留。尚未发布。"
    } catch { status = "导出失败：\(error.localizedDescription)" }
  }
}
#endif
