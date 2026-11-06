import SwiftUI

struct SessionMascotView: View {
  nonisolated static let silhouetteSize = CGSize(width: 60, height: 42)
  /// A sleeping (idle) session shrinks so it reads as asleep at a glance.
  nonisolated private static let sleepingScale: CGFloat = 0.5
  nonisolated static let cornerRadius: CGFloat = 10
  static let eyeScale: CGFloat = 30
  static let glowRadius: CGFloat = 2
  /// Room around the silhouette for the joins drawn toward an attached screen edge.
  nonisolated static let joinMargin: CGFloat = 10
  nonisolated static let labelSize = CGSize(width: 70, height: 16)
  // Room between silhouette and label for the hop and the "!" bubble.
  nonisolated private static let labelGap: CGFloat = 19

  /// Size of the panel hosting one session mascot, label included.
  nonisolated static let windowSize = CGSize(width: 84, height: 80)

  /// Frame of the silhouette shape: the body plus the join margin on every side.
  nonisolated static let silhouetteFrameSize = CGSize(
    width: silhouetteSize.width + joinMargin * 2,
    height: silhouetteSize.height + joinMargin * 2
  )

  /// Body of a session-sized mascot, joined to `edges`, drawn in `silhouetteFrameSize`.
  static func silhouette(for edges: MascotAttachmentEdges) -> MascotSilhouette {
    MascotSilhouette(attachmentEdges: edges, cornerRadius: cornerRadius, margin: joinMargin)
  }

  /// Silhouette and label frames in window coordinates (origin bottom-left, y up).
  /// The silhouette touches the window side facing the attached screen edge, and the
  /// label sits on the inner side. An asleep silhouette is smaller and the label follows it.
  nonisolated static func frames(
    for edges: MascotAttachmentEdges,
    isAsleep: Bool
  ) -> (body: CGRect, label: CGRect) {
    let width = windowSize.width
    let height = windowSize.height
    let scale = isAsleep ? sleepingScale : 1
    let body = CGSize(width: silhouetteSize.width * scale, height: silhouetteSize.height * scale)
    let label = labelSize
    let centeredX = (width - body.width) / 2
    let centeredLabelX = (width - label.width) / 2

    let dock = SessionMascotDock(edges)
    switch dock {
    case .floating:
      let bodyY = height - 16 - body.height
      return (
        CGRect(origin: CGPoint(x: centeredX, y: bodyY), size: body),
        CGRect(origin: CGPoint(x: centeredLabelX, y: bodyY - 3 - label.height), size: label)
      )
    case .bottom:
      return (
        CGRect(origin: CGPoint(x: centeredX, y: 0), size: body),
        CGRect(origin: CGPoint(x: centeredLabelX, y: body.height + labelGap), size: label)
      )
    case .top:
      let bodyY = height - body.height
      return (
        CGRect(origin: CGPoint(x: centeredX, y: bodyY), size: body),
        CGRect(origin: CGPoint(x: centeredLabelX, y: bodyY - labelGap - label.height), size: label)
      )
    case .left, .right:
      let isLeft = dock == .left
      let bodyY = height - 14 - body.height
      // The label clears the join drawn along the wall.
      let labelX = isLeft ? joinMargin + 2 : width - joinMargin - 2 - label.width
      return (
        CGRect(origin: CGPoint(x: isLeft ? 0 : width - body.width, y: bodyY), size: body),
        CGRect(origin: CGPoint(x: labelX, y: bodyY - 3 - label.height), size: label)
      )
    }
  }

  let session: ClaudeSession
  /// Screen edge the mascot sticks to; empty when it floats.
  let edges: MascotAttachmentEdges
  /// Body color chosen for the project.
  let color: MascotColor
  /// Pointer offset from the mascot center (screen space, y up), for eye tracking.
  let pointerOffset: () -> CGVector

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var gestureTrigger: GestureTrigger?
  @State private var lastReactionDate = Date.distantPast
  @State private var hopCount = 0
  @State private var wiggleCount = 0

  private var dock: SessionMascotDock { SessionMascotDock(edges) }
  var isAsleep: Bool { session.status == .idle }

