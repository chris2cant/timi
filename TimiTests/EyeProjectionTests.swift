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

  func testPointerAtCenterKeepsRestPitchAndNoYaw() {
    let gaze = EyeProjection.gaze(towardOffset: CGVector(dx: 0, dy: 0))

    XCTAssertEqual(gaze.yaw, 0, accuracy: 0.0001)
    XCTAssertEqual(gaze.pitch, EyeProjection.trackingRestPitch, accuracy: 0.0001)
  }

  func testPointerSideDrivesYawSymmetrically() {
    let right = EyeProjection.gaze(towardOffset: CGVector(dx: 200, dy: 0))
    let left = EyeProjection.gaze(towardOffset: CGVector(dx: -200, dy: 0))

    XCTAssertGreaterThan(right.yaw, 0)
    XCTAssertEqual(right.yaw, -left.yaw, accuracy: 0.0001)
  }

  func testPointerAboveRaisesPitch() {
    let above = EyeProjection.gaze(towardOffset: CGVector(dx: 0, dy: 200))
    let below = EyeProjection.gaze(towardOffset: CGVector(dx: 0, dy: -200))

    XCTAssertGreaterThan(above.pitch, below.pitch)
  }

  func testFarPointerIsBounded() {
    let gaze = EyeProjection.gaze(towardOffset: CGVector(dx: 1e6, dy: -1e6))

    XCTAssertLessThanOrEqual(gaze.yaw, EyeProjection.maxTrackingYaw)
    XCTAssertGreaterThanOrEqual(
      gaze.pitch,
      EyeProjection.trackingRestPitch - EyeProjection.maxTrackingPitch
    )
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
