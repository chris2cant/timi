import SwiftUI

@MainActor
final class MascotInteractionState: ObservableObject {
  @Published private(set) var clickCount = 0

  func reactToClick() {
    clickCount += 1
  }
}

struct MascotView: View {
  @ObservedObject var interactionState: MascotInteractionState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isBreathing = false
  @State private var isHovering = false
  @State private var isReacting = false
  @State private var eyesAreOpen = true

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color(red: 0.008, green: 0.008, blue: 0.012))
        .overlay {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(.white.opacity(0.045), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 7, y: 3)

      VStack(spacing: 7) {
        HStack(spacing: 35) {
          eye
          eye
        }

        SmileShape()
          .stroke(
            .white.opacity(0.95),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
          )
          .frame(width: isReacting ? 42 : 36, height: isReacting ? 15 : 12)
          .shadow(color: .white.opacity(0.18), radius: 2)
      }
      .offset(y: 2)
    }
    .padding(5)
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
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
    .accessibilityHint("Activate for a reaction. Use Settings to move Timi.")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      interactionState.reactToClick()
    }
  }

  private var eye: some View {
    Capsule()
      .fill(.white)
      .frame(width: 20, height: 39)
      .shadow(color: .white.opacity(0.24), radius: 3)
      .scaleEffect(y: eyesAreOpen ? 1 : 0.08)
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

private struct SmileShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control1: CGPoint(x: rect.width * 0.24, y: rect.maxY),
      control2: CGPoint(x: rect.width * 0.76, y: rect.maxY)
    )
    return path
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
        .frame(
          width: MascotWindowController.windowSize.width,
          height: MascotWindowController.windowSize.height
        )
    }
    .frame(width: 260, height: 180)
  }
}

struct MascotView_Previews: PreviewProvider {
  static var previews: some View {
    MascotPreviewBackground()
  }
}
