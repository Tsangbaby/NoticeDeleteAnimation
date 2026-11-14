import Foundation

/// token identifies a source deletion; do not use notification text as its identity.
/// Bitmap dimensions must be the actual allocated image pixels, not view points.
public struct NDAAdmissionRequest: Equatable {
    public let token: UUID
    public let tileCount: Int
    public let bitmapWidth: Int
    public let bitmapHeight: Int

    public init(token: UUID, tileCount: Int, bitmapWidth: Int, bitmapHeight: Int) {
        self.token = token
        self.tileCount = tileCount
        self.bitmapWidth = bitmapWidth
        self.bitmapHeight = bitmapHeight
    }
}

/// A distinct lease ID protects a reused source token from stale completion callbacks.
public struct NDAEffectLease: Equatable {
    public let id: UUID
    public let token: UUID
    public let tileCount: Int
    public let pixelCount: Int
    public let admittedAt: Double
    public let expiresAt: Double
}

public enum NDAAdmissionRejection: Equatable {
    case invalidTime
    case invalidRequest
    case duplicateToken
    case concurrentLimit
    case effectTileLimit
    case totalTileLimit
    case pixelLimit
}

public enum NDAAdmissionDecision: Equatable {
    case accepted(NDAEffectLease)
    case rejected(NDAAdmissionRejection)
}

/// Expired leases are returned even when admission fails. The renderer MUST destroy
/// their snapshots/layers immediately. Accounting alone cannot free UI resources.
public struct NDAAdmissionResult: Equatable {
    public let decision: NDAAdmissionDecision
    public let expiredLeases: [NDAEffectLease]
}

public struct NDAAdmissionBatchResult: Equatable {
    /// Only the first maxCellsPerBatch inputs are evaluated, in input order.
    public let results: [NDAAdmissionResult]
    public let skippedCount: Int
}

/// Pure, bounded, caller-serialized resource ledger; no timers, locks or UI objects.
/// Supply monotonic seconds (e.g. system uptime), not wall-clock dates. Finite
/// backwards times are clamped to the last observed time and cannot extend leases.
/// Invalid/negative/unrepresentable times do not mutate state. An active token is
/// admitted at most once; after release/expiry it may be reused with a new lease ID.
/// The owner must call expire on a timer and cancel all on surface/background loss.
/// This value type should have ONE authoritative owner; do not copy an active ledger.
public struct NDAAdmissionController {
    public let policy: NDAEffectPolicy
    public private(set) var activeLeases: [NDAEffectLease] = []
    public private(set) var usedTiles: Int = 0
    public private(set) var usedPixels: Int = 0
    public private(set) var lastObservedTime: Double?

    public init(policy: NDAEffectPolicy = NDAEffectPolicy()) { self.policy = policy }

    private mutating func advance(to now: Double) -> [NDAEffectLease]? {
        guard now.isFinite, now >= 0 else { return nil }
        let effective = max(lastObservedTime ?? now, now)
        let end = effective + policy.leaseLifetime
        guard end.isFinite, end > effective else { return nil }
        lastObservedTime = effective
        let expired = activeLeases.filter { $0.expiresAt <= effective }
        activeLeases.removeAll { $0.expiresAt <= effective }
        recount()
        return expired
    }

    private mutating func recount() {
        usedTiles = activeLeases.reduce(0) { $0 + $1.tileCount }
        usedPixels = activeLeases.reduce(0) { $0 + $1.pixelCount }
    }

    public mutating func admit(_ request: NDAAdmissionRequest, at now: Double) -> NDAAdmissionResult {
        guard let expired = advance(to: now), let effective = lastObservedTime else {
            return NDAAdmissionResult(decision: .rejected(.invalidTime), expiredLeases: [])
        }
        func reject(_ reason: NDAAdmissionRejection) -> NDAAdmissionResult {
            NDAAdmissionResult(decision: .rejected(reason), expiredLeases: expired)
        }
        guard request.tileCount > 0, request.bitmapWidth > 0, request.bitmapHeight > 0 else {
            return reject(.invalidRequest)
        }
        let pixels = request.bitmapWidth.multipliedReportingOverflow(by: request.bitmapHeight)
        guard !pixels.overflow, pixels.partialValue > 0 else { return reject(.invalidRequest) }
        guard !activeLeases.contains(where: { $0.token == request.token }) else {
            return reject(.duplicateToken)
        }
        guard activeLeases.count < policy.maxConcurrent else { return reject(.concurrentLimit) }
        guard request.tileCount <= policy.maxTilesPerEffect else { return reject(.effectTileLimit) }
        guard request.tileCount <= policy.maxTotalTiles - usedTiles else { return reject(.totalTileLimit) }
        guard pixels.partialValue <= policy.pixelBudget - usedPixels else { return reject(.pixelLimit) }
        let lease = NDAEffectLease(id: UUID(), token: request.token, tileCount: request.tileCount,
                                   pixelCount: pixels.partialValue, admittedAt: effective,
                                   expiresAt: effective + policy.leaseLifetime)
        activeLeases.append(lease)
        recount()
        return NDAAdmissionResult(decision: .accepted(lease), expiredLeases: expired)
    }

    public mutating func admitBatch(_ requests: [NDAAdmissionRequest], at now: Double) -> NDAAdmissionBatchResult {
        var results: [NDAAdmissionResult] = []
        for request in requests.prefix(policy.maxCellsPerBatch) {
            results.append(admit(request, at: now))
        }
        return NDAAdmissionBatchResult(results: results,
            skippedCount: max(0, requests.count - policy.maxCellsPerBatch))
    }

    /// Invalid times return an empty list, preserving state. Boundary is >= expiresAt.
    @discardableResult
    public mutating func expire(at now: Double) -> [NDAEffectLease] {
        advance(to: now) ?? []
    }

    /// Idempotent; passing a stale lease cannot release a newer same-token admission.
    @discardableResult
    public mutating func release(_ lease: NDAEffectLease) -> Bool {
        guard let index = activeLeases.firstIndex(where: { $0.id == lease.id }) else { return false }
        activeLeases.remove(at: index)
        recount()
        return true
    }

    /// Releases all accounting, retaining the monotonic time watermark.
    /// Returned leases identify every overlay/snapshot the caller must destroy.
    @discardableResult
    public mutating func cancelAll() -> [NDAEffectLease] {
        let leases = activeLeases
        activeLeases.removeAll(keepingCapacity: false)
        recount()
        return leases
    }
}
