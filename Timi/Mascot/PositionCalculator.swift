import CoreGraphics

struct MascotAttachmentEdges: OptionSet, Equatable, Sendable {
  let rawValue: Int

  static let left = Self(rawValue: 1 << 0)
  static let right = Self(rawValue: 1 << 1)
  static let bottom = Self(rawValue: 1 << 2)
  static let top = Self(rawValue: 1 << 3)
}

enum HideEdge: CaseIterable, Equatable, Sendable {
  case left
  case right
  case bottom
  case top
}

enum PositionCalculator {
  /// Nearest screen edge the mascot can slide off, skipping edges where another
  /// screen is adjacent (the mascot would otherwise show up on that screen).
  static func hideEdge(
    origin: CGPoint,
    windowSize: CGSize,
    in frame: CGRect,
    otherFrames: [CGRect] = []
  ) -> HideEdge? {
    let candidates: [(edge: HideEdge, distance: CGFloat, probe: CGPoint)] = [
      (.left, origin.x - frame.minX,
       CGPoint(x: frame.minX - 1, y: origin.y + windowSize.height / 2)),
      (.right, frame.maxX - (origin.x + windowSize.width),
       CGPoint(x: frame.maxX + 1, y: origin.y + windowSize.height / 2)),
      (.bottom, origin.y - frame.minY,
       CGPoint(x: origin.x + windowSize.width / 2, y: frame.minY - 1)),
      (.top, frame.maxY - (origin.y + windowSize.height),
       CGPoint(x: origin.x + windowSize.width / 2, y: frame.maxY + 1)),
    ]

    return candidates
      .filter { candidate in !otherFrames.contains { $0.contains(candidate.probe) } }
      .min { $0.distance < $1.distance }?
      .edge
  }

  /// Origin of the mascot slid off `edge`, leaving `visibleStrip` points on screen.
  static func hiddenOrigin(
    origin: CGPoint,
    windowSize: CGSize,
    in frame: CGRect,
    edge: HideEdge,
    visibleStrip: CGFloat
  ) -> CGPoint {
    let clampedOrigin = clamped(origin: origin, windowSize: windowSize, to: frame)
    return switch edge {
    case .left:
      CGPoint(x: frame.minX - windowSize.width + visibleStrip, y: clampedOrigin.y)
    case .right:
      CGPoint(x: frame.maxX - visibleStrip, y: clampedOrigin.y)
    case .bottom:
      CGPoint(x: clampedOrigin.x, y: frame.minY - windowSize.height + visibleStrip)
    case .top:
      CGPoint(x: clampedOrigin.x, y: frame.maxY - visibleStrip)
    }
  }

  /// Strip along `edge`, over the mascot's span, where the pointer reveals it.
  /// It reaches 1 pt past the edge because the pointer can sit exactly on it.
  static func revealZone(
    origin: CGPoint,
    windowSize: CGSize,
    in frame: CGRect,
    edge: HideEdge,
    thickness: CGFloat
  ) -> CGRect {
    let clampedOrigin = clamped(origin: origin, windowSize: windowSize, to: frame)
    let depth = thickness + 1
    return switch edge {
    case .left:
      CGRect(x: frame.minX - 1, y: clampedOrigin.y, width: depth, height: windowSize.height)
    case .right:
      CGRect(x: frame.maxX - thickness, y: clampedOrigin.y, width: depth, height: windowSize.height)
    case .bottom:
      CGRect(x: clampedOrigin.x, y: frame.minY - 1, width: windowSize.width, height: depth)
    case .top:
      CGRect(x: clampedOrigin.x, y: frame.maxY - thickness, width: windowSize.width, height: depth)
    }
  }

