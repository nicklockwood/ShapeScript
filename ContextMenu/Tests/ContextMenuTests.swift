import ContextMenu
import XCTest

@MainActor
final class ContextMenuTests: XCTestCase {
    func testInteractionAttachesToView() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let interaction = ContextMenuInteraction { _ in nil }

        view.addInteraction(interaction)

        XCTAssertTrue(interaction.view === view)
        let addedGestures = view.gestureRecognizers ?? []
        XCTAssertTrue(addedGestures.contains { $0 is UILongPressGestureRecognizer })

        view.removeInteraction(interaction)

        XCTAssertNil(interaction.view)
        for gesture in addedGestures {
            XCTAssertFalse(view.gestureRecognizers?.contains { $0 === gesture } ?? false)
        }
    }

    func testMenuProviderReceivesRequestedLocation() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var receivedLocation: CGPoint?
        let expectedLocation = CGPoint(x: 20, y: 30)
        let interaction = ContextMenuInteraction { location in
            receivedLocation = location
            return nil
        }

        view.addInteraction(interaction)
        interaction.presentMenu(at: expectedLocation)

        XCTAssertEqual(receivedLocation, expectedLocation)
    }
}