  var body: some View {
    let frames = Self.frames(for: edges, isAsleep: isAsleep)

    ZStack(alignment: .topLeading) {
      // Drawn at full size and scaled around its center, which lands on the smaller body
      // frame since the join margin is symmetric.
      mascot
        .scaleEffect(isAsleep ? Self.sleepingScale : 1)
        .position(inSessionWindow: frames.body)
      label
        .frame(width: frames.label.width, height: frames.label.height, alignment: dock.labelAlignment)
        .position(inSessionWindow: frames.label)
    }
    .animation(reduceMotion ? nil : .spring(duration: 0.45), value: isAsleep)
    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    .help(helpText)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(helpText)
    .onChange(of: session.status) { _, status in
      greet(status)
    }
    .onChange(of: session.reaction) { _, reaction in
      if let reaction { react(to: reaction.kind) }
    }
    .task(id: MotionKey(status: session.status, reduceMotion: reduceMotion)) {
      await animateStatus()
    }
  }

  private var mascot: some View {
    let shape = Self.silhouette(for: edges)
    let size = Self.silhouetteSize
    // Captured by value: the keyframe closures are Sendable.
    let dock = dock
    let anchor = dock.anchor(bodySize: size, margin: Self.joinMargin)

    return ZStack {
      shape
        .fill(color.swiftUIColor)
        .shadow(color: haloColor, radius: haloColor == .clear ? 0 : 4)
      eyes
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
      if haloColor != .clear {
        // The outline keeps the state readable on a wallpaper of the same hue as the halo.
        shape
          .stroke(session.status == .needsYou ? .orange : .blue, lineWidth: session.status == .needsYou ? 2 : 1.5)
          // No outline along the screen edge itself.
          .mask { Rectangle().padding(dock.wallEdge, Self.joinMargin + 1) }
      }
    }
    .overlay(alignment: dock.badgeAlignment) {
      badge.padding(Self.joinMargin)
    }
    .frame(width: Self.silhouetteFrameSize.width, height: Self.silhouetteFrameSize.height)
    .modifier(
      Breathing(
        period: breathingPeriod,
        inhale: CGSize(width: 1.012, height: 1.024),
        exhale: CGSize(width: 0.994, height: 0.988),
        anchor: anchor
      )
    )
    .keyframeAnimator(initialValue: HopPose(), trigger: hopCount) { content, pose in
      // The mascot hops away from its screen edge, squashing against it.
      content
        .scaleEffect(
          x: dock.hopsSideways ? pose.stretch : 2 - pose.stretch,
          y: dock.hopsSideways ? 2 - pose.stretch : pose.stretch,
          anchor: anchor
        )
        .offset(x: dock.hopDirection.dx * pose.lift, y: dock.hopDirection.dy * pose.lift)
    } keyframes: { _ in
      KeyframeTrack(\.stretch) {
        CubicKeyframe(0.9, duration: 0.1)
        CubicKeyframe(1.08, duration: 0.12)
        CubicKeyframe(1, duration: 0.16)
        CubicKeyframe(0.92, duration: 0.08)
        SpringKeyframe(1, duration: 0.22)
      }
      KeyframeTrack(\.lift) {
        LinearKeyframe(0, duration: 0.1)
        CubicKeyframe(7, duration: 0.18)
        CubicKeyframe(0, duration: 0.18)
        LinearKeyframe(0, duration: 0.22)
      }
    }
    .keyframeAnimator(initialValue: 0.0, trigger: wiggleCount) { content, angle in
      content.rotationEffect(.degrees(angle), anchor: anchor)
    } keyframes: { _ in
      KeyframeTrack {
        CubicKeyframe(-7, duration: 0.08)
        CubicKeyframe(6, duration: 0.12)
        CubicKeyframe(-4, duration: 0.12)
        CubicKeyframe(2, duration: 0.1)
        SpringKeyframe(0, duration: 0.2)
      }
    }
  }

  private var eyes: some View {
    let status = session.status

    return AnimatedEyes(
      mood: Self.mood(for: status),
      gaze: gaze(at:),
      trigger: gestureTrigger,
      eyeScale: status == .needsYou ? 34 : Self.eyeScale,
      autoBlink: status != .idle,
      ambientGestures: Self.ambientGestures(for: status),
      ambientInterval: Self.ambientInterval(for: status),
      // Asleep eyes are still between yawns: no timeline ticking.
      restsWhenStill: status == .idle,
      glowRadius: Self.glowRadius
    )
  }

  private static func mood(for status: ClaudeSessionStatus) -> EyeMood {
    switch status {
    case .working: .focused
    case .needsYou: .pleading
    case .yourTurn: .content
    case .idle: .sleepy
    }
  }

