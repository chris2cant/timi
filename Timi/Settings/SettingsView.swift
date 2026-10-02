import SwiftUI

struct SettingsView: View {
  @ObservedObject var appState: AppState

  private let columns = Array(repeating: GridItem(.fixed(86), spacing: 10), count: 3)

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Mascot Position")
          .font(.headline)
        Text("Choose where Timi sits in the usable area of its current display.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(0..<9, id: \.self) { cell in
          if cell == 4 {
            Color.clear
              .frame(height: 58)
          } else if let position = position(for: cell) {
            positionButton(position)
          }
        }
      }

      Divider()

      Toggle("Show Timi", isOn: $appState.isVisible)

      Divider()

      HStack {
        Text("Drag Timi to move it, or click it for a reaction.")
          .font(.callout)
          .foregroundStyle(.secondary)

        Spacer()

        Button("Reset Offset") {
          appState.resetOffset()
        }
        .disabled(appState.offset == .zero)
      }
    }
    .padding(24)
    .frame(width: 330)
  }

  private func positionButton(_ position: MascotPosition) -> some View {
    Button {
      appState.select(position)
    } label: {
      Text(position.title)
        .font(.caption)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }
    .buttonStyle(.bordered)
    .tint(appState.position == position ? .accentColor : nil)
    .accessibilityAddTraits(appState.position == position ? .isSelected : [])
  }

  private func position(for cell: Int) -> MascotPosition? {
    let row = cell / 3
    let column = cell % 3
    return MascotPosition.allCases.first {
      $0.gridRow == row && $0.gridColumn == column
    }
  }
}

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView(appState: AppState(defaults: UserDefaults(suiteName: "TimiPreview")!))
  }
}
