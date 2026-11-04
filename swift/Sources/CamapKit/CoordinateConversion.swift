import Foundation

/// Approximate conversion for GCJ-02 coordinates in mainland China.
/// Longitude is x, latitude is y. This is not an official AMap service.
public enum CoordinateConversion {
  public enum Error: Swift.Error, Equatable {
    case invalidCoordinate
    case outsideSupportedArea
    case didNotConverge
  }

  /// Returns an estimated WGS-84 coordinate for a GCJ-02 coordinate.
  /// The commonly used geographic bounds are only a coarse guard, not an
  /// authoritative administrative boundary. Check actual alignment before use.
  public static func gcj02ToWGS84(_ coordinate: Point) throws -> Point {
    guard coordinate.x.isFinite, coordinate.y.isFinite,
      abs(coordinate.x) <= 180, abs(coordinate.y) <= 90
    else { throw Error.invalidCoordinate }
    guard supported(coordinate) else { throw Error.outsideSupportedArea }
    var guess = coordinate
    for _ in 0..<30 {
      let projected = forward(guess)
      let dx = projected.x - coordinate.x
      let dy = projected.y - coordinate.y
      if max(abs(dx), abs(dy)) < 1e-9 { return guess }
      guess = Point(guess.x - dx, guess.y - dy)
    }
    throw Error.didNotConverge
  }

  private static func supported(_ p: Point) -> Bool {
    (72.004...137.8347).contains(p.x) && (0.8293...55.8271).contains(p.y)
  }

  // Commonly used approximation of the forward offset, used solely for inversion.
  private static func forward(_ p: Point) -> Point {
    let x = p.x - 105, y = p.y - 35, pi = Double.pi
    var lat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
    lat += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
    lat += (20*sin(y*pi) + 40*sin(y*pi/3))*2/3
    lat += (160*sin(y*pi/12) + 320*sin(y*pi/30))*2/3
    var lon = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
    lon += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
    lon += (20*sin(x*pi) + 40*sin(x*pi/3))*2/3
    lon += (150*sin(x*pi/12) + 300*sin(x*pi/30))*2/3
    let a = 6_378_245.0, ee = 0.006693421622965943
    let rad = p.y*pi/180
    let magic = 1 - ee*sin(rad)*sin(rad)
    let root = sqrt(magic)
    lat = lat*180/((a*(1-ee))/(magic*root)*pi)
    lon = lon*180/(a/root*cos(rad)*pi)
    return Point(p.x + lon, p.y + lat)
  }
}
