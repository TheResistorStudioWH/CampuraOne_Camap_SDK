import XCTest
@testable import CamapKit

final class TranslationCalibrationTests: XCTestCase {
  let truth = Binding(longitude: 114.392, latitude: 30.372, rotation: 17)
  var candidate: Binding { Binding(longitude: truth.longitude + 0.003, latitude: truth.latitude - 0.002, rotation: truth.rotation) }
  func landmark(_ id: String, _ p: Point, binding: Binding? = nil) -> CalibrationLandmark {
    CalibrationLandmark(featureID: id, name: id, localPoint: p, mapCoordinate: (binding ?? truth).project(p))
  }
  func testNonzeroAnchorFitsTranslationExactlyAndChecksAreIndependent() throws {
    let anchor = landmark("a", Point(-200, 90))
    let fitted = try TranslationCalibration.fit(candidate: candidate, anchor: anchor)
    XCTAssertEqual(fitted.longitude, truth.longitude, accuracy: 1e-10)
    XCTAssertEqual(fitted.latitude, truth.latitude, accuracy: 1e-10)
    XCTAssertEqual(fitted.rotation, candidate.rotation)
    let checks = [landmark("b", Point(40, 10)), landmark("c", Point(-100, 350))]
    let report = try TranslationCalibration.validate(binding: fitted, anchor: anchor, checks: checks)
    XCTAssertTrue(report.accepted, report.issues.joined(separator: ", "))
    XCTAssertLessThan(report.checks.map(\.errorMeters).max()!, 0.001)
    let wrong = Binding(longitude: truth.longitude, latitude: truth.latitude, rotation: 32)
    let bad = try TranslationCalibration.validate(binding: fitted, anchor: anchor,
      checks: [landmark("b", Point(40, 10), binding: wrong), landmark("c", Point(-100, 350))])
    XCTAssertFalse(bad.accepted)
    XCTAssertEqual(try TranslationCalibration.fit(candidate: candidate, anchor: anchor), fitted)
  }
  func testMissingNearbyCollinearOrDuplicateChecksCannotPass() throws {
    let a = landmark("a", Point(0, 0))
    for checks in [
      [], [landmark("b", Point(100, 0))],
      [landmark("b", Point(10, 0)), landmark("c", Point(0, 200))],
      [landmark("b", Point(100, 0)), landmark("c", Point(200, 0))],
      [landmark("a", Point(200, 0)), landmark("c", Point(0, 200))]
    ] {
      XCTAssertFalse(try TranslationCalibration.validate(binding: truth, anchor: a, checks: checks).accepted)
    }
    XCTAssertThrowsError(try TranslationCalibration.fit(candidate: candidate,
      anchor: CalibrationLandmark(featureID: "a", name: "", localPoint: Point(.nan, 0), mapCoordinate: Point(114, 30))))
    XCTAssertThrowsError(try TranslationCalibration.fit(candidate: candidate,
      anchor: CalibrationLandmark(featureID: "a", name: "", localPoint: Point(0, 0), mapCoordinate: Point(120, 30))))
  }
  func testSavePreservesGeometryAMapAndPublicationIdentityAndRejectsStalePoints() throws {
    let frame = SpatialFrame(name: "校区", bindings: ["amap": candidate])
    let features = [Point(0, 0), Point(200, 0), Point(0, 200)].enumerated().map {
      Feature(frameId: frame.id, kind: "poi", name: "地标\($0.offset)", geometry: .point($0.element))
    }
    let doc = CamapDocument(masterId: UUID().uuidString.lowercased(), baseRevision: 1,
      frames: [frame], features: features)
    let pairs = features.map { landmark($0.id, $0.geometry.points[0]) }
    let saved = try TranslationCalibration.applying(candidate: candidate, anchor: pairs[0],
      checks: Array(pairs.dropFirst()), to: doc, frameID: frame.id)
    XCTAssertEqual(saved.features, doc.features)
    XCTAssertEqual(saved.masterId, doc.masterId)
    XCTAssertEqual(saved.baseRevision, doc.baseRevision)
    XCTAssertEqual(saved.frames[0].bindings["amap"], frame.bindings["amap"])
    XCTAssertEqual(saved.frames[0].revision, frame.revision + 1)
    XCTAssertEqual(saved.frames[0].bindings["mapkit"]!.rotation, candidate.rotation)
    XCTAssertEqual(try Camap.decode(Camap.encode(saved)), saved)
    let stale = landmark(pairs[0].featureID, Point(1, 1))
    XCTAssertThrowsError(try TranslationCalibration.applying(candidate: candidate, anchor: stale,
      checks: Array(pairs.dropFirst()), to: doc, frameID: frame.id))
  }
}
