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

  var gridColumn: Int {
    switch self {
    case .topLeft, .centerLeft, .bottomLeft: 0
    case .topCenter, .bottomCenter: 1
    case .topRight, .centerRight, .bottomRight: 2
    }
  }

  var gridRow: Int {
    switch self {
    case .topLeft, .topCenter, .topRight: 0
    case .centerLeft, .centerRight: 1
    case .bottomLeft, .bottomCenter, .bottomRight: 2
    }
  }
}
