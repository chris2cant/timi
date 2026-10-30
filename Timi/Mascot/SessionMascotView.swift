import SwiftUI

struct SessionMascotView: View {
  nonisolated static let silhouetteSize = CGSize(width: 60, height: 42)
  nonisolated private static let cornerRadius: CGFloat = 10
  /// Room around the silhouette for the joins drawn toward an attached screen edge.
  nonisolated private static let joinMargin: CGFloat = 10
  nonisolated private static let labelSize = CGSize(width: 70, height: 16)
  // Room between silhouette and label for the hop and the "!" bubble.
  nonisolated private static let labelGap: CGFloat = 19

  /// Size of the panel hosting one session mascot, label included.
  nonisolated static let windowSize = CGSize(width: 84, height: 80)

  /// Silhouette and label frames in window coordinates (origin bottom-left, y up).
  /// The silhouette touches the window side facing the attached screen edge, and the
  /// label sits on the inner side.
  nonisolated static func frames(for edges: MascotAttachmentEdges) -> (body: CGRect, label: CGRect) {
    let width = windowSize.width
    let height = windowSize.height
    let body = silhouetteSize
    let label = labelSize
    let centeredX = (width - body.width) / 2
    let centeredLabelX = (width - label.width) / 2

    switch Dock(edges) {
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
      let isLeft = Dock(edges) == .left
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
  /// Pointer offset from the mascot center (screen space, y up), for eye tracking.
  let pointerOffset: () -> CGVector

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var eyesAreOpen = true
  @State private var hopCount = 0
  @State private var wiggleCount = 0

  private var dock: Dock { Dock(edges) }

  var body: some View {
    let frames = Self.frames(for: edges)

    ZStack(alignment: .topLeading) {
      mascot
        .position(x: frames.body.midX, y: Self.windowSize.height - frames.body.midY)
      label
        .frame(width: frames.label.width, height: frames.label.height, alignment: dock.labelAlignment)
        .position(x: frames.label.midX, y: Self.windowSize.height - frames.label.midY)
    }
    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    .help(helpText)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(helpText)
    .task(id: session.status) {
      await blinkPeriodically()
    }
    .task(id: MotionKey(status: session.status, reduceMotion: reduceMotion)) {
      await animateStatus()
    }
  }

  private var mascot: some View {
    let shape = MascotSilhouette(
      attachmentEdges: edges,
      cornerRadius: Self.cornerRadius,
      margin: Self.joinMargin
    )
    let size = Self.silhouetteSize
    let anchor = dock.anchor(bodySize: size, margin: Self.joinMargin)

    return ZStack {
      shape
        .fill(.black)
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
    .frame(width: size.width + Self.joinMargin * 2, height: size.height + Self.joinMargin * 2)
    .modifier(Breathing(period: breathingPeriod, anchor: anchor))
    // A new identity restarts the repeating animation at the new pace.
    .id(breathingPeriod)
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
    // Idle eyes are still: no timeline ticking. Reduce Motion freezes the gaze too.
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || session.status == .idle)) { timeline in
      let gaze = gaze(at: timeline.date.timeIntervalSinceReferenceDate)
      let eyes = EyeProjection.eyes(for: gaze, radius: Self.silhouetteSize.height / 2)
      let eyeScale: CGFloat = session.status == .needsYou ? 34 : 30
      let lidScale = lidScale

      Canvas { context, size in
        let width = EyeProjection.eyeWidth * eyeScale
        let height = EyeProjection.eyeHeight * eyeScale
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 1)
        let capsule = Path(
          roundedRect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
          cornerRadius: width / 2
        )

        for eye in eyes where eye.depth > 0.02 {
          let transform = CGAffineTransform(
            a: eye.a,
            b: eye.b * lidScale,
            c: eye.c,
            d: eye.d * lidScale,
            tx: center.x + eye.x,
            ty: center.y + eye.y
          )
          let opacity = min(1, eye.depth / 0.12) * 0.96
          context.fill(capsule.applying(transform), with: .color(.white.opacity(opacity)))
        }
      }
    }
    .accessibilityHidden(true)
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
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(.primary)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
      }
      .frame(maxWidth: Self.labelSize.width)
  }

  private var haloColor: Color {
    switch session.status {
    case .needsYou: .orange.opacity(0.8)
    case .working: .blue.opacity(0.7)
    case .yourTurn, .idle: .clear
    }
  }

  private var lidScale: CGFloat {
    if !eyesAreOpen { return 0.08 }
    return session.status == .idle ? 0.42 : 1
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

  private func gaze(at time: TimeInterval) -> HeadGaze {
    switch session.status {
    case .idle:
      return Self.sleepyGaze
    case .working:
      return reduceMotion ? Self.readingGaze(progress: 0.5) : Self.readingGaze(at: time)
    case .needsYou, .yourTurn:
      return reduceMotion ? Self.facingGaze : EyeProjection.gaze(towardOffset: pointerOffset())
    }
  }

  private static let sleepyGaze = HeadGaze(yaw: 0, pitch: -14, roll: 0)
  private static let facingGaze = HeadGaze(yaw: 0, pitch: 0, roll: 0)
  private static let readingPeriod: TimeInterval = 2.2

  /// Slow left-to-right sweep with a quick return, like reading lines of text.
  private static func readingGaze(at time: TimeInterval) -> HeadGaze {
    let progress = time.truncatingRemainder(dividingBy: readingPeriod) / readingPeriod
    let sweep = progress < 0.82 ? progress / 0.82 : 1 - (progress - 0.82) / 0.18
    return readingGaze(progress: sweep)
  }

  private static func readingGaze(progress: Double) -> HeadGaze {
    let eased = progress * progress * (3 - 2 * progress)
    return HeadGaze(yaw: CGFloat(eased) * 40 - 20, pitch: -6, roll: 0)
  }

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

  private func blinkPeriodically() async {
    eyesAreOpen = true
    guard session.status != .idle else { return }

    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(Double.random(in: 3.5...7)))
      } catch {
        return
      }

      eyesAreOpen = false

      do {
        try await Task.sleep(for: .milliseconds(130))
      } catch {
        eyesAreOpen = true
        return
      }

      eyesAreOpen = true
    }
  }
}

/// The screen edge a session mascot sticks to, which orients its label, badge and hop.
private enum Dock: Equatable {
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

private struct MotionKey: Equatable {
  let status: ClaudeSessionStatus
  let reduceMotion: Bool
}

private struct HopPose {
  var lift: CGFloat = 0
  var stretch: CGFloat = 1
}

private struct Breathing: ViewModifier {
  let period: Double?
  let anchor: UnitPoint

  @State private var isInhaling = false

  func body(content: Content) -> some View {
    content
      .scaleEffect(
        x: period == nil ? 1 : (isInhaling ? 1.012 : 0.994),
        y: period == nil ? 1 : (isInhaling ? 1.024 : 0.988),
        anchor: anchor
      )
      .onAppear {
        guard let period else { return }

        withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
          isInhaling = true
        }
      }
  }
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
        pointerOffset: { CGVector(dx: 120, dy: 60) }
      )
      .border(.secondary.opacity(0.3))
    }
  }
  .padding()
}
