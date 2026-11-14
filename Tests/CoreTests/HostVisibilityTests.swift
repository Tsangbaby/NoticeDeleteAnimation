import XCTest
@testable import NoticeDeleteAnimationCore

final class HostVisibilityTests: XCTestCase {
    func testSystemWindowWithoutSceneIsEligibleOnlyInSpringBoard() {
        XCTAssertTrue(NDAHostVisibility.allows(isSpringBoard: true, windowVisible: true, scene: .absent))
        XCTAssertFalse(NDAHostVisibility.allows(isSpringBoard: false, windowVisible: true, scene: .absent))
    }
    func testInactiveSpringBoardDoesNotImplyHiddenLockScreen() {
        XCTAssertTrue(NDAHostVisibility.allows(isSpringBoard: true, windowVisible: true, scene: .foregroundInactive))
        XCTAssertFalse(NDAHostVisibility.allows(isSpringBoard: false, windowVisible: true, scene: .foregroundInactive))
    }
    func testHiddenBackgroundAndUnattachedAreAlwaysRejected() {
        for host in [false, true] {
            for state: NDAHostSceneState in [.absent, .foregroundActive, .foregroundInactive, .background, .unattached] {
                XCTAssertFalse(NDAHostVisibility.allows(isSpringBoard: host, windowVisible: false, scene: state))
            }
            XCTAssertFalse(NDAHostVisibility.allows(isSpringBoard: host, windowVisible: true, scene: .background))
            XCTAssertFalse(NDAHostVisibility.allows(isSpringBoard: host, windowVisible: true, scene: .unattached))
        }
    }
    func testOrdinaryActiveWindowIsEligible() {
        XCTAssertTrue(NDAHostVisibility.allows(isSpringBoard: false, windowVisible: true, scene: .foregroundActive))
    }
}
