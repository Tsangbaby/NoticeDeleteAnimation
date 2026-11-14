import Foundation
import XCTest
@testable import NoticeDeleteAnimationCore

final class ParticlePlanTests: XCTestCase {
    func testSplitMixFixedVectors() {
        var generator = NDASeededGenerator(seed: 0)
        XCTAssertEqual(generator.nextUInt64(), 0xe220a8397b1dcdaf)
        XCTAssertEqual(generator.nextUInt64(), 0x6e789e6aa1b965f4)
        XCTAssertEqual(generator.nextUInt64(), 0x06c45d188009454f)
        var unit = NDASeededGenerator(seed: 0)
        XCTAssertEqual(unit.nextUnit(), 0.8833108082136426, accuracy: 1e-15)
        XCTAssertEqual(unit.nextUnit(), 0.43152799704850997, accuracy: 1e-15)
    }

    func testFixedParticleVector() throws {
        let plan = try XCTUnwrap(NDAParticlePlan.make(width: 1, height: 1, seed: 0,
            policy: NDAEffectPolicy(maxTilesPerEffect: 1)))
        XCTAssertEqual(plan.columns, 1)
        XCTAssertEqual(plan.rows, 1)
        let first = try XCTUnwrap(plan.particles.first)
        XCTAssertEqual(first.rect, NDAUnitRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(first.dx, 0.1 * (2 * 0.8833108082136426 - 1), accuracy: 1e-15)
        XCTAssertEqual(first.dy, -1.2 * (2.0 / 3.0 + 0.43152799704850997 * (2.0 / 3.0)), accuracy: 1e-15)
        XCTAssertEqual(first.rotation, 0.7 * (2 * 0.026433771592597743 - 1), accuracy: 1e-15)
        XCTAssertEqual(first.delay, 1.35 * 0.42 * 0.9708819781538285, accuracy: 1e-15)
        XCTAssertEqual(first.delay + first.duration, 1.35, accuracy: 1e-15)
    }

    func testRepeatabilityAndSeedSensitivity() throws {
        let a = try XCTUnwrap(NDAParticlePlan.make(width: 400, height: 100, seed: 123))
        let b = try XCTUnwrap(NDAParticlePlan.make(width: 400, height: 100, seed: 123))
        let c = try XCTUnwrap(NDAParticlePlan.make(width: 400, height: 100, seed: 124))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertGreaterThan(a.columns, a.rows)
    }

    func testGridAndMotionInvariants() throws {
        let sizes: [(Double, Double)] = [(1, 1), (400, 100), (100, 400),
            (1e-300, 1e7), (1e7, 1e-300), (10, 1), (1, 10)]
        for cap in [1, 2, 7, 17, 240, 4096] {
            for (width, height) in sizes {
                let policy = NDAEffectPolicy(maxTilesPerEffect: cap, maxTotalTiles: 4096)
                let plan = try XCTUnwrap(NDAParticlePlan.make(width: width, height: height,
                                                              seed: UInt64(cap), policy: policy))
                XCTAssertEqual(plan.particles.count, plan.columns * plan.rows)
                XCTAssertLessThanOrEqual(plan.particles.count, cap)
                XCTAssertFalse(plan.particles.isEmpty)
                var area = 0.0
                for (index, particle) in plan.particles.enumerated() {
                    let rect = particle.rect
                    area += rect.width * rect.height
                    XCTAssertEqual(rect.x, Double(index % plan.columns) / Double(plan.columns))
                    XCTAssertEqual(rect.y, Double(index / plan.columns) / Double(plan.rows))
                    XCTAssertGreaterThan(rect.width, 0)
                    XCTAssertGreaterThan(rect.height, 0)
                    XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-14)
                    XCTAssertLessThanOrEqual(rect.y + rect.height, 1 + 1e-14)
                    XCTAssertTrue(particle.dx.isFinite && particle.dy.isFinite)
                    XCTAssertLessThanOrEqual(abs(particle.dx), 0.1)
                    XCTAssertGreaterThanOrEqual(-particle.dy, 0.8 - 1e-14)
                    XCTAssertLessThanOrEqual(-particle.dy, 1.6 + 1e-14)
                    XCTAssertGreaterThanOrEqual(particle.delay, 0)
                    XCTAssertGreaterThan(particle.duration, 0)
                    XCTAssertEqual(particle.delay + particle.duration, policy.duration, accuracy: 1e-14)
                    XCTAssertLessThanOrEqual(abs(particle.rotation), 0.7)
                    XCTAssertEqual(particle.opacityKeyframes.map { $0.opacity }, [1, 1, 0])
                    XCTAssertEqual(particle.opacityKeyframes.last?.time, 1)
                }
                XCTAssertEqual(area, 1, accuracy: 1e-10)
            }
        }
    }

