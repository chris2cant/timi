import SwiftUI

@MainActor
final class MascotInteractionState: ObservableObject {
  @Published private(set) var clickCount = 0
  @Published private(set) var attachmentEdges: MascotAttachmentEdges = []
  var activationHandler: (() -> Void)?
  var pointerOffsetProvider: (() -> CGVector?)?

  func activate() {
    clickCount += 1
    activationHandler?()
  }

  func updateAttachmentEdges(_ edges: MascotAttachmentEdges) {
    attachmentEdges = edges
  }
}

/// Smooths the gaze between frames. Reference type on purpose: it is mutated
/// from the `TimelineView` body and must not trigger SwiftUI invalidations.
@MainActor
private final class GazeSmoother {
  private var current: HeadGaze?
  private var lastTime: TimeInterval?
  private let responseTime: TimeInterval = 0.08

  func smoothed(toward target: HeadGaze, at time: TimeInterval) -> HeadGaze {
    defer { lastTime = time }
    guard let current, let lastTime else {
      self.current = target
      return target
    }

    let dt = max(0, min(time - lastTime, 0.25))
    let k = CGFloat(1 - exp(-dt / responseTime))
    let next = HeadGaze(
      yaw: current.yaw + (target.yaw - current.yaw) * k,
      pitch: current.pitch + (target.pitch - current.pitch) * k,
      roll: current.roll + (target.roll - current.roll) * k
    )
    self.current = next
    return next
  }
}

struct MascotView: View {
  @ObservedObject var interactionState: MascotInteractionState
  @ObservedObject var dictationCoordinator: DictationCoordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isBreathing = false
  @State private var isHovering = false
  @State private var isReacting = false
  @State private var eyesAreOpen = true
  @State private var gazeSmoother = GazeSmoother()

  private let cornerRadius: CGFloat = 22

  private var silhouette: MascotSilhouette {
    MascotSilhouette(
      attachmentEdges: interactionState.attachmentEdges,
      cornerRadius: cornerRadius
    )
  }

