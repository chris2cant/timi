import SwiftUI

/// Asks `AnimatedEyes` to play a gesture. The serial lets the same gesture play again.
struct GestureTrigger: Equatable {
  let gesture: EyeGesture
  let serial: Int
}

extension Optional<GestureTrigger> {
  /// Replaces the trigger so that `gesture` plays, even right after the same one.
  mutating func play(_ gesture: EyeGesture) {
    self = GestureTrigger(gesture: gesture, serial: (self?.serial ?? 0) + 1)
  }
}

/// Frame-to-frame face state. Reference type on purpose: it is mutated from the
/// `TimelineView` body and must not trigger SwiftUI invalidations.
@MainActor
private final class FaceAnimator {
  struct Frame {
    /// Visible outline of each eye (left, right) in its own frame, before the projection.
    let outlines: [CGPath]
    let gaze: HeadGaze
  }

  private struct OutlineInput: Equatable {
    let shape: EyeShape
    let openness: CGFloat
    let baseSize: CGSize
  }

  private var spring = ExpressionSpring(.neutral)
  private var hasStarted = false
  private var gaze: HeadGaze?
  private var lastTime: TimeInterval?
  private var gesture: (kind: EyeGesture, start: TimeInterval)?
  private var pendingGesture: EyeGesture?
  private var nextBlink: TimeInterval?
  /// Last outline of each eye. The face holds still most of the time while the gaze moves,
  /// and cutting the lids out of an eye is the costly part of a frame.
  private var cachedOutlines: [(input: OutlineInput, path: CGPath)?] = [nil, nil]
  private let gazeResponseTime: TimeInterval = 0.06

  func play(_ gesture: EyeGesture) {
    pendingGesture = gesture
  }

  func frame(
    mood: FaceExpression,
    gaze target: HeadGaze,
    at time: TimeInterval,
    autoBlink: Bool,
    animated: Bool,
    baseSize: CGSize
  ) -> Frame {
    defer { lastTime = time }
    let dt = lastTime.map { max(0, time - $0) } ?? 0

    guard animated, hasStarted else {
      // First frame or Reduce Motion: show the mood as is.
      hasStarted = true
      spring.snap(to: mood)
      gaze = target + mood.gazeBias
      if !animated {
        gesture = nil
        pendingGesture = nil
      }
      return Frame(
        outlines: outlines(for: mood, pose: .rest, baseSize: baseSize),
        gaze: target + mood.gazeBias
      )
    }

    if let pendingGesture {
      gesture = (pendingGesture, time)
      self.pendingGesture = nil
    }
    if let gesture, time - gesture.start > gesture.kind.duration {
      self.gesture = nil
    }
    if gesture == nil, autoBlink {
      if let nextBlink, time >= nextBlink {
        gesture = (.blink, time)
        self.nextBlink = nil
      }
      if nextBlink == nil {
        nextBlink = time + .random(in: 3.5...7)
      }
    }

    let pose = gesture.map { $0.kind.pose(at: time - $0.start) } ?? .rest
    spring.step(toward: pose.expression ?? mood, dt: dt)

    let gazeTarget = target + spring.current.gazeBias
    let smoothed: HeadGaze
    if let gaze {
      let k = CGFloat(1 - exp(-min(dt, 0.25) / gazeResponseTime))
      smoothed = HeadGaze(
        yaw: gaze.yaw + (gazeTarget.yaw - gaze.yaw) * k,
        pitch: gaze.pitch + (gazeTarget.pitch - gaze.pitch) * k,
        roll: gaze.roll + (gazeTarget.roll - gaze.roll) * k
      )
    } else {
      smoothed = gazeTarget
    }
    gaze = smoothed

    return Frame(
      outlines: outlines(for: spring.current, pose: pose, baseSize: baseSize),
      gaze: smoothed + pose.gaze
    )
  }

  private func outlines(for expression: FaceExpression, pose: GesturePose, baseSize: CGSize) -> [CGPath] {
    let eyes = [(expression.left, pose.leftOpenness), (expression.right, pose.rightOpenness)]

    return eyes.enumerated().map { index, eye in
      var shape = eye.0
      shape.offset.dx += pose.offset.dx
      shape.offset.dy += pose.offset.dy
      let input = OutlineInput(shape: shape, openness: eye.1, baseSize: baseSize)
      if let cached = cachedOutlines[index], cached.input == input { return cached.path }

      let path = EyeGeometry.visiblePath(
        for: shape,
        baseSize: baseSize,
        openness: eye.1,
        isLeftEye: index == 0
      )
      cachedOutlines[index] = (input, path)
      return path
    }
  }
}

