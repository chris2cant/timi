import CoreGraphics
import Foundation

// MARK: - Moods

extension EyeMood {
  /// Short French label for the Settings gallery.
  var title: String {
    switch self {
    case .neutral: "Neutre"
    case .focused: "Concentré"
    case .happy: "Joyeux"
    case .content: "Serein"
    case .surprised: "Surpris"
    case .curious: "Curieux"
    case .pleading: "Suppliant"
    case .sleepy: "Endormi"
    case .annoyed: "Agacé"
    }
  }

  var expression: FaceExpression {
    switch self {
    case .neutral:
      return .neutral
    case .focused:
      // Studious, not cross: a flat, slightly lowered lid and eyes down on the work.
      // A positive tilt here reads as a frown.
      return FaceExpression(
        both: EyeShape(height: 0.95, upperLid: 0.24, upperLidTilt: -2),
        gazeBias: HeadGaze(yaw: 0, pitch: -7, roll: 0))
    case .happy:
      // The cheeks squash the eye and push it up into a crescent. A tall eye with the same
      // lid reads as an "n", hence the squash.
      return FaceExpression(
        both: EyeShape(
          width: 1.14, height: 0.8, lowerLid: 0.45, lowerLidArch: 1,
          offset: CGVector(dx: 0, dy: -0.06)))
    case .content:
      // Relaxed lids. A lower-lid cut on such a narrow eye leaves two fangs at the bottom.
      return FaceExpression(both: EyeShape(upperLid: 0.2, upperLidTilt: -6))
    case .surprised:
      return FaceExpression(both: EyeShape(width: 1.12, height: 1.14))
    case .curious:
      // Uneven eyes read as a tilted head.
      return FaceExpression(
        left: EyeShape(width: 1.06, height: 1.1),
        right: EyeShape(height: 0.92, upperLid: 0.14))
    case .pleading:
      return FaceExpression(
        both: EyeShape(width: 1.08, height: 1.1, upperLid: 0.14, upperLidTilt: -16),
        gazeBias: HeadGaze(yaw: 0, pitch: 4, roll: 0))
    case .sleepy:
      return FaceExpression(
        both: EyeShape(upperLid: 0.55, upperLidTilt: -4, lowerLid: 0.06),
        gazeBias: HeadGaze(yaw: 0, pitch: -10, roll: 0))
    case .annoyed:
      // Flat, unimpressed look.
      return FaceExpression(both: EyeShape(upperLid: 0.42, upperLidTilt: 4, lowerLid: 0.12))
    }
  }
}

// MARK: - Gestures

extension EyeGesture {
  /// Short French label for the Settings gallery.
  var title: String {
    switch self {
    case .blink: "Clignement"
    case .doubleBlink: "Double clignement"
    case .wink: "Clin d'œil"
    case .lookAround: "Regard autour"
    case .glanceUp: "Je réfléchis"
    case .aha: "Aha !"
    case .startle: "Sursaut"
    case .giggle: "Fou rire"
    case .confused: "Perplexe"
    case .wince: "Aïe"
    case .yawn: "Bâillement"
    case .dizzy: "Vertige"
    }
  }

  var duration: TimeInterval {
    switch self {
    case .blink: 0.18
    case .doubleBlink: 0.42
    case .wink: 0.5
    case .lookAround: 1.7
    case .glanceUp: 1.4
    case .aha: 0.7
    case .startle: 0.65
    case .giggle: 1.0
    case .confused: 1.1
    case .wince: 0.55
    case .yawn: 2.2
    case .dizzy: 2.0
    }
  }