  private static func ambientGestures(for status: ClaudeSessionStatus) -> [EyeGesture] {
    switch status {
    case .working: [.glanceUp, .glanceUp, .doubleBlink, .aha]
    case .needsYou: [.doubleBlink]
    case .yourTurn: [.lookAround, .doubleBlink, .wink]
    case .idle: [.yawn]
    }
  }

  private static func ambientInterval(for status: ClaudeSessionStatus) -> ClosedRange<TimeInterval> {
    switch status {
    case .working: 5...10
    case .needsYou: 3...6
    case .yourTurn: 8...16
    case .idle: 25...50
    }
  }

  /// Gesture played when the session enters `status`.
  private func greet(_ status: ClaudeSessionStatus) {
    switch status {
    case .needsYou: gestureTrigger.play(.startle)
    case .yourTurn: gestureTrigger.play(.giggle)
    case .working, .idle: break
    }
  }

  /// Hook events come in bursts during a turn: keep reactions occasional so they stay
  /// readable, and let failures through more often than successes.
  private func react(to kind: ClaudeSessionReaction.Kind) {
    guard session.status == .working else { return }
    let now = Date()
    let gesture: EyeGesture?
    switch kind {
    case .toolFailed:
      gesture = now.timeIntervalSince(lastReactionDate) > 1.5 ? .wince : nil
    case .subagentStarted:
      gesture = now.timeIntervalSince(lastReactionDate) > 3 ? .lookAround : nil
    case .promptReceived:
      gesture = .aha
    case .toolSucceeded:
      gesture = now.timeIntervalSince(lastReactionDate) > 6 && Double.random(in: 0..<1) < 0.3 ? .wink : nil
    }
    guard let gesture else { return }
    lastReactionDate = now
    gestureTrigger.play(gesture)
  }

  @ViewBuilder
  private var badge: some View {
    let offset = dock.badgeOffset

    switch session.status {
    case .needsYou:
      Text("!")
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 16, height: 16)
        .background(.orange, in: Circle())
        .overlay {
          Circle().strokeBorder(.white, lineWidth: 1.5)
        }
        .offset(x: offset.dx * 6, y: offset.dy * 7)
    case .yourTurn:
      PulsingDot(pulses: !reduceMotion)
        .id(reduceMotion)
        .offset(x: offset.dx * 3, y: offset.dy * 3)
    case .working, .idle:
      EmptyView()
    }
  }

  private var label: some View {
    Text(session.projectName)
      .font(.system(size: 10, weight: .semibold))
      .sessionLabelCapsule()
  }

  private var haloColor: Color {
    switch session.status {
    case .needsYou: .orange.opacity(0.8)
    case .working: .blue.opacity(0.7)
    case .yourTurn, .idle: .clear
    }
  }

  private var breathingPeriod: Double? {
    if reduceMotion { return nil }

    switch session.status {
    case .working: return 1.5
    case .needsYou: return 2.2
    case .yourTurn: return 2.8
    case .idle: return nil
    }
  }

  private var helpText: String {
    "\(session.projectName) — \(statusDescription)"
  }

  private var statusDescription: String {
    switch session.status {
    case .working: "Travaille…"
    case .needsYou: "A besoin de toi"
    case .yourTurn: "A fini, à toi"
    case .idle: "En attente"
    }
  }

  /// Gaze before the mood's bias (the sleepy and focused moods already look down).
  private func gaze(at time: TimeInterval) -> HeadGaze {
    switch session.status {
    case .idle:
      return Self.sleepyGaze
    case .working:
      return reduceMotion ? .zero : EyeProjection.readingGaze(at: time)
    case .needsYou, .yourTurn:
      return reduceMotion ? .zero : EyeProjection.gaze(towardOffset: pointerOffset())
    }
  }

  private static let sleepyGaze = HeadGaze(yaw: 0, pitch: -4, roll: 0)

  private func animateStatus() async {
    guard !reduceMotion else { return }

    switch session.status {
    case .needsYou:
      while !Task.isCancelled {
        hopCount += 1

        do {
          try await Task.sleep(for: .seconds(1.5))
        } catch {
          return
        }
      }
    case .yourTurn:
      wiggleCount += 1
    case .working, .idle:
      break
    }
  }
}

/// The screen edge a session mascot sticks to, which orients its label, badge and hop.
enum SessionMascotDock: Equatable {
  case floating, bottom, top, left, right

