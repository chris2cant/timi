import CoreGraphics
import Foundation

/// Shape of one eye. Lengths are fractions of the eye's own size, so the same
/// expression works for the main mascot and for the small session mascots.
struct EyeShape: Equatable, Sendable {
  /// Horizontal and vertical scale of the capsule (squash and stretch).
  var width: CGFloat = 1
  var height: CGFloat = 1
  /// Share of the eye hidden by the upper lid at its center, from the top (0 open, 1 closed).
  var upperLid: CGFloat = 0
  /// Upper lid slope in degrees. Positive lowers the inner corner (focused, annoyed),
  /// negative lowers the outer corner (worried, pleading).
  var upperLidTilt: CGFloat = 0
  /// Share of the eye hidden by the lower lid at its center, from the bottom.
  var lowerLid: CGFloat = 0
  /// How much higher the lower lid sits at its center than at the corners, as a share of
  /// `lowerLid` (0 flat, 1 corners at the bottom: the happy "^ ^" arch).
  var lowerLidArch: CGFloat = 0
  /// Shift of the eye, in eye heights (y down).
  var offset: CGVector = .zero

  static let open = EyeShape()
}

/// Both eyes plus a gaze bias. Eyes are in screen order: `left` is the one on the left.
struct FaceExpression: Equatable, Sendable {
  var left: EyeShape
  var right: EyeShape
  /// Added to the gaze, so an expression can look up (thinking) or down (sleepy).
  var gazeBias: HeadGaze = .zero

  static let neutral = FaceExpression(both: .open)
}

extension FaceExpression {
  /// Same shape for both eyes. The lid tilt is mirrored by the renderer, so a symmetric
  /// expression only describes one eye.
  init(both eye: EyeShape, gazeBias: HeadGaze = .zero) {
    self.init(left: eye, right: eye, gazeBias: gazeBias)
  }
}

extension HeadGaze {
  static let zero = HeadGaze(yaw: 0, pitch: 0, roll: 0)

  static func + (lhs: Self, rhs: Self) -> Self {
    HeadGaze(yaw: lhs.yaw + rhs.yaw, pitch: lhs.pitch + rhs.pitch, roll: lhs.roll + rhs.roll)
  }
}

/// Long-lived face state the mascot rests in. Shown by name in the Settings gallery.
enum EyeMood: String, CaseIterable, Identifiable, Sendable {
  case neutral, focused, happy, content, surprised, curious, pleading, sleepy, annoyed

  var id: Self { self }
}

/// One-shot face animation played on top of the mood, then dropped.
enum EyeGesture: String, CaseIterable, Identifiable, Sendable {
  case blink, doubleBlink, wink, lookAround, glanceUp, aha, startle, giggle, confused, wince
  case yawn, dizzy

  var id: Self { self }
}

/// What a gesture adds to the face at one instant.
struct GesturePose: Equatable, Sendable {
  /// Replaces the mood target while the gesture plays. It goes through the spring,
  /// so it suits holds of 150 ms and more, not blinks.
  var expression: FaceExpression? = nil
  /// Multiplies each eye's visible height directly, without the spring (blinks, winks).
  var leftOpenness: CGFloat = 1
  var rightOpenness: CGFloat = 1
  /// Added to the gaze directly (glances, eye rolls).
  var gaze: HeadGaze = .zero
  /// Shifts both eyes directly, in eye heights (y down), for shakes and bounces.
  var offset: CGVector = .zero

  static let rest = GesturePose()
}

/// Damped spring on every expression parameter, stepped once per frame.
/// Slightly underdamped: an expression change settles in ~0.3 s with a small overshoot.
struct ExpressionSpring {
  var stiffness: CGFloat = 260
  var dampingRatio: CGFloat = 0.72

  private(set) var current: FaceExpression
  private var velocity: [CGFloat]

  init(_ expression: FaceExpression) {
    current = expression
    velocity = Array(repeating: 0, count: expression.components.count)
  }

  mutating func snap(to target: FaceExpression) {
    current = target
    velocity = Array(repeating: 0, count: velocity.count)
  }

  /// Advances by `dt` seconds toward `target`. Large gaps (window hidden, timeline paused)
  /// are split into small steps, so the integration stays stable.
  mutating func step(toward target: FaceExpression, dt: TimeInterval) {
    // At rest on the target: nothing would move.
    guard current != target || velocity.contains(where: { $0 != 0 }) else { return }

    var position = current.components
    let goal = target.components
    let damping = 2 * dampingRatio * stiffness.squareRoot()
    var remaining = CGFloat(min(max(dt, 0), 1))
    while remaining > 0 {
      let h = min(remaining, 1 / 120)
      for index in position.indices {
        let force = stiffness * (goal[index] - position[index]) - damping * velocity[index]
        velocity[index] += force * h
        position[index] += velocity[index] * h
      }
      remaining -= h
    }
    current = FaceExpression(components: position)
    // Land exactly once close enough, so a still face stops changing and its eye outlines
    // can be reused.
    if isSettled(at: target) { snap(to: target) }
  }

  /// True once the face is close enough to `target` to stop ticking.
  func isSettled(at target: FaceExpression) -> Bool {
    zip(current.components, target.components).allSatisfy { abs($0 - $1) < 0.002 }
      && velocity.allSatisfy { abs($0) < 0.01 }
  }
}

