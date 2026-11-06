import SwiftUI

/// Tuning aid: shows every mood and gesture on both mascot sizes, at real size.
struct ExpressionGalleryView: View {
  private enum GazeMode: String, CaseIterable, Identifiable {
    case facing = "De face"
    case wandering = "Errance"
    case reading = "Lecture"

    var id: Self { self }
  }

  @State private var mood: EyeMood = .neutral
  @State private var gazeMode: GazeMode = .facing
  @State private var autoBlink = true
  @State private var trigger: GestureTrigger?

  var body: some View {
    Form {
      Section {
        HStack(spacing: 24) {
          Spacer()
          preview(
            size: MascotWindowController.mascotSize,
            cornerRadius: MascotView.cornerRadius,
            eyeScale: MascotView.eyeScale,
            glowRadius: MascotView.glowRadius
          )
          preview(
            size: SessionMascotView.silhouetteSize,
            cornerRadius: SessionMascotView.cornerRadius,
            eyeScale: SessionMascotView.eyeScale,
            glowRadius: SessionMascotView.glowRadius
          )
          Spacer()
        }
        .padding(.vertical, 8)
        Picker("Regard", selection: $gazeMode) {
          ForEach(GazeMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
        }
        .pickerStyle(.segmented)
        Toggle("Clignements automatiques", isOn: $autoBlink)
      }
      Section("Humeurs") {
        grid(EyeMood.allCases) { item in
          Button(item.title) { mood = item }
            .tint(mood == item ? .accentColor : nil)
        }
      }
      Section("Gestes") {
        grid(EyeGesture.allCases) { gesture in
          Button(gesture.title) { trigger.play(gesture) }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func preview(
    size: CGSize,
    cornerRadius: CGFloat,
    eyeScale: CGFloat,
    glowRadius: CGFloat
  ) -> some View {
    AnimatedEyes(
      mood: mood,
      gaze: gaze(at:),
      trigger: trigger,
      eyeScale: eyeScale,
      autoBlink: autoBlink,
      glowRadius: glowRadius
    )
    .frame(width: size.width, height: size.height)
    .background(.black)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private func gaze(at time: TimeInterval) -> HeadGaze {
    switch gazeMode {
    case .facing: .zero
    case .wandering: EyeProjection.wanderingGaze(at: time)
    case .reading: EyeProjection.readingGaze(at: time)
    }
  }

  private func grid<Item: Identifiable, Content: View>(
    _ items: [Item],
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
      ForEach(items) { item in
        content(item)
          .buttonStyle(.bordered)
          .frame(maxWidth: .infinity)
      }
    }
  }
}

#Preview {
  ExpressionGalleryView()
    .frame(width: 620, height: 540)
}
