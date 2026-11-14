import Foundation
import XCTest
@testable import NoticeDeleteAnimationCore

final class AdmissionTests: XCTestCase {
    private func request(token: UUID = UUID(), tiles: Int = 100,
                         width: Int = 100, height: Int = 100) -> NDAAdmissionRequest {
        NDAAdmissionRequest(token: token, tileCount: tiles, bitmapWidth: width, bitmapHeight: height)
    }

    private func accepted(_ result: NDAAdmissionResult,
                          file: StaticString = #filePath, line: UInt = #line) throws -> NDAEffectLease {
        if case .accepted(let lease) = result.decision { return lease }
        XCTFail("Expected acceptance, got \(result.decision)", file: file, line: line)
        throw NSError(domain: "CoreTests", code: 1)
    }

    func testDuplicateAndIdempotentRelease() throws {
        var core = NDAAdmissionController()
        let input = request()
        let lease = try accepted(core.admit(input, at: 10))
        XCTAssertEqual(core.admit(input, at: 10).decision, .rejected(.duplicateToken))
        XCTAssertEqual(core.usedTiles, 100)
        XCTAssertEqual(core.usedPixels, 10_000)
        XCTAssertTrue(core.release(lease))
        XCTAssertFalse(core.release(lease))
        XCTAssertEqual(core.usedTiles, 0)
        let replacement = try accepted(core.admit(input, at: 10))
        XCTAssertNotEqual(lease.id, replacement.id)
        XCTAssertFalse(core.release(lease))
        XCTAssertEqual(core.activeLeases, [replacement])
    }

