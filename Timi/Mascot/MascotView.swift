import SwiftUI

@MainActor
final class MascotInteractionState: ObservableObject {
  @Published private(set) var clickCount = 0
  @Published private(set) var attachmentEdges: MascotAttachmentEdges = []
  var activationHandler: (() -> Void)?

  func activate() {
    clickCount += 1
    activationHandler?()
  }

  func updateAttachmentEdges(_ edges: MascotAttachmentEdges) {
    attachmentEdges = edges
  }
}

struct MascotView: View {
  @ObservedObject var interactionState: MascotInteractionState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isBreathing = false
  @State private var isHovering = false
  @State private var isReacting = false
  @State private var eyesAreOpen = true

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

      sphericalEyes
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
    .accessibilityLabel("Timi mascot")
    .accessibilityHint("Activate to open the conversation. Use Settings to move Timi.")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      interactionState.activate()
    }
  }

  private var sphericalEyes: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
      Canvas { context, size in
        let projectionRadius = min(size.width, size.height) / 2
        let eyeScale: CGFloat = 72
        let gaze = reduceMotion
          ? EyeProjection.restingGaze
          : EyeProjection.wanderingGaze(at: timeline.date.timeIntervalSinceReferenceDate)
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

private struct MascotPreviewBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [.purple, .pink],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
      )

      MascotView(interactionState: MascotInteractionState())
    }
    .frame(width: 260, height: 180)
  }
}

struct MascotView_Previews: PreviewProvider {
  static var previews: some View {
    MascotPreviewBackground()
  }
}
