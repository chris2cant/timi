import XCTest

@testable import Timi

final class PositionCalculatorTests: XCTestCase {
  private let frame = CGRect(x: 100, y: 50, width: 1_000, height: 700)
  private let size = CGSize(width: 100, height: 80)
  private let margin: CGFloat = 20

  func testCornerOriginsRespectVisibleFrameAndMargin() {
    XCTAssertEqual(origin(.topLeft), CGPoint(x: 120, y: 650))
    XCTAssertEqual(origin(.topRight), CGPoint(x: 980, y: 650))
    XCTAssertEqual(origin(.bottomLeft), CGPoint(x: 120, y: 70))
    XCTAssertEqual(origin(.bottomRight), CGPoint(x: 980, y: 70))
  }

  func testEdgeCentersAccountForWindowSize() {
    XCTAssertEqual(origin(.topCenter), CGPoint(x: 550, y: 650))
    XCTAssertEqual(origin(.centerLeft), CGPoint(x: 120, y: 360))
    XCTAssertEqual(origin(.centerRight), CGPoint(x: 980, y: 360))
    XCTAssertEqual(origin(.bottomCenter), CGPoint(x: 550, y: 70))
  }

  func testOffsetIsAppliedRelativeToAnchor() {
    XCTAssertEqual(
      PositionCalculator.origin(
        for: .bottomLeft,
        in: frame,
        windowSize: size,
        margin: margin,
        offset: CGSize(width: 35, height: 18)
      ),
      CGPoint(x: 155, y: 88)
    )
  }

  func testManualPositionIsClampedInsideScreenFrame() {
    XCTAssertEqual(
      PositionCalculator.clamped(
        origin: CGPoint(x: -500, y: 900),
        windowSize: size,
        to: frame
      ),
      CGPoint(x: 100, y: 670)
    )
  }

  func testClampingHandlesEveryEdgeAndLeavesValidOriginUnchanged() {
    XCTAssertEqual(clamped(CGPoint(x: 40, y: 300)), CGPoint(x: 100, y: 300))
    XCTAssertEqual(clamped(CGPoint(x: 1_400, y: 300)), CGPoint(x: 1_000, y: 300))
    XCTAssertEqual(clamped(CGPoint(x: 500, y: -30)), CGPoint(x: 500, y: 50))
    XCTAssertEqual(clamped(CGPoint(x: 500, y: 900)), CGPoint(x: 500, y: 670))
    XCTAssertEqual(clamped(CGPoint(x: 400, y: 200)), CGPoint(x: 400, y: 200))
  }

  func testWindowLargerThanScreenFrameAlignsWithMinimumEdges() {
    XCTAssertEqual(
      PositionCalculator.clamped(
        origin: CGPoint(x: 800, y: 600),
        windowSize: CGSize(width: 1_200, height: 900),
        to: frame
      ),
      CGPoint(x: frame.minX, y: frame.minY)
    )
  }

  func testPositionSnapsIndependentlyToEachNearbyScreenEdge() {
    XCTAssertEqual(
      snapped(CGPoint(x: 112, y: 300)),
      CGPoint(x: 100, y: 300)
    )
    XCTAssertEqual(
      snapped(CGPoint(x: 975, y: 300)),
      CGPoint(x: 1_000, y: 300)
    )
    XCTAssertEqual(
      snapped(CGPoint(x: 500, y: 68)),
      CGPoint(x: 500, y: 50)
    )
    XCTAssertEqual(
      snapped(CGPoint(x: 500, y: 646)),
      CGPoint(x: 500, y: 670)
    )
  }

  func testPositionSnapsToCornerAndStaysFreeOutsideThreshold() {
    XCTAssertEqual(
      snapped(CGPoint(x: 125, y: 645)),
      CGPoint(x: 100, y: 670)
    )
    XCTAssertEqual(
      snapped(CGPoint(x: 300, y: 300)),
      CGPoint(x: 300, y: 300)
    )
  }

  func testAttachmentEdgesDetectEachSnappedSideAndCorners() {
    XCTAssertEqual(
      attachedEdges(CGPoint(x: 100, y: 300)),
      [.left]
    )
    XCTAssertEqual(
      attachedEdges(CGPoint(x: 1_000, y: 300)),
      [.right]
    )
    XCTAssertEqual(
      attachedEdges(CGPoint(x: 500, y: 50)),
      [.bottom]
    )
    XCTAssertEqual(
      attachedEdges(CGPoint(x: 500, y: 670)),
      [.top]
    )
    XCTAssertEqual(
      attachedEdges(CGPoint(x: 100, y: 670)),
      [.left, .top]
    )
    XCTAssertEqual(attachedEdges(CGPoint(x: 300, y: 300)), [])
  }

  func testAttachmentEdgesTolerateSubpixelCoordinates() {
    XCTAssertEqual(
      attachedEdges(CGPoint(x: 100.25, y: 669.75)),
      [.left, .top]
    )
  }

  func testSnappingUsesFullScreenFrameIncludingMenuBarArea() {
    let fullScreenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    XCTAssertEqual(
      PositionCalculator.snappedToEdges(
        origin: CGPoint(x: 600, y: 770),
        windowSize: size,
        in: fullScreenFrame,
        threshold: 50
      ),
      CGPoint(x: 600, y: 820)
    )
  }