    func testExactBudgetsAndRejectionDoesNotReserve() throws {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(
            maxConcurrent: 3, maxTilesPerEffect: 240, maxTotalTiles: 480, pixelBudget: 1_500_000))
        let first = try accepted(core.admit(request(tiles: 240, width: 1000, height: 750), at: 0))
        _ = try accepted(core.admit(request(tiles: 240, width: 1000, height: 750), at: 0))
        XCTAssertEqual(core.usedTiles, 480)
        XCTAssertEqual(core.usedPixels, 1_500_000)
        XCTAssertEqual(core.admit(request(tiles: 1, width: 1, height: 1), at: 0).decision,
                       .rejected(.totalTileLimit))
        XCTAssertEqual(core.activeLeases.count, 2)
        XCTAssertTrue(core.release(first))
        _ = try accepted(core.admit(request(tiles: 1, width: 1000, height: 750), at: 0))
        XCTAssertEqual(core.admit(request(tiles: 1, width: 1, height: 1), at: 0).decision,
                       .rejected(.pixelLimit))
        XCTAssertEqual(core.usedTiles, 241)
        XCTAssertEqual(core.usedPixels, 1_500_000)
    }

    func testConcurrentAndPerEffectCaps() throws {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(
            maxConcurrent: 3, maxTilesPerEffect: 240, maxTotalTiles: 480))
        XCTAssertEqual(core.admit(request(tiles: 241), at: 0).decision, .rejected(.effectTileLimit))
        for _ in 0..<3 { _ = try accepted(core.admit(request(tiles: 1), at: 0)) }
        XCTAssertEqual(core.admit(request(tiles: 1), at: 0).decision, .rejected(.concurrentLimit))
        XCTAssertEqual(core.usedTiles, 3)
    }

    func testActualBitmapPixelsNotPoints() {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(pixelBudget: 10_000))
        // A 100x100 point view rendered at 3x must report 300x300 pixels.
        XCTAssertEqual(core.admit(request(width: 300, height: 300), at: 0).decision,
                       .rejected(.pixelLimit))
        XCTAssertEqual(core.usedPixels, 0)
    }

    func testInvalidRequestsAndMultiplicationOverflow() {
        var core = NDAAdmissionController()
        let invalid = [request(tiles: 0), request(tiles: -1), request(width: 0),
            request(height: -1), request(width: Int.max, height: Int.max)]
        for input in invalid {
            XCTAssertEqual(core.admit(input, at: 0).decision, .rejected(.invalidRequest))
            XCTAssertTrue(core.activeLeases.isEmpty)
            XCTAssertEqual(core.usedTiles, 0)
            XCTAssertEqual(core.usedPixels, 0)
        }
    }

    func testExpiryBoundaryAndAdmissionReturnsCleanup() throws {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(duration: 0.8, leaseLifetime: 1))
        let input = request()
        let lease = try accepted(core.admit(input, at: 10))
        XCTAssertEqual(lease.expiresAt, 11)
        XCTAssertTrue(core.expire(at: 10.999).isEmpty)
        let result = core.admit(input, at: 11)
        let replacement = try accepted(result)
        XCTAssertEqual(result.expiredLeases, [lease])
        XCTAssertEqual(core.activeLeases, [replacement])
        XCTAssertEqual(core.expire(at: 12), [replacement])
        XCTAssertTrue(core.expire(at: 12).isEmpty)
        XCTAssertEqual(core.usedTiles, 0)
        XCTAssertEqual(core.usedPixels, 0)
        XCTAssertFalse(core.release(lease))
    }

    func testRejectedAdmissionAlsoReturnsExpiredLeases() throws {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(duration: 0.8, leaseLifetime: 1))
        let lease = try accepted(core.admit(request(), at: 0))
        let rejected = core.admit(request(tiles: 0), at: 1)
        XCTAssertEqual(rejected.decision, .rejected(.invalidRequest))
        XCTAssertEqual(rejected.expiredLeases, [lease])
        XCTAssertEqual(core.usedTiles, 0)
    }

    func testBackwardsAndInvalidTimeDoNotExtendOrCorrupt() throws {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(duration: 0.8, leaseLifetime: 1))
        let lease = try accepted(core.admit(request(), at: 10))
        let backward = try accepted(core.admit(request(), at: 1))
        XCTAssertEqual(backward.admittedAt, 10)
        XCTAssertEqual(backward.expiresAt, 11)
        for invalid in [Double.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
            XCTAssertEqual(core.admit(request(), at: invalid).decision, .rejected(.invalidTime))
            XCTAssertTrue(core.expire(at: invalid).isEmpty)
            XCTAssertEqual(core.activeLeases, [lease, backward])
            XCTAssertEqual(core.lastObservedTime, 10)
        }
        XCTAssertEqual(core.expire(at: 11), [lease, backward])
    }

    func testBatchIsBoundedAndInputOrdered() throws {
        var core = NDAAdmissionController(policy: NDAEffectPolicy(maxConcurrent: 20))
        let inputs = (0..<100).map { _ in request(tiles: 1, width: 1, height: 1) }
        let batch = core.admitBatch(inputs, at: 0)
        XCTAssertEqual(batch.results.count, 8)
        XCTAssertEqual(batch.skippedCount, 92)
        for (index, result) in batch.results.enumerated() {
            XCTAssertEqual(try accepted(result).token, inputs[index].token)
        }
        XCTAssertEqual(core.usedTiles, 8)
        XCTAssertEqual(core.usedPixels, 8)
        let empty = core.admitBatch([], at: 100)
        XCTAssertTrue(empty.results.isEmpty)
        XCTAssertEqual(empty.skippedCount, 0)
        // Empty batches intentionally do not tick; explicit expire owns timer cleanup.
        XCTAssertEqual(core.activeLeases.count, 8)
    }

    func testCancelAllReturnsResourcesAndKeepsClockWatermark() throws {
        var core = NDAAdmissionController()
        let lease = try accepted(core.admit(request(), at: 10))
        XCTAssertEqual(core.cancelAll(), [lease])
        XCTAssertTrue(core.cancelAll().isEmpty)
        XCTAssertEqual(core.usedTiles, 0)
        XCTAssertEqual(core.usedPixels, 0)
        XCTAssertFalse(core.release(lease))
        let next = try accepted(core.admit(request(), at: 0))
        XCTAssertEqual(next.admittedAt, 10)
    }
}