  /// Pose at `elapsed` seconds since the gesture started; `.rest` outside 0...duration.
  func pose(at elapsed: TimeInterval) -> GesturePose {
    guard elapsed >= 0, elapsed <= duration else { return .rest }
    let t = elapsed
    var pose = GesturePose()

    switch self {
    case .blink:
      let openness = blinkOpenness(at: t, start: 0, close: 0.06, hold: 0.03, open: 0.09)
      pose.leftOpenness = openness
      pose.rightOpenness = openness

    case .doubleBlink:
      let first = blinkOpenness(at: t, start: 0, close: 0.05, hold: 0.02, open: 0.09)
      let second = blinkOpenness(at: t, start: 0.22, close: 0.05, hold: 0.02, open: 0.09)
      pose.leftOpenness = min(first, second)
      pose.rightOpenness = min(first, second)

    case .wink:
      // Knowing wink: the open eye smiles a little while the right one closes.
      var smile = EyeShape.open
      smile.lowerLid = 0.2
      smile.lowerLidArch = 0.6
      pose.expression = FaceExpression(left: smile, right: .open)
      pose.rightOpenness = blinkOpenness(at: t, start: 0, close: 0.07, hold: 0.31, open: 0.12)

    case .lookAround:
      // Saccades are fast; the eye rests still between them.
      pose.gaze = HeadGaze(
        yaw: interpolate(
          [
            Key(0, 0), Key(0.2, 0), Key(0.27, -24), Key(0.67, -24),
            Key(0.77, 24), Key(1.17, 24), Key(1.25, 0), Key(1.7, 0),
          ], at: t),
        pitch: 0, roll: 0)
      // Real eyes blink during large gaze shifts.
      let openness = blinkOpenness(at: t, start: 0.64, close: 0.06, hold: 0.03, open: 0.09)
      pose.leftOpenness = openness
      pose.rightOpenness = openness

    case .glanceUp:
      // "Thinking": a quick glance up and to the side, held, then back.
      var thinking = EyeShape.open
      thinking.upperLid = 0.1
      thinking.lowerLid = 0.12
      thinking.lowerLidArch = 0.3
      pose.expression = FaceExpression(both: thinking)
      let ramp = interpolate([Key(0, 0), Key(0.1, 0), Key(0.22, 1), Key(1.0, 1), Key(1.12, 0)], at: t)
      pose.gaze = HeadGaze(yaw: 10 * ramp, pitch: 16 * ramp, roll: 0)

    case .aha:
      if t < 0.35 { pose.expression = EyeMood.surprised.expression }
      let openness = interpolate([Key(0, 1), Key(0.05, 1.15), Key(0.4, 1)], at: t)
      pose.leftOpenness = openness
      pose.rightOpenness = openness
      pose.offset = CGVector(
        dx: 0, dy: interpolate([Key(0, 0), Key(0.1, -0.06), Key(0.3, 0)], at: t))

    case .startle:
      pose.expression = EyeMood.surprised.expression
      let openness = interpolate([Key(0, 1), Key(0.04, 1.2), Key(0.4, 1)], at: t)
      pose.leftOpenness = openness
      pose.rightOpenness = openness
      // Jumps up, then settles back with a small damped overshoot.
      pose.offset = CGVector(
        dx: 0,
        dy: interpolate([Key(0, 0), Key(0.05, -0.1), Key(0.22, 0.02), Key(0.4, 0)], at: t))

    case .giggle:
      pose.expression = EyeMood.happy.expression
      // Bounces at 4 Hz that only ever go up, fading out.
      let bounce = (1 - cos(2 * .pi * 4 * t)) / 2
      pose.offset = CGVector(dx: 0, dy: -0.06 * (1 - t / duration) * bounce)

    case .confused:
      var squint = EyeShape.open
      squint.upperLid = 0.25
      squint.upperLidTilt = -10
      var wide = EyeShape.open
      wide.height = 1.08
      pose.expression = FaceExpression(left: squint, right: wide)
      let u = t / duration
      pose.offset = CGVector(dx: 0.08 * (1 - u) * sin(2 * .pi * 3 * u), dy: 0)

    case .wince:
      pose.expression = FaceExpression(
        both: EyeShape(upperLid: 0.5, upperLidTilt: 14, lowerLid: 0.35))
      if t < 0.3 {
        pose.offset = CGVector(dx: 0.04 * (1 - t / 0.3) * sin(2 * .pi * 2 * t / 0.3), dy: 0)
      }

    case .yawn:
      // Eyes squeeze shut for the yawn, then a slow blink.
      if t < 1.4 {
        pose.expression = FaceExpression(
          both: EyeShape(height: 0.9, upperLid: 0.6, lowerLid: 0.3))
      }
      let openness = blinkOpenness(at: t, start: 1.9, close: 0.12, hold: 0.06, open: 0.12)
      pose.leftOpenness = openness
      pose.rightOpenness = openness

    case .dizzy:
      var left = EyeShape.open
      left.height = 1.08
      var right = EyeShape.open
      right.height = 0.9
      right.upperLid = 0.15
      pose.expression = FaceExpression(left: left, right: right)
      // Decaying circle, eased in at the start and back to center over the last half second.
      let fadeIn = interpolate([Key(0, 0), Key(0.15, 1)], at: t)
      let fadeOut = interpolate([Key(1.5, 1), Key(2.0, 0)], at: t)
      let amplitude = (1 - 0.6 * t / duration) * fadeIn * fadeOut
      let angle = 2 * .pi * 2 * t
      pose.gaze = HeadGaze(yaw: 14 * cos(angle) * amplitude, pitch: 10 * sin(angle) * amplitude, roll: 0)
    }

    return pose
  }
}

// MARK: - Keyframes

private struct Key {
  enum Ease { case smooth, easeIn, easeOut }

  let time: TimeInterval
  let value: CGFloat
  /// Easing of the segment that ends at this key.
  let ease: Ease

  init(_ time: TimeInterval, _ value: CGFloat, _ ease: Ease = .smooth) {
    self.time = time
    self.value = value
    self.ease = ease
  }
}

/// Value of a keyframe track at `t`, holding the first and last values outside the track.
/// Keys must be sorted by time.
private func interpolate(_ keys: [Key], at t: TimeInterval) -> CGFloat {
  guard let first = keys.first, let last = keys.last else { return 0 }
  if t <= first.time { return first.value }
  if t >= last.time { return last.value }
  for (a, b) in zip(keys, keys.dropFirst()) where t < b.time {
    let x = CGFloat((t - a.time) / (b.time - a.time))
    let eased: CGFloat
    switch b.ease {
    case .smooth: eased = x * x * (3 - 2 * x)
    case .easeIn: eased = x * x
    case .easeOut: eased = 1 - (1 - x) * (1 - x)
    }
    return a.value + (b.value - a.value) * eased
  }
  return last.value
}

/// Openness of one blink: closes fast, holds, then reopens more gently.
private func blinkOpenness(
  at t: TimeInterval, start: TimeInterval, close: TimeInterval, hold: TimeInterval,
  open: TimeInterval
) -> CGFloat {
  interpolate(
    [
      Key(start, 1), Key(start + close, 0.05, .easeIn), Key(start + close + hold, 0.05),
      Key(start + close + hold + open, 1, .easeOut),
    ], at: t)
}