  init(_ edges: MascotAttachmentEdges) {
    if edges.contains(.bottom) {
      self = .bottom
    } else if edges.contains(.top) {
      self = .top
    } else if edges.contains(.left) {
      self = .left
    } else if edges.contains(.right) {
      self = .right
    } else {
      self = .floating
    }
  }

  var hopsSideways: Bool { self == .left || self == .right }

  var wallEdge: Edge.Set {
    switch self {
    case .floating: []
    case .bottom: .bottom
    case .top: .top
    case .left: .leading
    case .right: .trailing
    }
  }

  /// Unit hop direction in SwiftUI space (y down), away from the edge.
  var hopDirection: CGVector {
    switch self {
    case .floating, .bottom: CGVector(dx: 0, dy: -1)
    case .top: CGVector(dx: 0, dy: 1)
    case .left: CGVector(dx: 1, dy: 0)
    case .right: CGVector(dx: -1, dy: 0)
    }
  }

  /// Point on the silhouette's edge side, in the frame that includes the join margin.
  func anchor(bodySize: CGSize, margin: CGFloat) -> UnitPoint {
    let width = bodySize.width + margin * 2
    let height = bodySize.height + margin * 2
    switch self {
    case .floating, .bottom: return UnitPoint(x: 0.5, y: (margin + bodySize.height) / height)
    case .top: return UnitPoint(x: 0.5, y: margin / height)
    case .left: return UnitPoint(x: margin / width, y: 0.5)
    case .right: return UnitPoint(x: (margin + bodySize.width) / width, y: 0.5)
    }
  }

  /// The badge sits on the inner corner, away from the edge.
  var badgeAlignment: Alignment {
    switch self {
    case .floating, .bottom, .left: .topTrailing
    case .top: .bottomTrailing
    case .right: .topLeading
    }
  }

  /// Signs of the badge offset that push it past `badgeAlignment`'s corner.
  var badgeOffset: CGVector {
    switch self {
    case .floating, .bottom, .left: CGVector(dx: 1, dy: -1)
    case .top: CGVector(dx: 1, dy: 1)
    case .right: CGVector(dx: -1, dy: -1)
    }
  }

  var labelAlignment: Alignment {
    switch self {
    case .floating, .bottom, .top: .center
    case .left: .leading
    case .right: .trailing
    }
  }
}

extension View {
  /// Centers the view on `frame`, given in session window coordinates (y up).
  func position(inSessionWindow frame: CGRect) -> some View {
    position(x: frame.midX, y: SessionMascotView.windowSize.height - frame.midY)
  }

  /// Capsule behind the text under a session mascot or the usage gauge.
  func sessionLabelCapsule() -> some View {
    lineLimit(1)
      .foregroundStyle(.primary)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
      }
      .frame(maxWidth: SessionMascotView.labelSize.width)
  }
}

extension MascotColor {
  var swiftUIColor: Color {
    Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
  }
}

private struct MotionKey: Equatable {
  let status: ClaudeSessionStatus
  let reduceMotion: Bool
}

private struct HopPose {
  var lift: CGFloat = 0
  var stretch: CGFloat = 1
}

private struct PulsingDot: View {
  let pulses: Bool

  @State private var isRippling = false

  var body: some View {
    Circle()
      .fill(.green)
      .frame(width: 10, height: 10)
      .overlay {
        Circle().strokeBorder(.black.opacity(0.85), lineWidth: 1.5)
      }
      .background {
        Circle()
          .fill(.green.opacity(0.5))
          .scaleEffect(isRippling ? 2.2 : 1)
          .opacity(isRippling ? 0 : 1)
      }
      .onAppear {
        guard pulses else { return }

        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
          isRippling = true
        }
      }
  }
}

#Preview {
  let statuses: [(String, ClaudeSessionStatus, MascotAttachmentEdges)] = [
    ("timi", .working, []),
    ("api-gateway", .needsYou, .bottom),
    ("un-projet-au-nom-tres-long", .yourTurn, .left),
    ("docs", .idle, .top),
  ]

  HStack(spacing: 8) {
    ForEach(Array(statuses.enumerated()), id: \.offset) { index, entry in
      SessionMascotView(
        session: ClaudeSession(
          id: "\(index)",
          projectName: entry.0,
          status: entry.1,
          context: ClaudeHookContext()
        ),
        edges: entry.2,
        color: MascotColor.allCases[index * 2],
        pointerOffset: { CGVector(dx: 120, dy: 60) }
      )
      .border(.secondary.opacity(0.3))
    }
  }
  .padding()
}