  var body: some View {
    ZStack {
      silhouette
        .fill(.black)

      Group {
        if dictationCoordinator.phase == .idle {
          sphericalEyes
        } else {
          dictationStatus
        }
      }
        // The silhouette is expressed in the panel's coordinate space because it
        // includes the drawing margin used by the edge attachments. Keep the mask
        // at that size even when its content has a smaller intrinsic frame.
        .frame(
          width: MascotWindowController.windowSize.width,
          height: MascotWindowController.windowSize.height
        )
        .mask {
          silhouette
        }
        .scaleEffect(
          x: motionScale(
            breathing: isBreathing ? 1.006 : 0.994,
            interaction: isReacting ? 1.025 : (isHovering ? 1.012 : 1)
          ),
          y: motionScale(
            breathing: isBreathing ? 1.012 : 0.988,
            interaction: isReacting ? 0.975 : (isHovering ? 1.012 : 1)
          )
        )
    }
    .frame(
      width: MascotWindowController.windowSize.width,
      height: MascotWindowController.windowSize.height
    )
    .contentShape(silhouette)
    .onHover { hovering in
      isHovering = hovering
    }
    .onAppear {
      updateBreathing()
    }
    .onChange(of: reduceMotion) {
      updateBreathing()
    }
    .onChange(of: interactionState.clickCount) {
      reactToClick()
    }
    .task {
      await blinkPeriodically()
    }
    .animation(reduceMotion ? nil : .spring(duration: 0.22), value: isHovering)
    .animation(reduceMotion ? nil : .spring(duration: 0.2), value: isReacting)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(
      dictationCoordinator.phase.isActive
        ? "Activer pour arrêter la dictée."
        : "Activer pour ouvrir la conversation. Utiliser Réglages pour déplacer Timi."
    )
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      interactionState.activate()
    }
  }

  private var dictationStatus: some View {
    VStack(spacing: 5) {
      HStack(spacing: 5) {
        statusSymbol
        Text(statusTitle)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .lineLimit(1)
      }
      .foregroundStyle(statusColor)

      if dictationCoordinator.phase == .listening || dictationCoordinator.phase == .preparing {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
          Text(elapsedText)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.78))
        }

        HStack(alignment: .center, spacing: 3) {
          ForEach(Array(dictationCoordinator.meterLevels.enumerated()), id: \.offset) { _, level in
            Capsule()
              .fill(dictationCoordinator.isSilent ? Color.orange : Color.white)
              .frame(width: 5, height: barHeight(level))
              .animation(
                reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.08),
                value: reduceMotion ? (level > 0.15 ? Float(1) : Float(0)) : level
              )
          }
        }
        .frame(height: 25)

        if dictationCoordinator.isSilent {
          Text("Aucun son détecté")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
        }
      }
    }
    .frame(
      width: MascotWindowController.mascotSize.width - 22,
      height: MascotWindowController.mascotSize.height - 14
    )
  }

  @ViewBuilder
  private var statusSymbol: some View {
    switch dictationCoordinator.phase {
    case .listening, .preparing:
      Circle().fill(.green).frame(width: 7, height: 7)
    case .succeeded:
      Image(systemName: "checkmark.circle.fill")
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
    default:
      EmptyView()
    }
  }

  private var statusTitle: String {
    if dictationCoordinator.isSilent { return "J’écoute" }
    return switch dictationCoordinator.phase {
    case .idle: ""
    case .preparing: "Je prépare…"
    case .listening: "J’écoute"
    case .finalizing: "Je transcris…"
    case .refining: "Je nettoie…"
    case .inserting: "J’insère…"
    case .succeeded(.pasted): "Collé"
    case .succeeded(.copied): "Copié"
    case .failed(let message): message
    }
  }

  private var statusColor: Color {
    if dictationCoordinator.isSilent { return .orange }
    if case .failed = dictationCoordinator.phase { return .red }
    return .white
  }

  private var elapsedText: String {
    let seconds = Int(Date().timeIntervalSince(dictationCoordinator.startedAt ?? .now))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
  }

  private func barHeight(_ level: Float) -> CGFloat {
    let displayedLevel = reduceMotion ? (level > 0.15 ? 0.55 : 0.08) : level
    return 3 + CGFloat(displayedLevel) * 22
  }

  private var accessibilityLabel: String {
    statusTitle.isEmpty ? "Timi" : "Timi, \(statusTitle)"
  }

  private var sphericalEyes: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
      let gaze = currentGaze(at: timeline.date.timeIntervalSinceReferenceDate)
      Canvas { context, size in
        let projectionRadius = min(size.width, size.height) / 2
        let eyeScale: CGFloat = 72
        let eyes = EyeProjection.eyes(for: gaze, radius: projectionRadius)
        let width = EyeProjection.eyeWidth * eyeScale
        let height = EyeProjection.eyeHeight * eyeScale
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + 1)
        let blinkScale: CGFloat = eyesAreOpen ? 1 : 0.06
        let capsule = Path(
          roundedRect: CGRect(
            x: -width / 2,
            y: -height / 2,
            width: width,
            height: height
          ),
          cornerRadius: width / 2
        )

        for eye in eyes where eye.depth > 0.02 {
          let transform = CGAffineTransform(
            a: eye.a,
            b: eye.b * blinkScale,
            c: eye.c,
            d: eye.d * blinkScale,
            tx: center.x + eye.x,
            ty: center.y + eye.y
          )
          let opacity = min(1, eye.depth / 0.12) * 0.96
          context.fill(
            capsule.applying(transform),
            with: .color(.white.opacity(opacity))
          )
        }
      }
    }
    .frame(
      width: MascotWindowController.mascotSize.width,
      height: MascotWindowController.mascotSize.height
    )
    .animation(.easeInOut(duration: 0.09), value: eyesAreOpen)
    .accessibilityHidden(true)
  }

  private func currentGaze(at time: TimeInterval) -> HeadGaze {
    if reduceMotion { return EyeProjection.restingGaze }

    let target = interactionState.pointerOffsetProvider?().map(EyeProjection.gaze(towardOffset:))
      ?? EyeProjection.wanderingGaze(at: time)
    return gazeSmoother.smoothed(toward: target, at: time)
  }

  private func motionScale(breathing: CGFloat, interaction: CGFloat) -> CGFloat {
    reduceMotion ? 1 : breathing * interaction
  }

  private func updateBreathing() {
    if reduceMotion {
      withAnimation(.linear(duration: 0.01)) {
        isBreathing = false
      }
    } else {
      withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
        isBreathing = true
      }
    }
  }

  private func reactToClick() {
    isReacting = true

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      isReacting = false
    }
  }

  @MainActor
  private func blinkPeriodically() async {
    while !Task.isCancelled {
      do {
        try await Task.sleep(for: .seconds(Double.random(in: 3.5...6.5)))
      } catch {
        return
      }

      eyesAreOpen = false

      do {
        try await Task.sleep(for: .milliseconds(130))
      } catch {
        return
      }

      eyesAreOpen = true
    }
  }
}

