import Foundation

/// A manually identified correspondence. Map coordinates come directly from
/// MapKit, never from converting the AMap coordinate of this same landmark.
public struct CalibrationLandmark: Codable, Sendable, Equatable {
  public let featureID: String
  public let name: String
  public let localPoint: Point
  public let mapCoordinate: Point
  public init(featureID: String, name: String, localPoint: Point, mapCoordinate: Point) {
    self.featureID = featureID
    self.name = name
    self.localPoint = localPoint
    self.mapCoordinate = mapCoordinate
  }
}

public enum TranslationCalibration {
  public enum Failure: Swift.Error, Equatable {
    case invalidInput, anchorTooFar, validationFailed, staleLandmark
  }
  public struct Residual: Codable, Sendable {
    public let landmark: CalibrationLandmark
    public let predicted: Point
    public let errorMeters: Double
  }
  public struct Report: Codable, Sendable {
    public let binding: Binding
    public let anchor: CalibrationLandmark
    public let checks: [Residual]
    public let maximumErrorMeters: Double
    public let minimumSeparationMeters: Double
    public let triangleHeightMeters: Double
    public let issues: [String]
    public var accepted: Bool { issues.isEmpty }
  }
  private static let radius = 6_378_137.0, degrees = Double.pi / 180
  private static func coordinateIsValid(_ p: Point) -> Bool {
    p.x.isFinite && p.y.isFinite && abs(p.x) <= 180 && abs(p.y) <= 80
  }
  private static func valid(_ b: Binding) -> Bool {
    coordinateIsValid(Point(b.longitude, b.latitude)) && b.rotation.isFinite
  }
  private static func valid(_ p: CalibrationLandmark) -> Bool {
    !p.featureID.isEmpty && p.localPoint.x.isFinite && p.localPoint.y.isFinite
      && hypot(p.localPoint.x, p.localPoint.y) <= 10_000 && coordinateIsValid(p.mapCoordinate)
  }
  public static func distanceMeters(_ a: Point, _ b: Point) -> Double {
    let lat = (b.y - a.y) * degrees, lon = (b.x - a.x) * degrees
    let h = pow(sin(lat / 2), 2)
      + cos(a.y * degrees) * cos(b.y * degrees) * pow(sin(lon / 2), 2)
    return 2 * radius * asin(sqrt(max(0, min(1, h))))
  }

  /// Fit only an origin. The candidate's rotation is retained exactly.
  /// Check points never participate in fitting.
  public static func fit(candidate: Binding, anchor: CalibrationLandmark) throws -> Binding {
    guard valid(candidate), valid(anchor) else { throw Failure.invalidInput }
    guard distanceMeters(candidate.project(anchor.localPoint), anchor.mapCoordinate) <= 2_000
    else { throw Failure.anchorTooFar }
    let angle = candidate.rotation * degrees
    let east = anchor.localPoint.x * cos(angle) - anchor.localPoint.y * sin(angle)
    let north = anchor.localPoint.x * sin(angle) + anchor.localPoint.y * cos(angle)
    func mercator(_ lat: Double) -> Double { log(tan(.pi / 4 + lat * degrees / 2)) }
    let target = mercator(anchor.mapCoordinate.y)
    func residual(_ lat: Double) -> Double {
      mercator(lat) + north / (radius * cos(lat * degrees)) - target
    }
    // Solve the actual SDK projection, including cos(lat0), rather than add
    // latitude/longitude deltas which fail for nonzero local anchor positions.
    var low = max(-80, anchor.mapCoordinate.y - 1)
    var high = min(80, anchor.mapCoordinate.y + 1)
    guard residual(low) <= 0, residual(high) >= 0 else { throw Failure.invalidInput }
    for _ in 0..<70 {
      let mid = (low + high) / 2
      if residual(mid) < 0 { low = mid } else { high = mid }
    }
    let latitude = (low + high) / 2
    let longitude = anchor.mapCoordinate.x - east / (radius * cos(latitude * degrees) * degrees)
    let binding = Binding(longitude: longitude, latitude: latitude, rotation: candidate.rotation)
    guard valid(binding) else { throw Failure.invalidInput }
    return binding
  }

