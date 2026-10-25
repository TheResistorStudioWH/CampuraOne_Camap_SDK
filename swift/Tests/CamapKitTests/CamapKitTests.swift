import XCTest

@testable import CamapKit

final class CamapKitTests: XCTestCase {
  func testRoundtripAndCorruption() throws {
    let url = Bundle.module.url(
      forResource: "demo", withExtension: "camap", subdirectory: "Fixtures")!
    let data = try Data(contentsOf: url)
    let d = try Camap.decode(data)
    XCTAssertEqual(d.features.count, 5)
    if let folder = ProcessInfo.processInfo.environment["CAMAP_INTEROP_DIR"] {
      try Camap.write(d, to: URL(fileURLWithPath: folder).appendingPathComponent("swift.camap"))
    }
    XCTAssertEqual(try Camap.decode(Camap.encode(d)), d)
    var bad = data
    bad[100] ^= 1
    XCTAssertThrowsError(try Camap.decode(bad))
  }
  func testCoordinates() {
    let b = Binding(longitude: 114, latitude: 30, rotation: 35)
    let p = Point(50, -20)
    let back = b.unproject(b.project(p))
    XCTAssertEqual(p.x, back.x, accuracy: 0.0001)
    XCTAssertEqual(p.y, back.y, accuracy: 0.0001)
  }
  func testInvalidReference() throws {
    var d = try Camap.read(
      from: Bundle.module.url(
        forResource: "demo", withExtension: "camap", subdirectory: "Fixtures")!)
    d.nodes = []
    XCTAssertThrowsError(try Camap.validate(d))
  }
}
