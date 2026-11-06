import CoreGraphics
import Foundation

struct HeadGaze: Equatable {
  let yaw: CGFloat
  let pitch: CGFloat
  let roll: CGFloat
}

struct ProjectedEye: Equatable {
  let x: CGFloat
  let y: CGFloat
  let a: CGFloat
  let b: CGFloat
  let c: CGFloat
  let d: CGFloat
  let depth: CGFloat
}

enum EyeProjection {
  static let eyeSeparation: CGFloat = 15.46
  static let eyeWidth: CGFloat = 0.186
  static let eyeHeight: CGFloat = 0.412

  static let restingGaze = HeadGaze(yaw: 28.49, pitch: 28.62, roll: -13)

  static func wanderingGaze(at time: TimeInterval) -> HeadGaze {
    let yaw = sinWave(time, period: 8.6) * 29
      + sinWave(time, period: 3.7, phase: 2.1) * 4
    let pitch = 17
      + sinWave(time, period: 9.1, phase: 1.3) * 5
      + sinWave(time, period: 4.3, phase: 0.7) * 1.5
    let roll = -9 + sinWave(time, period: 13.7, phase: 3.2) * 2.2

    return HeadGaze(yaw: yaw, pitch: pitch, roll: roll)
  }

  /// Fixation yaws along one line of text and how long the eyes rest on each.
  private static let readingFixations: [(yaw: CGFloat, hold: TimeInterval)] = [
    (-20, 0.3), (-7, 0.36), (6, 0.26), (19, 0.32),
  ]
  private static let readingSaccade: TimeInterval = 0.05
  private static let readingReturn: TimeInterval = 0.18
  /// Each line sits a little lower than the previous one, then the page starts over.
  private static let readingLinePitches: [CGFloat] = [-1, -3, -5]
  private static let readingLineDuration = readingFixations.reduce(0) { $0 + $1.hold }
    + readingSaccade * Double(readingFixations.count - 1) + readingReturn

  /// Reading like a person does: quick jumps between short fixations along a line, then a
  /// return sweep to the start of the next line.
  static func readingGaze(at time: TimeInterval) -> HeadGaze {
    let fixations = readingFixations
    let line = readingLineDuration
    let lineIndex = Int((time / line).rounded(.down))
    var t = time - Double(lineIndex) * line
    let pitches = readingLinePitches
    // Wrapped for negative times too.
    let pitchIndex = (lineIndex % pitches.count + pitches.count) % pitches.count
    let pitch = pitches[pitchIndex]
    let nextPitch = pitches[(pitchIndex + 1) % pitches.count]

    for (index, fixation) in fixations.enumerated() {
      if t < fixation.hold {
        return HeadGaze(yaw: fixation.yaw, pitch: pitch, roll: 0)
      }
      t -= fixation.hold
      guard index + 1 < fixations.count else { break }
      if t < readingSaccade {
        let p = smoothstep(t / readingSaccade)
        let yaw = fixation.yaw + (fixations[index + 1].yaw - fixation.yaw) * p
        return HeadGaze(yaw: yaw, pitch: pitch, roll: 0)
      }
      t -= readingSaccade
    }

    let p = smoothstep(min(t / readingReturn, 1))
    let first = fixations[0].yaw
    let last = fixations[fixations.count - 1].yaw
    return HeadGaze(yaw: last + (first - last) * p, pitch: pitch + (nextPitch - pitch) * p, roll: 0)
  }

  static let maxTrackingYaw: CGFloat = 29
  static let maxTrackingPitch: CGFloat = 20
  static let trackingRestPitch: CGFloat = 0
  static let trackingRoll: CGFloat = 0
  static let trackingDistanceScale: CGFloat = 300

  /// Gaze toward a pointer offset from the mascot center (screen space, y up).
  /// `tanh` saturates smoothly so a far pointer never overshoots the sphere.
  static func gaze(towardOffset offset: CGVector) -> HeadGaze {
    HeadGaze(
      yaw: maxTrackingYaw * tanh(offset.dx / trackingDistanceScale),
      pitch: trackingRestPitch + maxTrackingPitch * tanh(offset.dy / trackingDistanceScale),
      roll: trackingRoll
    )
  }

  static func eyes(
    for gaze: HeadGaze,
    radius: CGFloat,
    separation: CGFloat = eyeSeparation
  ) -> [ProjectedEye] {
    var forward = Vector3(x: 0, y: 0, z: 1)
    var right = Vector3(x: 1, y: 0, z: 0)
    var down = Vector3(x: 0, y: 1, z: 0)

    (forward, right) = spin(forward, right, by: radians(gaze.yaw))
    (down, forward) = spin(down, forward, by: radians(gaze.pitch))
    (right, down) = spin(right, down, by: radians(gaze.roll))

    return [-1.0, 1.0].map { side in
      let (eyeForward, eyeRight) = spin(
        forward,
        right,
        by: radians(separation * side)
      )

      return ProjectedEye(
        x: eyeForward.x * radius,
        y: eyeForward.y * radius,
        a: eyeRight.x,
        b: eyeRight.y,
        c: down.x,
        d: down.y,
        depth: eyeForward.z
      )
    }
  }

  private static func sinWave(
    _ time: TimeInterval,
    period: TimeInterval,
    phase: TimeInterval = 0
  ) -> CGFloat {
    CGFloat(sin(((time + phase) / period) * Double.pi * 2))
  }

  private static func smoothstep(_ x: Double) -> CGFloat {
    CGFloat(x * x * (3 - 2 * x))
  }

  private static func radians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
  }

  private static func spin(
    _ first: Vector3,
    _ second: Vector3,
    by angle: CGFloat
  ) -> (Vector3, Vector3) {
    let cosine = cos(angle)
    let sine = sin(angle)

    return (
      first * cosine + second * sine,
      second * cosine - first * sine
    )
  }
}

private struct Vector3 {
  let x: CGFloat
  let y: CGFloat
  let z: CGFloat

  static func + (lhs: Self, rhs: Self) -> Self {
    Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
  }

  static func - (lhs: Self, rhs: Self) -> Self {
    Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
  }

  static func * (lhs: Self, rhs: CGFloat) -> Self {
    Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
  }
}
