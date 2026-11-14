import Foundation

/// All limits are immutable and sanitized at initialization. Invalid duration uses 1.35s.
/// Bitmap budget counts actual width * height pixels, not points or visible crop area.
public struct NDAEffectPolicy: Equatable {
    public let duration: Double
    public let maxConcurrent: Int
    public let maxTilesPerEffect: Int
    public let maxTotalTiles: Int
    public let pixelBudget: Int
    public let maxCellsPerBatch: Int
    public let leaseLifetime: Double

    public init(duration: Double = 1.35, maxConcurrent: Int = 2,
                maxTilesPerEffect: Int = 900, maxTotalTiles: Int = 1800,
                pixelBudget: Int = 1_500_000, maxCellsPerBatch: Int = 8,
                leaseLifetime: Double? = nil) {
        let resolvedDuration = duration.isFinite ? min(1.8, max(0.35, duration)) : 1.35
        self.duration = resolvedDuration
        self.maxConcurrent = min(64, max(1, maxConcurrent))
        self.maxTilesPerEffect = min(4096, max(1, maxTilesPerEffect))
        self.maxTotalTiles = min(16384, max(1, maxTotalTiles))
        self.pixelBudget = min(64_000_000, max(1, pixelBudget))
        self.maxCellsPerBatch = min(64, max(1, maxCellsPerBatch))
        let lifetime = leaseLifetime ?? (resolvedDuration + 0.25)
        self.leaseLifetime = lifetime.isFinite
            ? min(10, max(resolvedDuration, lifetime)) : resolvedDuration + 0.25
    }
}

/// Unit coordinates relative to the entire snapshot, with top-left origin.
public struct NDAUnitRect: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Linear opacity keys. Times are fractions of this particle's own duration.
public struct NDAOpacityKeyframe: Equatable {
    public let time: Double
    public let opacity: Double
}

/// A renderer-independent target. dx/dy are fractions of the WHOLE snapshot's
/// width/height (positive y is down); rotation is radians; delay/duration seconds.
/// Start transform is identity, start scale/opacity are 1. Renderer may choose easing.
public struct NDAParticle: Equatable {
    public let rect: NDAUnitRect
    public let dx: Double
    public let dy: Double
    public let rotation: Double
    public let delay: Double
    public let duration: Double
    public let scaleEnd: Double
    public let opacityKeyframes: [NDAOpacityKeyframe]
}

/// Tunable dust profile: upward fragments, right-to-left breakup, ~1.35s total.
/// Qualitative reference characterization only; displacement/easing need visual tuning.
public struct NDAMotionParameters: Equatable {
    public let horizontalDrift: Double
    public let upwardDrift: Double
    public let rotationMagnitude: Double
    public let staggerFraction: Double
    public let scaleEnd: Double
    public let fadeStart: Double

    public init(horizontalDrift: Double = 0.1, upwardDrift: Double = 1.2,
                rotationMagnitude: Double = 0.7, staggerFraction: Double = 0.42,
                scaleEnd: Double = 0.12, fadeStart: Double = 0.18) {
        func value(_ x: Double, _ fallback: Double, _ lo: Double, _ hi: Double) -> Double {
            x.isFinite ? min(hi, max(lo, x)) : fallback
        }
        self.horizontalDrift = value(horizontalDrift, 0.1, 0, 2)
        self.upwardDrift = value(upwardDrift, 1.2, 0, 2)
        self.rotationMagnitude = value(rotationMagnitude, 0.7, 0, .pi * 2)
        self.staggerFraction = value(staggerFraction, 0.42, 0, 0.8)
        self.scaleEnd = value(scaleEnd, 0.12, 0, 1)
        self.fadeStart = value(fadeStart, 0.18, 0, 0.95)
    }
}

/// Stable SplitMix64: no randomized Hasher, platform clock or system RNG.
/// Wrapping arithmetic is part of the algorithm; seed zero is valid.
public struct NDASeededGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform discrete values in [0, 1), using exactly the high 53 bits.
    public mutating func nextUnit() -> Double {
        Double(nextUInt64() >> 11) * (1.0 / 9007199254740992.0)
    }
}

public struct NDAParticlePlan: Equatable {
    public let particles: [NDAParticle]
    public let columns: Int
    public let rows: Int
    /// Every delay + duration is <= totalDuration.
    public let totalDuration: Double

    /// Rejects nonfinite, nonpositive, or >10M dimensions before numeric conversion.
    /// Grid covers the unit rect exactly, row-major, without exceeding the tile cap.
    /// Aspect ratio is respected as closely as integer/budget constraints allow.
    public static func make(width: Double, height: Double, seed: UInt64,
                            policy: NDAEffectPolicy = NDAEffectPolicy(),
                            motion: NDAMotionParameters = NDAMotionParameters()) -> NDAParticlePlan? {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 10_000_000, height <= 10_000_000 else { return nil }
        let cap = min(policy.maxTilesPerEffect, policy.maxTotalTiles)
        // Clamp before division: even subnormal positive dimensions are safe.
        let aspect: Double
        if width >= height {
            aspect = min(Double(cap), width / height)
        } else {
            aspect = max(1 / Double(cap), width / height)
        }
        let columns = min(cap, max(1, Int(sqrt(Double(cap) * aspect).rounded())))
        let rows = max(1, cap / columns)
        var random = NDASeededGenerator(seed: seed)
        var particles: [NDAParticle] = []
        particles.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = Double(column) / Double(columns)
                let y = Double(row) / Double(rows)
                let right = Double(column + 1) / Double(columns)
                let bottom = Double(row + 1) / Double(rows)
                let drift = random.nextUnit() * 2 - 1
                let lift = 2.0 / 3.0 + random.nextUnit() * (2.0 / 3.0)
                let spin = random.nextUnit() * 2 - 1
                // Jitter stays within each column's band: every right column
                // starts before its immediate left neighbour, even across rows.
                let wave = (Double(columns - column - 1) + random.nextUnit()) / Double(columns)
                let delay = policy.duration * motion.staggerFraction * wave
                particles.append(NDAParticle(
                    rect: NDAUnitRect(x: x, y: y, width: right - x, height: bottom - y),
                    dx: motion.horizontalDrift * drift,
                    dy: -motion.upwardDrift * lift,
                    rotation: motion.rotationMagnitude * spin,
                    delay: delay, duration: policy.duration - delay,
                    scaleEnd: motion.scaleEnd,
                    opacityKeyframes: [NDAOpacityKeyframe(time: 0, opacity: 1),
                        NDAOpacityKeyframe(time: motion.fadeStart, opacity: 1),
                        NDAOpacityKeyframe(time: 1, opacity: 0)]))
            }
        }
        return NDAParticlePlan(particles: particles, columns: columns, rows: rows,
                               totalDuration: policy.duration)
    }
}
