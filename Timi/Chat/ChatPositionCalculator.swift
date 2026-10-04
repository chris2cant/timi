import CoreGraphics

enum ChatPositionCalculator {
  static func origin(
    attachedTo mascotFrame: CGRect,
    bubbleSize: CGSize,
    in visibleFrame: CGRect,
    gap: CGFloat = 12
  ) -> CGPoint {
    let rightOriginX = mascotFrame.maxX + gap
    let leftOriginX = mascotFrame.minX - gap - bubbleSize.width
    let availableOnRight = visibleFrame.maxX - mascotFrame.maxX
    let availableOnLeft = mascotFrame.minX - visibleFrame.minX

    let proposedX: CGFloat
    if rightOriginX + bubbleSize.width <= visibleFrame.maxX {
      proposedX = rightOriginX
    } else if leftOriginX >= visibleFrame.minX {
      proposedX = leftOriginX
    } else if availableOnRight >= availableOnLeft {
      proposedX = rightOriginX
    } else {
      proposedX = leftOriginX
    }

    let proposedY = mascotFrame.midY - bubbleSize.height / 2
    return CGPoint(
      x: clamped(
        proposedX,
        minimum: visibleFrame.minX,
        maximum: visibleFrame.maxX - bubbleSize.width
      ),
      y: clamped(
        proposedY,
        minimum: visibleFrame.minY,
        maximum: visibleFrame.maxY - bubbleSize.height
      )
    )
  }

  private static func clamped(
    _ value: CGFloat,
    minimum: CGFloat,
    maximum: CGFloat
  ) -> CGFloat {
    min(max(value, minimum), max(minimum, maximum))
  }
}
