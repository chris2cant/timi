import Foundation

enum MascotPosition: String, CaseIterable, Identifiable, Sendable {
  case topLeft
  case topCenter
  case topRight
  case centerLeft
  case centerRight
  case bottomLeft
  case bottomCenter
  case bottomRight

  var id: Self { self }

  var title: String {
    switch self {
    case .topLeft: "Top Left"
    case .topCenter: "Top Center"
    case .topRight: "Top Right"
    case .centerLeft: "Center Left"
    case .centerRight: "Center Right"
    case .bottomLeft: "Bottom Left"
    case .bottomCenter: "Bottom Center"
    case .bottomRight: "Bottom Right"
    }
  }
}