  static func origin(
    for position: MascotPosition,
    in visibleFrame: CGRect,
    windowSize: CGSize,
    margin: CGFloat,
    offset: CGSize = .zero
  ) -> CGPoint {
    let left = visibleFrame.minX + margin
    let centerX = visibleFrame.midX - windowSize.width / 2
    let right = visibleFrame.maxX - margin - windowSize.width

    let bottom = visibleFrame.minY + margin
    let centerY = visibleFrame.midY - windowSize.height / 2
    let top = visibleFrame.maxY - margin - windowSize.height

    let anchorOrigin =
      switch position {
      case .topLeft: CGPoint(x: left, y: top)
      case .topCenter: CGPoint(x: centerX, y: top)
      case .topRight: CGPoint(x: right, y: top)
      case .centerLeft: CGPoint(x: left, y: centerY)
      case .centerRight: CGPoint(x: right, y: centerY)
      case .bottomLeft: CGPoint(x: left, y: bottom)
      case .bottomCenter: CGPoint(x: centerX, y: bottom)
      case .bottomRight: CGPoint(x: right, y: bottom)
      }

    return CGPoint(
      x: anchorOrigin.x + offset.width,
      y: anchorOrigin.y + offset.height
    )
  }

  static func clamped(
    origin: CGPoint,
    windowSize: CGSize,
    to frame: CGRect
  ) -> CGPoint {
    let maximumX = max(frame.minX, frame.maxX - windowSize.width)
    let maximumY = max(frame.minY, frame.maxY - windowSize.height)

    return CGPoint(
      x: min(max(origin.x, frame.minX), maximumX),
      y: min(max(origin.y, frame.minY), maximumY)
    )
  }

  static func snappedToEdges(
    origin: CGPoint,
    windowSize: CGSize,
    in frame: CGRect,
    threshold: CGFloat
  ) -> CGPoint {
    let clampedOrigin = clamped(origin: origin, windowSize: windowSize, to: frame)
    let maximumX = max(frame.minX, frame.maxX - windowSize.width)
    let maximumY = max(frame.minY, frame.maxY - windowSize.height)

    let x = snappedCoordinate(
      clampedOrigin.x,
      minimum: frame.minX,
      maximum: maximumX,
      threshold: threshold
    )
    let y = snappedCoordinate(
      clampedOrigin.y,
      minimum: frame.minY,
      maximum: maximumY,
      threshold: threshold
    )

    return CGPoint(x: x, y: y)
  }

  static func attachmentEdges(
    origin: CGPoint,
    windowSize: CGSize,
    in frame: CGRect,
    tolerance: CGFloat = 0.5
  ) -> MascotAttachmentEdges {
    var edges: MascotAttachmentEdges = []

    if abs(origin.x - frame.minX) <= tolerance {
      edges.insert(.left)
    }
    if abs(origin.x + windowSize.width - frame.maxX) <= tolerance {
      edges.insert(.right)
    }
    if abs(origin.y - frame.minY) <= tolerance {
      edges.insert(.bottom)
    }
    if abs(origin.y + windowSize.height - frame.maxY) <= tolerance {
      edges.insert(.top)
    }

    return edges
  }

  static func indexOfFrameContainingMost(
    _ windowFrame: CGRect,
    among screenFrames: [CGRect],
    preferredIndex: Int? = nil
  ) -> Int? {
    var bestIndex: Int?
    var bestArea: CGFloat = 0

    for (index, screenFrame) in screenFrames.enumerated() {
      let area = intersectionArea(windowFrame, screenFrame)
      if area > bestArea || (area == bestArea && area > 0 && index == preferredIndex) {
        bestArea = area
        bestIndex = index
      }
    }

    return bestIndex
  }

  static func indexOfFrame(
    containing point: CGPoint,
    among frames: [CGRect],
    preferredIndex: Int? = nil
  ) -> Int? {
    let matchingIndices = frames.indices.filter { frames[$0].contains(point) }
    if let preferredIndex, matchingIndices.contains(preferredIndex) {
      return preferredIndex
    }
    return matchingIndices.first
  }

  private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else { return 0 }
    return intersection.width * intersection.height
  }

  private static func snappedCoordinate(
    _ coordinate: CGFloat,
    minimum: CGFloat,
    maximum: CGFloat,
    threshold: CGFloat
  ) -> CGFloat {
    let minimumDistance = abs(coordinate - minimum)
    let maximumDistance = abs(maximum - coordinate)

    if minimumDistance <= threshold, minimumDistance <= maximumDistance {
      return minimum
    }
    if maximumDistance <= threshold {
      return maximum
    }
    return coordinate
  }
}
