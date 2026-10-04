import XCTest
@testable import Timi

final class ChatPositionCalculatorTests: XCTestCase {
  private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
  private let bubbleSize = CGSize(width: 380, height: 420)

  func testPlacesBubbleToTheRightWhenThereIsRoom() {
    let mascot = CGRect(x: 200, y: 400, width: 148, height: 104)

    XCTAssertEqual(
      ChatPositionCalculator.origin(
        attachedTo: mascot,
        bubbleSize: bubbleSize,
        in: screen
      ),
      CGPoint(x: 360, y: 242)
    )
  }

  func testPlacesBubbleToTheLeftNearRightEdge() {
    let mascot = CGRect(x: 1_292, y: 400, width: 148, height: 104)

    XCTAssertEqual(
      ChatPositionCalculator.origin(
        attachedTo: mascot,
        bubbleSize: bubbleSize,
        in: screen
      ),
      CGPoint(x: 900, y: 242)
    )
  }

  func testClampsBubbleInsideVisibleFrame() {
    let visibleFrame = CGRect(x: 80, y: 50, width: 500, height: 500)
    let mascot = CGRect(x: 250, y: 500, width: 148, height: 104)

    let origin = ChatPositionCalculator.origin(
      attachedTo: mascot,
      bubbleSize: bubbleSize,
      in: visibleFrame
    )

    XCTAssertGreaterThanOrEqual(origin.x, visibleFrame.minX)
    XCTAssertGreaterThanOrEqual(origin.y, visibleFrame.minY)
    XCTAssertLessThanOrEqual(origin.x + bubbleSize.width, visibleFrame.maxX)
    XCTAssertLessThanOrEqual(origin.y + bubbleSize.height, visibleFrame.maxY)
  }
}