/// Timi's two eyes, projected on a sphere, with lids shaped by a mood, auto-blinks and
/// one-shot gestures. Shared by the main mascot, the session mascots and the Settings gallery.
struct AnimatedEyes: View {
  var mood: EyeMood
  /// Gaze target before the mood's bias, read every frame.
  var gaze: (TimeInterval) -> HeadGaze
  var trigger: GestureTrigger? = nil
  /// Height of a neutral eye is `EyeProjection.eyeHeight * eyeScale`.
  var eyeScale: CGFloat
  var autoBlink = true
  /// Gestures picked at random now and then, so the face never looks frozen.
  var ambientGestures: [EyeGesture] = []
  var ambientInterval: ClosedRange<TimeInterval> = 8...16
  /// Stops the timeline between gestures and mood changes (asleep session mascots).
  var restsWhenStill = false
  /// Freezes the face while nobody can see it.
  var isPaused = false
  /// Radius of the soft light around each eye.
  var glowRadius: CGFloat = 3

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var animator = FaceAnimator()
  @State private var isAwake = true
  @State private var wakeSerial = 0
  @State private var wakeDuration: TimeInterval = 0

  var body: some View {
    let paused = reduceMotion || isPaused || (restsWhenStill && !isAwake)
    let baseSize = CGSize(
      width: EyeProjection.eyeWidth * eyeScale,
      height: EyeProjection.eyeHeight * eyeScale
    )

    TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      let frame = animator.frame(
        mood: mood.expression,
        gaze: gaze(time),
        at: time,
        autoBlink: autoBlink,
        animated: !reduceMotion,
        baseSize: baseSize
      )

      Canvas { context, size in
        Self.draw(frame, in: &context, size: size, glowRadius: glowRadius)
      }
    }
    .onChange(of: trigger) {
      guard let trigger, !reduceMotion else { return }
      play(trigger.gesture)
    }
    .onChange(of: mood) {
      wake(for: 0)
    }
    .task(id: AmbientKey(gestures: ambientGestures, interval: ambientInterval, reduceMotion: reduceMotion)) {
      await playAmbientGestures()
    }
    .task(id: wakeSerial) {
      // Keeps the timeline running long enough for the spring and the gesture to finish.
      guard restsWhenStill, wakeSerial > 0 else { return }
      do {
        try await Task.sleep(for: .seconds(wakeDuration))
      } catch {
        return
      }
      isAwake = false
    }
    .onAppear {
      isAwake = !restsWhenStill
      if restsWhenStill { wake(for: 0) }
    }
    .accessibilityHidden(true)
  }

  private func play(_ gesture: EyeGesture) {
    animator.play(gesture)
    wake(for: gesture.duration)
  }

  private func wake(for duration: TimeInterval) {
    guard restsWhenStill else { return }
    wakeDuration = duration + 0.8
    isAwake = true
    wakeSerial += 1
  }

  private func playAmbientGestures() async {
    guard !reduceMotion, !ambientGestures.isEmpty else { return }

    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(.random(in: ambientInterval)))
      } catch {
        return
      }
      if let gesture = ambientGestures.randomElement() {
        play(gesture)
      }
    }
  }

  private static func draw(
    _ frame: FaceAnimator.Frame,
    in context: inout GraphicsContext,
    size: CGSize,
    glowRadius: CGFloat
  ) {
    let eyes = EyeProjection.eyes(for: frame.gaze, radius: min(size.width, size.height) / 2)
    let center = CGPoint(x: size.width / 2, y: size.height / 2 + 1)

    if glowRadius > 0 {
      context.addFilter(.shadow(color: .white.opacity(0.4), radius: glowRadius))
    }

    for (index, eye) in eyes.enumerated() where eye.depth > 0.02 {
      let transform = CGAffineTransform(
        a: eye.a,
        b: eye.b,
        c: eye.c,
        d: eye.d,
        tx: center.x + eye.x,
        ty: center.y + eye.y
      )
      let opacity = min(1, eye.depth / 0.12) * 0.96
      context.fill(Path(frame.outlines[index]).applying(transform), with: .color(.white.opacity(opacity)))
    }
  }
}

private struct AmbientKey: Equatable {
  let gestures: [EyeGesture]
  let interval: ClosedRange<TimeInterval>
  let reduceMotion: Bool
}
