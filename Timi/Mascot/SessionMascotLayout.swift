import CoreGraphics

struct SessionMascotPlacement: Equatable {
  let origin: CGPoint
  /// Screen edge the session mascot sticks to, like the main mascot (empty when floating).
  let edges: MascotAttachmentEdges
}

enum SessionMascotLayout {
  /// Placements for `count` session mascots lined up next to the main mascot.
  /// They stack in a column when the main mascot sticks to the left or right edge of
  /// `frame` only, and in a row otherwise. The line grows toward the inside of `frame`
  /// and wraps when it overflows. The first line shares the main mascot's edge, so its
  /// mascots stick to it too; `leadingGap` keeps their joins apart from the main one.
  static func placements(
    count: Int,
    windowSize: CGSize,
    attachedTo mascotFrame: CGRect,
    in frame: CGRect,
    gap: CGFloat,
    leadingGap: CGFloat
  ) -> [SessionMascotPlacement] {
    guard count > 0 else { return [] }

    let edges = PositionCalculator.attachmentEdges(
      origin: mascotFrame.origin,
      windowSize: mascotFrame.size,
      in: frame
    )
    let isColumn = edges.isDisjoint(with: [.bottom, .top])
      && !edges.isDisjoint(with: [.left, .right])
    let geometry = Geometry(windowSize: windowSize, gap: gap, leadingGap: leadingGap)

    let placements = isColumn
      ? columnPlacements(count: count, geometry: geometry, mascotFrame: mascotFrame,
                         leftEdge: edges.contains(.left), in: frame)
      : rowPlacements(count: count, geometry: geometry, mascotFrame: mascotFrame,
                      edges: edges, in: frame)
    return placements.map {
      SessionMascotPlacement(
        origin: PositionCalculator.clamped(origin: $0.origin, windowSize: windowSize, to: frame),
        edges: $0.edges
      )
    }
  }

  private struct Geometry {
    let windowSize: CGSize
    let gap: CGFloat
    let leadingGap: CGFloat

    var stepX: CGFloat { windowSize.width + gap }
    var stepY: CGFloat { windowSize.height + gap }
  }

  private static func rowPlacements(
    count: Int,
    geometry: Geometry,
    mascotFrame: CGRect,
    edges: MascotAttachmentEdges,
    in frame: CGRect
  ) -> [SessionMascotPlacement] {
    let size = geometry.windowSize
    let growsLeft = mascotFrame.midX > frame.midX
    let alignsTop = mascotFrame.midY > frame.midY
    let sharedEdge = edges.intersection(alignsTop ? .top : .bottom)

    let room = (growsLeft ? mascotFrame.minX - frame.minX : frame.maxX - mascotFrame.maxX)
      - geometry.leadingGap + geometry.gap
    let perRow = max(1, Int((room / geometry.stepX).rounded(.down)))

    let firstX = growsLeft
      ? mascotFrame.minX - geometry.leadingGap - size.width
      : mascotFrame.maxX + geometry.leadingGap
    let firstY = alignsTop ? mascotFrame.maxY - size.height : mascotFrame.minY

    return (0..<count).map { index in
      let column = CGFloat(index % perRow)
      let row = index / perRow
      return SessionMascotPlacement(
        origin: CGPoint(
          x: firstX + (growsLeft ? -column : column) * geometry.stepX,
          y: firstY + (alignsTop ? -1 : 1) * CGFloat(row) * geometry.stepY
        ),
        edges: row == 0 ? sharedEdge : []
      )
    }
  }

  private static func columnPlacements(
    count: Int,
    geometry: Geometry,
    mascotFrame: CGRect,
    leftEdge: Bool,
    in frame: CGRect
  ) -> [SessionMascotPlacement] {
    let size = geometry.windowSize
    let growsUp = mascotFrame.midY <= frame.midY

    let room = (growsUp ? frame.maxY - mascotFrame.maxY : mascotFrame.minY - frame.minY)
      - geometry.leadingGap + geometry.gap
    let perColumn = max(1, Int((room / geometry.stepY).rounded(.down)))

    let firstX = leftEdge ? mascotFrame.minX : mascotFrame.maxX - size.width
    let firstY = growsUp
      ? mascotFrame.maxY + geometry.leadingGap
      : mascotFrame.minY - geometry.leadingGap - size.height

    return (0..<count).map { index in
      let row = CGFloat(index % perColumn)
      let column = index / perColumn
      return SessionMascotPlacement(
        origin: CGPoint(
          x: firstX + (leftEdge ? 1 : -1) * CGFloat(column) * geometry.stepX,
          y: firstY + (growsUp ? row : -row) * geometry.stepY
        ),
        edges: column == 0 ? (leftEdge ? .left : .right) : []
      )
    }
  }
}