private struct MascotSilhouette: Shape {
  let attachmentEdges: MascotAttachmentEdges
  let cornerRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    let bodyRect = rect.insetBy(
      dx: MascotWindowController.drawingMargin,
      dy: MascotWindowController.drawingMargin
    )
    let radius = min(cornerRadius, min(bodyRect.width, bodyRect.height) / 2)
    let top = attachmentEdges.contains(.top)
    let right = attachmentEdges.contains(.right)
    let bottom = attachmentEdges.contains(.bottom)
    let left = attachmentEdges.contains(.left)

    let topLeft = topLeftCorner(in: bodyRect, radius: radius, top: top, left: left)
    let topRight = topRightCorner(in: bodyRect, radius: radius, top: top, right: right)
    let bottomRight = bottomRightCorner(
      in: bodyRect,
      radius: radius,
      bottom: bottom,
      right: right
    )
    let bottomLeft = bottomLeftCorner(
      in: bodyRect,
      radius: radius,
      bottom: bottom,
      left: left
    )

    var path = Path()
    path.move(to: topLeft.horizontalPoint)
    path.addLine(to: topRight.horizontalPoint)
    path.addQuadCurve(to: topRight.verticalPoint, control: topRight.controlPoint)
    path.addLine(to: bottomRight.verticalPoint)
    path.addQuadCurve(to: bottomRight.horizontalPoint, control: bottomRight.controlPoint)
    path.addLine(to: bottomLeft.horizontalPoint)
    path.addQuadCurve(to: bottomLeft.verticalPoint, control: bottomLeft.controlPoint)
    path.addLine(to: topLeft.verticalPoint)
    path.addQuadCurve(to: topLeft.horizontalPoint, control: topLeft.controlPoint)
    path.closeSubpath()
    return path
  }

  private struct Corner {
    let horizontalPoint: CGPoint
    let verticalPoint: CGPoint
    let controlPoint: CGPoint
  }

  private func topLeftCorner(
    in rect: CGRect,
    radius: CGFloat,
    top: Bool,
    left: Bool
  ) -> Corner {
    if top, left {
      let point = CGPoint(x: rect.minX, y: rect.minY)
      return Corner(horizontalPoint: point, verticalPoint: point, controlPoint: point)
    }
    if top {
      return Corner(
        horizontalPoint: CGPoint(x: rect.minX - radius, y: rect.minY),
        verticalPoint: CGPoint(x: rect.minX, y: rect.minY + radius),
        controlPoint: CGPoint(x: rect.minX, y: rect.minY)
      )
    }
    if left {
      return Corner(
        horizontalPoint: CGPoint(x: rect.minX + radius, y: rect.minY),
        verticalPoint: CGPoint(x: rect.minX, y: rect.minY - radius),
        controlPoint: CGPoint(x: rect.minX, y: rect.minY)
      )
    }
    return Corner(
      horizontalPoint: CGPoint(x: rect.minX + radius, y: rect.minY),
      verticalPoint: CGPoint(x: rect.minX, y: rect.minY + radius),
      controlPoint: CGPoint(x: rect.minX, y: rect.minY)
    )
  }

  private func topRightCorner(
    in rect: CGRect,
    radius: CGFloat,
    top: Bool,
    right: Bool
  ) -> Corner {
    if top, right {
      let point = CGPoint(x: rect.maxX, y: rect.minY)
      return Corner(horizontalPoint: point, verticalPoint: point, controlPoint: point)
    }
    if top {
      return Corner(
        horizontalPoint: CGPoint(x: rect.maxX + radius, y: rect.minY),
        verticalPoint: CGPoint(x: rect.maxX, y: rect.minY + radius),
        controlPoint: CGPoint(x: rect.maxX, y: rect.minY)
      )
    }
    if right {
      return Corner(
        horizontalPoint: CGPoint(x: rect.maxX - radius, y: rect.minY),
        verticalPoint: CGPoint(x: rect.maxX, y: rect.minY - radius),
        controlPoint: CGPoint(x: rect.maxX, y: rect.minY)
      )
    }
    return Corner(
      horizontalPoint: CGPoint(x: rect.maxX - radius, y: rect.minY),
      verticalPoint: CGPoint(x: rect.maxX, y: rect.minY + radius),
      controlPoint: CGPoint(x: rect.maxX, y: rect.minY)
    )
  }

  private func bottomRightCorner(
    in rect: CGRect,
    radius: CGFloat,
    bottom: Bool,
    right: Bool
  ) -> Corner {
    if bottom, right {
      let point = CGPoint(x: rect.maxX, y: rect.maxY)
      return Corner(horizontalPoint: point, verticalPoint: point, controlPoint: point)
    }
    if bottom {
      return Corner(
        horizontalPoint: CGPoint(x: rect.maxX + radius, y: rect.maxY),
        verticalPoint: CGPoint(x: rect.maxX, y: rect.maxY - radius),
        controlPoint: CGPoint(x: rect.maxX, y: rect.maxY)
      )
    }
    if right {
      return Corner(
        horizontalPoint: CGPoint(x: rect.maxX - radius, y: rect.maxY),
        verticalPoint: CGPoint(x: rect.maxX, y: rect.maxY + radius),
        controlPoint: CGPoint(x: rect.maxX, y: rect.maxY)
      )
    }
    return Corner(
      horizontalPoint: CGPoint(x: rect.maxX - radius, y: rect.maxY),
      verticalPoint: CGPoint(x: rect.maxX, y: rect.maxY - radius),
      controlPoint: CGPoint(x: rect.maxX, y: rect.maxY)
    )
  }

  private func bottomLeftCorner(
    in rect: CGRect,
    radius: CGFloat,
    bottom: Bool,
    left: Bool
  ) -> Corner {
    if bottom, left {
      let point = CGPoint(x: rect.minX, y: rect.maxY)
      return Corner(horizontalPoint: point, verticalPoint: point, controlPoint: point)
    }
    if bottom {
      return Corner(
        horizontalPoint: CGPoint(x: rect.minX - radius, y: rect.maxY),
        verticalPoint: CGPoint(x: rect.minX, y: rect.maxY - radius),
        controlPoint: CGPoint(x: rect.minX, y: rect.maxY)
      )
    }
    if left {
      return Corner(
        horizontalPoint: CGPoint(x: rect.minX + radius, y: rect.maxY),
        verticalPoint: CGPoint(x: rect.minX, y: rect.maxY + radius),
        controlPoint: CGPoint(x: rect.minX, y: rect.maxY)
      )
    }
    return Corner(
      horizontalPoint: CGPoint(x: rect.minX + radius, y: rect.maxY),
      verticalPoint: CGPoint(x: rect.minX, y: rect.maxY - radius),
      controlPoint: CGPoint(x: rect.minX, y: rect.maxY)
    )
  }
}
