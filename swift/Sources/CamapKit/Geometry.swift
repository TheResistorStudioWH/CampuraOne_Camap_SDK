import Foundation

public struct Point: Codable, Sendable, Equatable {
  public var x: Double
  public var y: Double
  public init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.singleValueContainer().decode([Double].self)
    guard values.count == 2 else { throw CamapError.invalid("Point needs two coordinates") }
    self.init(values[0], values[1])
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    try c.encode([x, y])
  }
}
public enum Geometry: Codable, Sendable, Equatable {
  case point(Point)
  case line([Point])
  case polygon([Point])
  enum Keys: String, CodingKey { case type, coordinates }
  public var points: [Point] {
    switch self {
    case .point(let p): return [p]
    case .line(let p), .polygon(let p): return p
    }
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    switch try c.decode(String.self, forKey: .type) {
    case "point": self = .point(try c.decode(Point.self, forKey: .coordinates))
    case "line": self = .line(try c.decode([Point].self, forKey: .coordinates))
    case "polygon": self = .polygon(try c.decode([Point].self, forKey: .coordinates))
    default: throw CamapError.invalid("Unknown geometry")
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    switch self {
    case .point(let p):
      try c.encode("point", forKey: .type)
      try c.encode(p, forKey: .coordinates)
    case .line(let p):
      try c.encode("line", forKey: .type)
      try c.encode(p, forKey: .coordinates)
    case .polygon(let p):
      try c.encode("polygon", forKey: .type)
      try c.encode(p, forKey: .coordinates)
    }
  }
}
extension Binding {
  public func project(_ p: Point) -> Point {
    let d = Double.pi / 180
    let a = rotation * d
    let c = cos(latitude * d)
    let x = p.x * cos(a) - p.y * sin(a)
    let y = p.x * sin(a) + p.y * cos(a)
    return Point(
      longitude + x / (6_378_137 * c * d),
      (2 * atan(exp(log(tan(.pi / 4 + latitude * d / 2)) + y / (6_378_137 * c))) - Double.pi / 2)
        / d)
  }
  public func unproject(_ p: Point) -> Point {
    let d = Double.pi / 180
    let c = cos(latitude * d)
    let a = -rotation * d
    let x = (p.x - longitude) * 6_378_137 * c * d
    let y = (log(tan(.pi / 4 + p.y * d / 2)) - log(tan(.pi / 4 + latitude * d / 2))) * 6_378_137 * c
    return Point(x * cos(a) - y * sin(a), x * sin(a) + y * cos(a))
  }
}