extension FaceExpression {
  /// Flat parameter list used by the spring. Order is private to this file.
  fileprivate var components: [CGFloat] {
    left.components + right.components + [gazeBias.yaw, gazeBias.pitch, gazeBias.roll]
  }

  fileprivate init(components c: [CGFloat]) {
    let count = EyeShape.componentCount
    self.init(
      left: EyeShape(components: c[0..<count]),
      right: EyeShape(components: c[count..<count * 2]),
      gazeBias: HeadGaze(yaw: c[count * 2], pitch: c[count * 2 + 1], roll: c[count * 2 + 2])
    )
  }
}

extension EyeShape {
  fileprivate static let componentCount = 8

  fileprivate var components: [CGFloat] {
    [width, height, upperLid, upperLidTilt, lowerLid, lowerLidArch, offset.dx, offset.dy]
  }

  fileprivate init(components c: ArraySlice<CGFloat>) {
    let c = Array(c)
    self.init(
      width: c[0], height: c[1], upperLid: c[2], upperLidTilt: c[3], lowerLid: c[4],
      lowerLidArch: c[5], offset: CGVector(dx: c[6], dy: c[7]))
  }
}

/// Pure geometry of an eye in its own frame: centered on the origin, y down, before the
/// spherical projection. Kept apart from the views so it can be tested.
enum EyeGeometry {
  /// The capsule, scaled by the shape and `openness`, with an outline for each lid to cut
  /// away. `isLeftEye` decides which side is the inner corner for the lid tilt.
  static func paths(
    for shape: EyeShape,
    baseSize: CGSize,
    openness: CGFloat,
    isLeftEye: Bool
  ) -> (eye: CGPath, upperLid: CGPath, lowerLid: CGPath) {
    let width = baseSize.width * max(shape.width, 0.05)
    let height = baseSize.height * max(shape.height, 0.05) * min(max(openness, 0.04), 1.2)
    let center = CGPoint(x: shape.offset.dx * baseSize.height, y: shape.offset.dy * baseSize.height)
    let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    let radius = min(width, height) / 2
    let eye = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Wide enough to cover the capsule whatever the tilt.
    let reach = width * 0.75
    let minX = center.x - reach
    let maxX = center.x + reach

    // Upper lid: a slightly convex edge, lower on the inner side when the tilt is positive.
    let upperY = rect.minY + rect.height * min(max(shape.upperLid, 0), 1)
    let slope = tan(shape.upperLidTilt * .pi / 180) * (isLeftEye ? 1 : -1)
    let upper = CGMutablePath()
    upper.move(to: CGPoint(x: minX, y: rect.minY - height))
    upper.addLine(to: CGPoint(x: maxX, y: rect.minY - height))
    upper.addLine(to: CGPoint(x: maxX, y: upperY + slope * reach))
    upper.addQuadCurve(
      to: CGPoint(x: minX, y: upperY - slope * reach),
      control: CGPoint(x: center.x, y: upperY + rect.height * 0.08 * shape.upperLid)
    )
    upper.closeSubpath()

    // Lower lid: a curve rising toward the center; with a full arch the corners stay at
    // the bottom and only the middle is hidden.
    let lowerLid = min(max(shape.lowerLid, 0), 1)
    let peakY = rect.maxY - rect.height * lowerLid
    let cornerY = rect.maxY - rect.height * lowerLid * (1 - min(max(shape.lowerLidArch, 0), 1))
    let lower = CGMutablePath()
    lower.move(to: CGPoint(x: minX, y: rect.maxY + height))
    lower.addLine(to: CGPoint(x: minX, y: cornerY))
    lower.addLine(to: CGPoint(x: rect.minX, y: cornerY))
    // The curve spans the eye exactly, so an arch leaves both corners visible.
    // A quadratic Bézier only reaches halfway to its control point.
    lower.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: cornerY),
      control: CGPoint(x: center.x, y: 2 * peakY - cornerY)
    )
    lower.addLine(to: CGPoint(x: maxX, y: cornerY))
    lower.addLine(to: CGPoint(x: maxX, y: rect.maxY + height))
    lower.closeSubpath()

    return (eye, upper, lower)
  }

  /// What remains of the eye once the lids are cut away, with the sharp corners left by the
  /// cuts rounded off. This is the single path the renderer fills, so the glow follows it.
  static func visiblePath(
    for shape: EyeShape,
    baseSize: CGSize,
    openness: CGFloat,
    isLeftEye: Bool
  ) -> CGPath {
    let parts = paths(for: shape, baseSize: baseSize, openness: openness, isLeftEye: isLeftEye)
    let hasLids = shape.upperLid > 0.005 || abs(shape.upperLidTilt) > 0.5 || shape.lowerLid > 0.005
    guard hasLids else { return parts.eye }

    let cut = parts.eye.subtracting(parts.upperLid).subtracting(parts.lowerLid)
    let bounds = cut.boundingBoxOfPath
    // Capped by the remaining height, or a nearly closed eye would vanish entirely.
    let radius = min(baseSize.width * 0.1, bounds.height * 0.25)
    guard radius > 0.25 else { return cut }

    // Morphological opening: shrink by `radius`, then grow back with round joins. Convex
    // corners come back rounded; slivers thinner than the radius disappear.
    let band = { (path: CGPath) in
      path.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
    }
    let core = cut.subtracting(band(cut))
    return core.union(band(core))
  }
}
