import UIKit
import XCTest

/// Add to an iOS XCTest target. Exercises real UIKit geometry, NOT private hooks
/// or the production capture bridge. This file is intentionally outside SwiftPM.
final class SurfaceGeometryTests: XCTestCase {
    func testNonzeroScrollOriginDoesNotDoubleOffset() {
        let list = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        list.contentSize = CGSize(width: 390, height: 2000)
        list.bounds.origin = CGPoint(x: 0, y: 500)
        let source = UIView(frame: CGRect(x: 20, y: 520, width: 350, height: 100))
        list.addSubview(source)
        let frame = source.convert(source.bounds, to: list)
        let overlay = UIView(frame: list.bounds)
        overlay.bounds = list.bounds
        list.addSubview(overlay)
        let tile = UIView(frame: frame)
        overlay.addSubview(tile)
        XCTAssertEqual(tile.convert(tile.bounds, to: list), frame)
        XCTAssertEqual(tile.convert(tile.bounds, to: list).minY, 520)
        XCTAssertEqual(overlay.convert(tile.frame, to: list).minY, 520)
    }

    func testOrdinaryScrollCoordinatesRemainCorrect() {
        let list = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        let overlay = UIView(frame: list.bounds)
        overlay.bounds = list.bounds
        list.addSubview(overlay)
        let rect = CGRect(x: 10, y: 30, width: 300, height: 80)
        XCTAssertEqual(overlay.convert(rect, to: list), rect)
    }
}