    func testInvalidDimensionsAndTotalCap() throws {
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, .greatestFiniteMagnitude] {
            XCTAssertNil(NDAParticlePlan.make(width: invalid, height: 10, seed: 0))
            XCTAssertNil(NDAParticlePlan.make(width: 10, height: invalid, seed: 0))
        }
        let plan = try XCTUnwrap(NDAParticlePlan.make(width: 100, height: 100, seed: 0,
            policy: NDAEffectPolicy(maxTilesPerEffect: 240, maxTotalTiles: 7)))
        XCTAssertLessThanOrEqual(plan.particles.count, 7)
    }

    func testPolicyAndMotionSanitization() {
        let defaults = NDAEffectPolicy()
        XCTAssertEqual(defaults.duration, 1.35)
        XCTAssertEqual(defaults.maxConcurrent, 2)
        XCTAssertEqual(defaults.maxTilesPerEffect, 900)
        XCTAssertEqual(defaults.maxTotalTiles, 1800)
        XCTAssertEqual(defaults.pixelBudget, 1_500_000)
        XCTAssertEqual(defaults.maxCellsPerBatch, 8)
        XCTAssertEqual(NDAEffectPolicy(duration: -1).duration, 0.35)
        XCTAssertEqual(NDAEffectPolicy(duration: 100).duration, 1.8)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(NDAEffectPolicy(duration: invalid).duration, 1.35)
            XCTAssertEqual(NDAMotionParameters(horizontalDrift: invalid).horizontalDrift, 0.1)
            XCTAssertEqual(NDAEffectPolicy(leaseLifetime: invalid).leaseLifetime, 1.6)
        }
        let bounded = NDAEffectPolicy(maxConcurrent: Int.max, maxTilesPerEffect: Int.max,
            maxTotalTiles: Int.max, pixelBudget: Int.max, maxCellsPerBatch: Int.max,
            leaseLifetime: Double.greatestFiniteMagnitude)
        XCTAssertEqual(bounded.maxConcurrent, 64)
        XCTAssertEqual(bounded.maxTilesPerEffect, 4096)
        XCTAssertEqual(bounded.maxTotalTiles, 16384)
        XCTAssertEqual(bounded.pixelBudget, 64_000_000)
        XCTAssertEqual(bounded.maxCellsPerBatch, 64)
        XCTAssertEqual(bounded.leaseLifetime, 10)
        let small = NDAEffectPolicy(maxConcurrent: -1, maxTilesPerEffect: 0,
            maxTotalTiles: -1, pixelBudget: 0, maxCellsPerBatch: -1, leaseLifetime: 0)
        XCTAssertEqual(small.maxConcurrent, 1)
        XCTAssertEqual(small.maxTilesPerEffect, 1)
        XCTAssertEqual(small.maxTotalTiles, 1)
        XCTAssertEqual(small.pixelBudget, 1)
        XCTAssertEqual(small.maxCellsPerBatch, 1)
        XCTAssertEqual(small.leaseLifetime, small.duration)
        let motion = NDAMotionParameters(horizontalDrift: -1, upwardDrift: 1e300,
            rotationMagnitude: 1e300, staggerFraction: 1e300, scaleEnd: -1, fadeStart: 1e300)
        XCTAssertEqual(motion.horizontalDrift, 0)
        XCTAssertEqual(motion.upwardDrift, 2)
        XCTAssertEqual(motion.rotationMagnitude, .pi * 2)
        XCTAssertEqual(motion.staggerFraction, 0.8)
        XCTAssertEqual(motion.scaleEnd, 0)
        XCTAssertEqual(motion.fadeStart, 0.95)
    }
}