  func testFrameSelectionUsesScreenWithLargestIntersection() {
    let screens = [
      CGRect(x: 0, y: 0, width: 1_000, height: 800),
      CGRect(x: 1_000, y: -200, width: 700, height: 600),
    ]

    XCTAssertEqual(
      PositionCalculator.indexOfFrameContainingMost(
        CGRect(x: 950, y: 100, width: 140, height: 100),
        among: screens
      ),
      1
    )
    XCTAssertEqual(
      PositionCalculator.indexOfFrameContainingMost(
        CGRect(x: 940, y: 100, width: 100, height: 100),
        among: screens
      ),
      0
    )
  }

  func testFrameSelectionReturnsNilOutsideEveryScreen() {
    XCTAssertNil(
      PositionCalculator.indexOfFrameContainingMost(
        CGRect(x: 2_000, y: 2_000, width: 100, height: 100),
        among: [frame]
      )
    )
  }

  func testFrameSelectionPrefersCurrentScreenWhenIntersectionIsEqual() {
    let screens = [
      CGRect(x: 0, y: 0, width: 1_000, height: 800),
      CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
    ]
    let window = CGRect(x: 950, y: 100, width: 100, height: 100)

    XCTAssertEqual(
      PositionCalculator.indexOfFrameContainingMost(
        window,
        among: screens,
        preferredIndex: 0
      ),
      0
    )
    XCTAssertEqual(
      PositionCalculator.indexOfFrameContainingMost(
        window,
        among: screens,
        preferredIndex: 1
      ),
      1
    )
  }

  func testPointSelectionFindsDestinationScreenWithNegativeCoordinates() {
    let screens = [
      CGRect(x: 0, y: 0, width: 1_000, height: 800),
      CGRect(x: -800, y: -200, width: 800, height: 600),
    ]

    XCTAssertEqual(
      PositionCalculator.indexOfFrame(
        containing: CGPoint(x: -400, y: 100),
        among: screens
      ),
      1
    )
    XCTAssertNil(
      PositionCalculator.indexOfFrame(
        containing: CGPoint(x: 2_000, y: 2_000),
        among: screens
      )
    )
  }

  private func origin(_ position: MascotPosition) -> CGPoint {
    PositionCalculator.origin(
      for: position,
      in: frame,
      windowSize: size,
      margin: margin
    )
  }

  func testHideEdgePicksNearestEdgeAndSkipsEdgesWithNeighbourScreen() {
    let nearLeft = CGPoint(x: 110, y: 300)
    XCTAssertEqual(
      PositionCalculator.hideEdge(origin: nearLeft, windowSize: size, in: frame),
      .left
    )
    let neighbour = CGRect(x: frame.minX - 500, y: frame.minY, width: 500, height: frame.height)
    XCTAssertNotEqual(
      PositionCalculator.hideEdge(
        origin: nearLeft, windowSize: size, in: frame, otherFrames: [neighbour]
      ),
      .left
    )
  }

  func testHiddenOriginSlidesOffEdgeLeavingVisibleStrip() {
    let origin = CGPoint(x: 110, y: 300)
    func hidden(_ edge: HideEdge, _ strip: CGFloat) -> CGPoint {
      PositionCalculator.hiddenOrigin(
        origin: origin, windowSize: size, in: frame, edge: edge, visibleStrip: strip
      )
    }
    XCTAssertEqual(hidden(.left, 0).x, frame.minX - size.width)
    XCTAssertEqual(hidden(.left, 4).x, frame.minX - size.width + 4)
    XCTAssertEqual(hidden(.right, 4).x, frame.maxX - 4)
    XCTAssertEqual(hidden(.bottom, 4).y, frame.minY - size.height + 4)
    XCTAssertEqual(hidden(.top, 0).y, frame.maxY)
    XCTAssertEqual(hidden(.left, 0).y, origin.y)
  }

  func testRevealZoneHugsEdgeOverMascotSpan() {
    let origin = CGPoint(x: 110, y: 300)
    let zone = PositionCalculator.revealZone(
      origin: origin, windowSize: size, in: frame, edge: .left, thickness: 2
    )
    XCTAssertTrue(zone.contains(CGPoint(x: frame.minX, y: origin.y + 5)))
    XCTAssertFalse(zone.contains(CGPoint(x: frame.minX + 3, y: origin.y + 5)))
    XCTAssertFalse(zone.contains(CGPoint(x: frame.minX, y: origin.y + size.height + 5)))
    let right = PositionCalculator.revealZone(
      origin: origin, windowSize: size, in: frame, edge: .right, thickness: 2
    )
    XCTAssertTrue(right.contains(CGPoint(x: frame.maxX - 1, y: origin.y + 5)))
  }

  private func clamped(_ point: CGPoint) -> CGPoint {
    PositionCalculator.clamped(origin: point, windowSize: size, to: frame)
  }

  private func snapped(_ point: CGPoint) -> CGPoint {
    PositionCalculator.snappedToEdges(
      origin: point,
      windowSize: size,
      in: frame,
      threshold: 30
    )
  }

  private func attachedEdges(_ point: CGPoint) -> MascotAttachmentEdges {
    PositionCalculator.attachmentEdges(
      origin: point,
      windowSize: size,
      in: frame
    )
  }
}
