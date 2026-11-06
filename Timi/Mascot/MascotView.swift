import SwiftUI

@MainActor
final class MascotInteractionState: ObservableObject {
  @Published private(set) var clickCount = 0
  @Published private(set) var attachmentEdges: MascotAttachmentEdges = []
  @Published private(set) var eyesArePaused = false
  var activationHandler: (() -> Void)?
  var pointerOffsetProvider: (() -> CGVector?)?

  func activate() {
    clickCount += 1
    activationHandler?()
  }

  func updateAttachmentEdges(_ edges: MascotAttachmentEdges) {
    // Called on every drag step: @Published would redraw the mascot even when unchanged.
    guard edges != attachmentEdges else { return }
    attachmentEdges = edges
  }

  func updateEyesArePaused(_ isPaused: Bool) {
    guard isPaused != eyesArePaused else { return }
    eyesArePaused = isPaused
  }
}

struct MascotView: View {
  static let cornerRadius: CGFloat = 22
  static let eyeScale: CGFloat = 72
  static let glowRadius: CGFloat = 4

  @ObservedObject var interactionState: MascotInteractionState
  @ObservedObject var dictationCoordinator: DictationCoordinator
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isHovering = false
  @State private var isReacting = false
  @State private var gestureTrigger: GestureTrigger?
  @State private var recentClicks: [Date] = []

  private var silhouette: MascotSilhouette {
    MascotSilhouette(
      attachmentEdges: interactionState.attachmentEdges,
      cornerRadius: Self.cornerRadius
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
          x: reduceMotion ? 1 : (isReacting ? 1.025 : (isHovering ? 1.012 : 1)),
          y: reduceMotion ? 1 : (isReacting ? 0.975 : (isHovering ? 1.012 : 1))
        )
        .modifier(
          Breathing(
            period: reduceMotion || interactionState.eyesArePaused ? nil : 2.6,
            inhale: CGSize(width: 1.006, height: 1.012),
            exhale: CGSize(width: 0.994, height: 0.988)
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
      if hovering { gestureTrigger.play(.aha) }
    }
    .onChange(of: interactionState.clickCount) {
      reactToClick()
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
    AnimatedEyes(
      mood: isHovering ? .content : .neutral,
      gaze: currentGaze(at:),
      trigger: gestureTrigger,
      eyeScale: Self.eyeScale,
      ambientGestures: [.lookAround, .lookAround, .doubleBlink, .glanceUp, .wink, .yawn],
      ambientInterval: 9...20,
      isPaused: interactionState.eyesArePaused,
      glowRadius: Self.glowRadius
    )
    .frame(
      width: MascotWindowController.mascotSize.width,
      height: MascotWindowController.mascotSize.height
    )
  }

  private func currentGaze(at time: TimeInterval) -> HeadGaze {
    if reduceMotion { return EyeProjection.restingGaze }

    return interactionState.pointerOffsetProvider?().map(EyeProjection.gaze(towardOffset:))
      ?? EyeProjection.wanderingGaze(at: time)
  }

  private func reactToClick() {
    isReacting = true

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      isReacting = false
    }

    // Three quick clicks leave Timi dizzy; a single one makes it giggle.
    let now = Date()
    recentClicks = recentClicks.filter { now.timeIntervalSince($0) < 1.2 } + [now]
    if recentClicks.count >= 3 {
      recentClicks = []
      gestureTrigger.play(.dizzy)
    } else {
      gestureTrigger.play(.giggle)
    }
  }
}

/// Slow, endless squash and stretch of a mascot. `period` is one breath in or out; nil
/// holds the view still at its natural size.
struct Breathing: ViewModifier {
  let period: Double?
  /// Scales at the top of an inhale and at the bottom of an exhale.
  let inhale: CGSize
  let exhale: CGSize
  var anchor: UnitPoint = .center

  @State private var isInhaling = false

  func body(content: Content) -> some View {
    let scale = period == nil ? CGSize(width: 1, height: 1) : (isInhaling ? inhale : exhale)

    content
      .scaleEffect(x: scale.width, y: scale.height, anchor: anchor)
      // One finite animation per breath rather than `repeatForever`, which only a new view
      // identity can stop: a new pace (or none) then takes over without resetting the face.
      .task(id: period) {
        guard let period else { return }

        while !Task.isCancelled {
          withAnimation(.easeInOut(duration: period)) {
            isInhaling.toggle()
          }
          do {
            try await Task.sleep(for: .seconds(period))
          } catch {
            return
          }
        }
      }
  }
}

struct MascotSilhouette: Shape {
  let attachmentEdges: MascotAttachmentEdges
  let cornerRadius: CGFloat
  /// Room around the body for the joins drawn toward attached edges.
  var margin: CGFloat = MascotWindowController.drawingMargin

  func path(in rect: CGRect) -> Path {
    let body = rect.insetBy(dx: margin, dy: margin)
    let radius = min(cornerRadius, min(body.width, body.height) / 2)
    let top = attachmentEdges.contains(.top)
    let right = attachmentEdges.contains(.right)
    let bottom = attachmentEdges.contains(.bottom)
    let left = attachmentEdges.contains(.left)

    let topLeft = Corner(
      at: CGPoint(x: body.minX, y: body.minY),
      inward: CGVector(dx: 1, dy: 1),
      radius: radius,
      onHorizontalEdge: top,
      onVerticalEdge: left
    )
    let topRight = Corner(
      at: CGPoint(x: body.maxX, y: body.minY),
      inward: CGVector(dx: -1, dy: 1),
      radius: radius,
      onHorizontalEdge: top,
      onVerticalEdge: right
    )
    let bottomRight = Corner(
      at: CGPoint(x: body.maxX, y: body.maxY),
      inward: CGVector(dx: -1, dy: -1),
      radius: radius,
      onHorizontalEdge: bottom,
      onVerticalEdge: right
    )
    let bottomLeft = Corner(
      at: CGPoint(x: body.minX, y: body.maxY),
      inward: CGVector(dx: 1, dy: -1),
      radius: radius,
      onHorizontalEdge: bottom,
      onVerticalEdge: left
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

  /// A rounded body corner. Along an attached edge the curve flares outward instead, into
  /// the join with the screen edge; between two attached edges the corner stays square.
  private struct Corner {
    let horizontalPoint: CGPoint
    let verticalPoint: CGPoint
    let controlPoint: CGPoint

    /// `inward` points from the corner toward the body's center, one unit per axis.
    init(
      at point: CGPoint,
      inward: CGVector,
      radius: CGFloat,
      onHorizontalEdge: Bool,
      onVerticalEdge: Bool
    ) {
      controlPoint = point
      if onHorizontalEdge, onVerticalEdge {
        horizontalPoint = point
        verticalPoint = point
      } else {
        horizontalPoint = CGPoint(x: point.x + inward.dx * (onHorizontalEdge ? -radius : radius), y: point.y)
        verticalPoint = CGPoint(x: point.x, y: point.y + inward.dy * (onVerticalEdge ? -radius : radius))
      }
    }
  }
}
