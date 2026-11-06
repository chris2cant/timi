import XCTest

@testable import Timi

final class EyeCatalogTests: XCTestCase {
  func testMoodsStayInSafeRanges() {
    for mood in EyeMood.allCases {
      let face = mood.expression
      for eye in [face.left, face.right] {
        XCTAssertTrue((0...0.7).contains(eye.upperLid), "\(mood) upperLid")
        XCTAssertTrue((0...0.7).contains(eye.lowerLid), "\(mood) lowerLid")
        XCTAssertTrue((0.8...1.25).contains(eye.width), "\(mood) width")
        XCTAssertTrue((0.8...1.25).contains(eye.height), "\(mood) height")
        XCTAssertLessThanOrEqual(abs(eye.upperLidTilt), 20, "\(mood) tilt")
      }
    }
  }

  func testMoodSpecifics() {
    XCTAssertGreaterThanOrEqual(EyeMood.happy.expression.left.lowerLidArch, 0.8)
    let pleading = EyeMood.pleading.expression.left.upperLidTilt
    let annoyed = EyeMood.annoyed.expression.left.upperLidTilt
    XCTAssertLessThan(pleading * annoyed, 0)
    // Working must not look cross: no frown from the lid tilt.
    XCTAssertLessThanOrEqual(EyeMood.focused.expression.left.upperLidTilt, 0)
  }

  func testGesturesAreBoundedAndRestOutside() {
    for gesture in EyeGesture.allCases {
      XCTAssertGreaterThan(gesture.duration, 0, "\(gesture)")
      XCTAssertLessThanOrEqual(gesture.duration, 3, "\(gesture)")
      XCTAssertEqual(gesture.pose(at: -0.01), .rest, "\(gesture)")
      XCTAssertEqual(gesture.pose(at: gesture.duration + 0.01), .rest, "\(gesture)")
    }
  }

  func testGesturesAreNeutralAtBounds() {
    for gesture in EyeGesture.allCases {
      for t in [0, gesture.duration] {
        let pose = gesture.pose(at: t)
        XCTAssertEqual(pose.leftOpenness, 1, accuracy: 0.02, "\(gesture) at \(t)")
        XCTAssertEqual(pose.rightOpenness, 1, accuracy: 0.02, "\(gesture) at \(t)")
        XCTAssertEqual(pose.gaze.yaw, 0, accuracy: 0.5, "\(gesture) at \(t)")
        XCTAssertEqual(pose.gaze.pitch, 0, accuracy: 0.5, "\(gesture) at \(t)")
        XCTAssertEqual(pose.offset.dx, 0, accuracy: 0.02, "\(gesture) at \(t)")
        XCTAssertEqual(pose.offset.dy, 0, accuracy: 0.02, "\(gesture) at \(t)")
      }
    }
  }

  func testGesturesAreContinuous() {
    let step = 0.005
    for gesture in EyeGesture.allCases {
      var previous = gesture.pose(at: 0)
      var t = step
      while t <= gesture.duration {
        let pose = gesture.pose(at: t)
        let label = "\(gesture) at \(t)"
        XCTAssertLessThan(abs(pose.leftOpenness - previous.leftOpenness), 0.25, label)
        XCTAssertLessThan(abs(pose.rightOpenness - previous.rightOpenness), 0.25, label)
        XCTAssertLessThan(abs(pose.gaze.yaw - previous.gaze.yaw), 8, label)
        XCTAssertLessThan(abs(pose.gaze.pitch - previous.gaze.pitch), 8, label)
        XCTAssertLessThan(abs(pose.offset.dx - previous.offset.dx), 0.05, label)
        XCTAssertLessThan(abs(pose.offset.dy - previous.offset.dy), 0.05, label)
        previous = pose
        t += step
      }
    }
  }

  func testBlinkClosesAroundMidpoint() {
    let pose = EyeGesture.blink.pose(at: EyeGesture.blink.duration / 2)
    XCTAssertLessThan(pose.leftOpenness, 0.1)
    XCTAssertLessThan(pose.rightOpenness, 0.1)
  }

  func testWinkClosesOnlyTheRightEye() {
    let pose = EyeGesture.wink.pose(at: 0.25)
    XCTAssertEqual(pose.leftOpenness, 1, accuracy: 0.001)
    XCTAssertLessThan(pose.rightOpenness, 0.1)
  }
}
