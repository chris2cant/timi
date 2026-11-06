import XCTest

@testable import Timi

final class EyeExpressionTests: XCTestCase {
  private let baseSize = CGSize(width: 10, height: 20)

  func testSpringSettlesOnTarget() {
    var spring = ExpressionSpring(.neutral)
    let target = EyeMood.surprised.expression

    spring.step(toward: target, dt: 2)

    XCTAssertTrue(spring.isSettled(at: target))
    XCTAssertEqual(spring.current.left.width, target.left.width, accuracy: 0.002)
  }

  func testSpringIsHalfwayAfterAShortStep() {
    var spring = ExpressionSpring(.neutral)
    var target = FaceExpression.neutral
    target.left.upperLid = 1

    spring.step(toward: target, dt: 1 / 30)

    XCTAssertGreaterThan(spring.current.left.upperLid, 0)
    XCTAssertLessThan(spring.current.left.upperLid, 0.5)
    XCTAssertFalse(spring.isSettled(at: target))
  }

  func testSnapJumpsWithoutVelocity() {
    var spring = ExpressionSpring(.neutral)
    let target = EyeMood.sleepy.expression

    spring.snap(to: target)

    XCTAssertTrue(spring.isSettled(at: target))
  }

  func testUpperLidCoversItsShareOfTheEye() {
    let paths = EyeGeometry.paths(
      for: EyeShape(upperLid: 0.5),
      baseSize: baseSize,
      openness: 1,
      isLeftEye: true
    )

    XCTAssertTrue(paths.upperLid.contains(CGPoint(x: 0, y: -2)))
    XCTAssertFalse(paths.upperLid.contains(CGPoint(x: 0, y: 2)))
  }

  func testPositiveTiltLowersTheInnerCornerOfEachEye() {
    let shape = EyeShape(upperLid: 0.3, upperLidTilt: 15)
    let left = EyeGeometry.paths(for: shape, baseSize: baseSize, openness: 1, isLeftEye: true)
    let right = EyeGeometry.paths(for: shape, baseSize: baseSize, openness: 1, isLeftEye: false)
    // Just below the untilted lid line (y = -4), near each corner.
    let innerOfLeft = CGPoint(x: 4, y: -3)
    let outerOfLeft = CGPoint(x: -4, y: -3)

    XCTAssertTrue(left.upperLid.contains(innerOfLeft))
    XCTAssertFalse(left.upperLid.contains(outerOfLeft))
    XCTAssertTrue(right.upperLid.contains(outerOfLeft))
    XCTAssertFalse(right.upperLid.contains(innerOfLeft))
  }

  func testArchedLowerLidKeepsTheCornersVisible() {
    let paths = EyeGeometry.paths(
      for: EyeShape(lowerLid: 0.5, lowerLidArch: 1),
      baseSize: baseSize,
      openness: 1,
      isLeftEye: true
    )

    XCTAssertTrue(paths.lowerLid.contains(CGPoint(x: 0, y: 1)))
    // Same height near a corner: the arch has dropped back toward the bottom there.
    XCTAssertFalse(paths.lowerLid.contains(CGPoint(x: -3.5, y: 1)))
    XCTAssertFalse(paths.lowerLid.contains(CGPoint(x: -3.5, y: 4)))
  }

  func testVisiblePathRoundsTheLidCutWithoutLosingTheEye() {
    let shape = EyeShape(upperLid: 0.4, upperLidTilt: 10)
    let visible = EyeGeometry.visiblePath(for: shape, baseSize: baseSize, openness: 1, isLeftEye: true)
    let bounds = visible.boundingBoxOfPath

    XCTAssertEqual(bounds.maxY, 10, accuracy: 0.5)
    XCTAssertGreaterThan(bounds.minY, -3)
    // The inner top corner of the cut is rounded off.
    XCTAssertFalse(visible.contains(CGPoint(x: 4.9, y: bounds.minY + 0.3)))
  }

  func testOpennessShrinksTheEye() {
    let closed = EyeGeometry.paths(for: .open, baseSize: baseSize, openness: 0.05, isLeftEye: true)

    XCTAssertLessThan(closed.eye.boundingBox.height, 2)
    XCTAssertEqual(closed.eye.boundingBox.width, 10, accuracy: 0.001)
  }

  func testReadingGazeJumpsBetweenFixations() {
    var previous = EyeProjection.readingGaze(at: 0)
    var stillSamples = 0
    var samples = 0

    for step in 1...600 {
      let gaze = EyeProjection.readingGaze(at: Double(step) / 200)
      XCTAssertLessThan(abs(gaze.yaw - previous.yaw), 8)
      XCTAssertLessThan(abs(gaze.pitch - previous.pitch), 1)
      if gaze.yaw == previous.yaw { stillSamples += 1 }
      samples += 1
      previous = gaze
    }

    // Mostly fixations, with quick saccades in between.
    XCTAssertGreaterThan(Double(stillSamples) / Double(samples), 0.7)
  }
}
