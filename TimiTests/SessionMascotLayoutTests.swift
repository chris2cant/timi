import XCTest

@testable import Timi

final class SessionMascotLayoutTests: XCTestCase {
  private let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
  private let size = CGSize(width: 100, height: 80)
  private let gap: CGFloat = 10

  func testMascotOnRightHalfGrowsLeftAlignedOnBottom() {
    let mascot = CGRect(x: 800, y: 20, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 2, mascot: mascot),
      [CGPoint(x: 690, y: 20), CGPoint(x: 580, y: 20)]
    )
  }

  func testMascotOnLeftHalfGrowsRight() {
    let mascot = CGRect(x: 50, y: 20, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 2, mascot: mascot),
      [CGPoint(x: 208, y: 20), CGPoint(x: 318, y: 20)]
    )
  }

  func testMascotOnTopHalfAlignsOnItsTop() {
    let mascot = CGRect(x: 50, y: 650, width: 148, height: 104)

    XCTAssertEqual(origins(count: 1, mascot: mascot), [CGPoint(x: 208, y: 674)])
  }

  func testOverflowingRowWrapsTowardScreenInside() {
    let narrowScreen = CGRect(x: 0, y: 0, width: 500, height: 800)
    let bottomMascot = CGRect(x: 300, y: 20, width: 148, height: 104)
    let topMascot = CGRect(x: 300, y: 650, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 3, mascot: bottomMascot, in: narrowScreen),
      [CGPoint(x: 190, y: 20), CGPoint(x: 80, y: 20), CGPoint(x: 190, y: 110)]
    )
    XCTAssertEqual(
      origins(count: 3, mascot: topMascot, in: narrowScreen),
      [CGPoint(x: 190, y: 674), CGPoint(x: 80, y: 674), CGPoint(x: 190, y: 584)]
    )
  }

  func testOriginsAreClampedInsideVisibleFrame() {
    let hiddenAtBottom = CGRect(x: 50, y: -60, width: 148, height: 104)
    let hiddenAtTop = CGRect(x: 50, y: 760, width: 148, height: 104)

    XCTAssertEqual(origins(count: 1, mascot: hiddenAtBottom), [CGPoint(x: 208, y: 0)])
    XCTAssertEqual(origins(count: 1, mascot: hiddenAtTop), [CGPoint(x: 208, y: 720)])
  }

  func testMascotOnBottomEdgeOrCornerKeepsARow() {
    let bottom = CGRect(x: 400, y: 0, width: 148, height: 104)
    let bottomLeftCorner = CGRect(x: 0, y: 0, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 2, mascot: bottom),
      [CGPoint(x: 558, y: 0), CGPoint(x: 668, y: 0)]
    )
    XCTAssertEqual(origins(count: 1, mascot: bottomLeftCorner), [CGPoint(x: 158, y: 0)])
  }

  func testMascotOnLeftEdgeStacksAColumnUpward() {
    let mascot = CGRect(x: 0, y: 200, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 2, mascot: mascot),
      [CGPoint(x: 0, y: 314), CGPoint(x: 0, y: 404)]
    )
  }

  func testMascotOnRightEdgeUpperHalfStacksAColumnDownward() {
    let mascot = CGRect(x: 852, y: 500, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 2, mascot: mascot),
      [CGPoint(x: 900, y: 410), CGPoint(x: 900, y: 320)]
    )
  }

  func testOverflowingColumnWrapsTowardScreenInside() {
    let shortScreen = CGRect(x: 0, y: 0, width: 1_000, height: 500)
    let mascot = CGRect(x: 0, y: 100, width: 148, height: 104)

    XCTAssertEqual(
      origins(count: 4, mascot: mascot, in: shortScreen),
      [
        CGPoint(x: 0, y: 214), CGPoint(x: 0, y: 304), CGPoint(x: 0, y: 394),
        CGPoint(x: 110, y: 214),
      ]
    )
  }

  func testFirstLineSticksToTheMainMascotEdgeAfterTheLeadingGap() {
    let bottom = CGRect(x: 400, y: 0, width: 148, height: 104)
    let floating = CGRect(x: 400, y: 200, width: 148, height: 104)

    XCTAssertEqual(
      placements(count: 2, mascot: bottom, leadingGap: 30),
      [
        SessionMascotPlacement(origin: CGPoint(x: 578, y: 0), edges: .bottom),
        SessionMascotPlacement(origin: CGPoint(x: 688, y: 0), edges: .bottom),
      ]
    )
    XCTAssertEqual(placements(count: 1, mascot: floating).map(\.edges), [[]])
  }

  func testWrappedLinesFloat() {
    let shortScreen = CGRect(x: 0, y: 0, width: 1_000, height: 500)
    let leftMascot = CGRect(x: 0, y: 100, width: 148, height: 104)
    let narrowScreen = CGRect(x: 0, y: 0, width: 500, height: 800)
    let bottomMascot = CGRect(x: 300, y: 0, width: 148, height: 104)

    XCTAssertEqual(
      placements(count: 4, mascot: leftMascot, in: shortScreen).map(\.edges),
      [.left, .left, .left, []]
    )
    XCTAssertEqual(
      placements(count: 3, mascot: bottomMascot, in: narrowScreen).map(\.edges),
      [.bottom, .bottom, []]
    )
  }

  func testNoSessionGivesNoOrigin() {
    let mascot = CGRect(x: 50, y: 20, width: 148, height: 104)

    XCTAssertEqual(origins(count: 0, mascot: mascot), [])
    XCTAssertEqual(origins(count: -1, mascot: mascot), [])
  }

  private func origins(count: Int, mascot: CGRect, in frame: CGRect? = nil) -> [CGPoint] {
    placements(count: count, mascot: mascot, in: frame).map(\.origin)
  }

  private func placements(
    count: Int,
    mascot: CGRect,
    in frame: CGRect? = nil,
    leadingGap: CGFloat? = nil
  ) -> [SessionMascotPlacement] {
    SessionMascotLayout.placements(
      count: count,
      windowSize: size,
      attachedTo: mascot,
      in: frame ?? screen,
      gap: gap,
      leadingGap: leadingGap ?? gap
    )
  }
}
