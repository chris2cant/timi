import XCTest

@testable import Timi

@MainActor
final class AppStateTests: XCTestCase {
  func testDefaultsUseBottomRightZeroOffsetAndVisibleMascot() {
    withDefaults { defaults in
      let state = AppState(defaults: defaults)

      XCTAssertEqual(state.position, .bottomRight)
      XCTAssertEqual(state.offset, .zero)
      XCTAssertNil(state.displayUUID)
      XCTAssertTrue(state.isVisible)
    }
  }

  func testStoredPlacementAndVisibilityAreRestored() {
    withDefaults { defaults in
      defaults.set(MascotPosition.topCenter.rawValue, forKey: "mascotPosition")
      defaults.set(42.5, forKey: "mascotOffsetX")
      defaults.set(-18.0, forKey: "mascotOffsetY")
      defaults.set(false, forKey: "mascotIsVisible")
      defaults.set("display-uuid", forKey: "mascotDisplayUUID")

      let state = AppState(defaults: defaults)

      XCTAssertEqual(state.position, .topCenter)
      XCTAssertEqual(state.offset, CGSize(width: 42.5, height: -18))
      XCTAssertEqual(state.displayUUID, "display-uuid")
      XCTAssertFalse(state.isVisible)
    }
  }

  func testInvalidStoredPositionFallsBackToBottomRight() {
    withDefaults { defaults in
      defaults.set("not-a-position", forKey: "mascotPosition")

      XCTAssertEqual(AppState(defaults: defaults).position, .bottomRight)
    }
  }

  func testSelectingAnchorResetsOffsetPersistsAndNotifies() {
    withDefaults { defaults in
      let state = AppState(defaults: defaults)
      state.updateOffset(CGSize(width: 25, height: -10))

      var observedPosition: MascotPosition?
      var observedOffset: CGSize?
      state.placementDidChange = { position, offset, _ in
        observedPosition = position
        observedOffset = offset
      }

      state.select(.centerLeft)

      XCTAssertEqual(state.position, .centerLeft)
      XCTAssertEqual(state.offset, .zero)
      XCTAssertEqual(observedPosition, .centerLeft)
      XCTAssertEqual(observedOffset, .zero)
      XCTAssertEqual(defaults.string(forKey: "mascotPosition"), MascotPosition.centerLeft.rawValue)
      XCTAssertEqual(defaults.double(forKey: "mascotOffsetX"), 0)
      XCTAssertEqual(defaults.double(forKey: "mascotOffsetY"), 0)
    }
  }

  func testOffsetResetAndVisibilityPersistAndNotify() {
    withDefaults { defaults in
      let state = AppState(defaults: defaults)
      var observedOffset: CGSize?
      var observedVisibility: Bool?
      state.placementDidChange = { _, offset, _ in observedOffset = offset }
      state.visibilityDidChange = { observedVisibility = $0 }

      state.updateOffset(CGSize(width: -30, height: 12))
      XCTAssertEqual(observedOffset, CGSize(width: -30, height: 12))
      XCTAssertEqual(defaults.double(forKey: "mascotOffsetX"), -30)
      XCTAssertEqual(defaults.double(forKey: "mascotOffsetY"), 12)

      state.resetOffset()
      XCTAssertEqual(state.offset, .zero)
      XCTAssertEqual(observedOffset, .zero)

      state.isVisible = false
      XCTAssertEqual(observedVisibility, false)
      XCTAssertEqual(defaults.object(forKey: "mascotIsVisible") as? Bool, false)
    }
  }

  func testDisplayUUIDIsPersistedWithDraggedOffset() {
    withDefaults { defaults in
      let state = AppState(defaults: defaults)
      var observedDisplayUUID: String?
      state.placementDidChange = { _, _, displayUUID in
        observedDisplayUUID = displayUUID
      }

      state.updatePlacement(
        offset: CGSize(width: 80, height: -25),
        displayUUID: "secondary-display"
      )

      XCTAssertEqual(state.offset, CGSize(width: 80, height: -25))
      XCTAssertEqual(state.displayUUID, "secondary-display")
      XCTAssertEqual(observedDisplayUUID, "secondary-display")
      XCTAssertEqual(defaults.string(forKey: "mascotDisplayUUID"), "secondary-display")

      state.select(.topRight)
      XCTAssertEqual(state.offset, .zero)
      XCTAssertEqual(state.displayUUID, "secondary-display")
      XCTAssertEqual(defaults.string(forKey: "mascotDisplayUUID"), "secondary-display")
    }
  }

  private func withDefaults(_ body: (UserDefaults) -> Void) {
    let suiteName = "AppStateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    body(defaults)
  }
}