  /// Default acceptance: two different, dispersed check landmarks, <=10 m
  /// visual residual each. Residuals do not assert GPS/survey accuracy.
  public static func validate(
    binding: Binding, anchor: CalibrationLandmark, checks: [CalibrationLandmark],
    maximumErrorMeters: Double = 10
  ) throws -> Report {
    guard valid(binding), valid(anchor), checks.allSatisfy(valid),
      maximumErrorMeters.isFinite, (1...30).contains(maximumErrorMeters)
    else { throw Failure.invalidInput }
    let residuals = checks.map {
      Residual(landmark: $0, predicted: binding.project($0.localPoint),
        errorMeters: distanceMeters(binding.project($0.localPoint), $0.mapCoordinate))
    }
    let points = [anchor] + checks
    var issues: [String] = []
    if checks.count < 2 { issues.append("还需两个独立验证点") }
    if Set(points.map(\.featureID)).count != points.count { issues.append("请使用不同的地标") }
    var separation = Double.greatestFiniteMagnitude
    var triangleHeight = 0.0
    for i in points.indices {
      for j in points.indices where j > i {
        separation = min(separation, hypot(
          points[i].localPoint.x - points[j].localPoint.x,
          points[i].localPoint.y - points[j].localPoint.y))
      }
    }
    if points.count < 2 { separation = 0 }
    if checks.count >= 2 {
      for i in checks.indices {
        for j in checks.indices where j > i {
          let a = anchor.localPoint, b = checks[i].localPoint, c = checks[j].localPoint
          let cross = abs((b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x))
          let longest = max(hypot(b.x-a.x, b.y-a.y),
            max(hypot(c.x-a.x, c.y-a.y), hypot(c.x-b.x, c.y-b.y)))
          if longest > 0 { triangleHeight = max(triangleHeight, cross / longest) }
        }
      }
    }
    if separation < 50 { issues.append("三个点需两两相隔至少 50 米") }
    if triangleHeight < 20 { issues.append("验证点需分布在不同方向，三角形高度至少 20 米") }
    if distanceMeters(binding.project(anchor.localPoint), anchor.mapCoordinate) > 0.01 {
      issues.append("绑定未通过所选锚点")
    }
    if residuals.contains(where: { $0.errorMeters > maximumErrorMeters }) {
      issues.append("验证误差超限；请核对同名点，暂不自动改变旋转或比例")
    }
    return Report(binding: binding, anchor: anchor, checks: residuals,
      maximumErrorMeters: maximumErrorMeters, minimumSeparationMeters: separation,
      triangleHeightMeters: triangleHeight, issues: issues)
  }

  /// Save only after independent verification. All geometry and other provider
  /// bindings remain unchanged; stale/unknown landmark references are rejected.
  public static func applying(
    candidate: Binding, anchor: CalibrationLandmark, checks: [CalibrationLandmark],
    to document: CamapDocument, frameID: String, maximumErrorMeters: Double = 10
  ) throws -> CamapDocument {
    try Camap.validate(document)
    guard let index = document.frames.firstIndex(where: { $0.id == frameID }),
      document.frames[index].revision < Int.max
    else { throw Failure.invalidInput }
    for landmark in [anchor] + checks {
      guard let feature = document.features.first(where: {
        $0.id == landmark.featureID && $0.frameId == frameID
      }) else { throw Failure.staleLandmark }
      let vertices = feature.geometry.points
      let center = Point(vertices.map(\.x).reduce(0,+) / Double(vertices.count),
        vertices.map(\.y).reduce(0,+) / Double(vertices.count))
      guard (vertices + [center]).contains(where: {
        hypot($0.x - landmark.localPoint.x, $0.y - landmark.localPoint.y) < 1e-6
      }) else { throw Failure.staleLandmark }
    }
    let binding = try fit(candidate: candidate, anchor: anchor)
    let report = try validate(binding: binding, anchor: anchor, checks: checks,
      maximumErrorMeters: maximumErrorMeters)
    guard report.accepted else { throw Failure.validationFailed }
    var result = document
    result.frames[index].bindings["mapkit"] = binding
    result.frames[index].revision += 1
    try Camap.validate(result)
    return result
  }
}
