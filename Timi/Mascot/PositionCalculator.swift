import CoreGraphics

enum PositionCalculator {
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
