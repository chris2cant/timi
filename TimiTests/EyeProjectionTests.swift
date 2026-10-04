import XCTest

@testable import Timi

final class EyeProjectionTests: XCTestCase {
  func testCenteredGazeProjectsSymmetricalEyes() {
    let eyes = EyeProjection.eyes(
      for: HeadGaze(yaw: 0, pitch: 0, roll: 0),
      radius: 100
    )

    XCTAssertEqual(eyes[0].x, -eyes[1].x, accuracy: 0.0001)
    XCTAssertEqual(eyes[0].depth, eyes[1].depth, accuracy: 0.0001)
    XCTAssertEqual(eyes[0].a, eyes[1].a, accuracy: 0.0001)
  }

  func testEyeNearSphereEdgeIsCompressedByDepth() {
    let eyes = EyeProjection.eyes(
      for: HeadGaze(yaw: 32, pitch: 0, roll: 0),
      radius: 100
    )

    XCTAssertGreaterThan(eyes[0].depth, eyes[1].depth)
    XCTAssertGreaterThan(abs(eyes[0].a), abs(eyes[1].a))
  }

  func testTurningToOtherSideReversesPerspective() {
    let lookingRight = EyeProjection.eyes(
      for: HeadGaze(yaw: 32, pitch: 0, roll: 0),
      radius: 100
    )
    let lookingLeft = EyeProjection.eyes(
      for: HeadGaze(yaw: -32, pitch: 0, roll: 0),
      radius: 100
    )

    XCTAssertEqual(lookingRight[0].depth, lookingLeft[1].depth, accuracy: 0.0001)
    XCTAssertEqual(lookingRight[1].depth, lookingLeft[0].depth, accuracy: 0.0001)
  }
}
