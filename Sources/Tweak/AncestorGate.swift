import UIKit
import QuartzCore

/// The production capture gate, also compiled unchanged by the simulator harness.
/// No logging, snapshots or relaxation of the alpha4 predicates here.
enum NDAAncestorReason: String, CaseIterable {
    case hidden, alpha, transform, sublayer, mask, animations, clipping, depth, hierarchy
    var event: String { "ancestor." + rawValue }
}
/// Immutable operands from the precise production clipping predicate.
/// Kept only on a rejection; no later coordinate conversion or view mutation.
struct NDAClippingGeometry {
    let sourceBounds: CGRect
    let sourceInAncestor: CGRect
    let ancestorBounds: CGRect
}
struct NDAAncestorFailure {
    let reason: NDAAncestorReason
    let view: UIView
    let depth: Int
    let effectiveAlpha: CGFloat
    let clipping: NDAClippingGeometry?
}
enum NDAAncestorGate {
    static func supportedTransform(_ transform: CATransform3D) -> Bool {
        guard CATransform3DIsAffine(transform) else { return false }
        let affine = CATransform3DGetAffineTransform(transform)
        return affine.a.isFinite && affine.d.isFinite && affine.tx.isFinite && affine.ty.isFinite &&
            affine.a > 0 && affine.d > 0 && abs(affine.b) < 0.000001 && abs(affine.c) < 0.000001
    }

    /// Depth is one-based; at the cap report the last checked view (64), not
    /// an uninspected ancestor. A detached chain reports its last checked view.
    static func failure(_ source: UIView, through surface: UIView, window: UIWindow) -> NDAAncestorFailure? {
        var current: UIView? = source
        var reachedSurface = false
        var effectiveAlpha: CGFloat = 1
        var depth = 0
        var last = source
        func reject(_ reason: NDAAncestorReason, _ view: UIView,
                    clipping: NDAClippingGeometry? = nil) -> NDAAncestorFailure {
            NDAAncestorFailure(reason: reason, view: view, depth: depth,
                effectiveAlpha: effectiveAlpha, clipping: clipping)
        }
        while let view = current, depth < 64 {
            depth += 1
            last = view
            effectiveAlpha *= view.alpha
            if view.isHidden { return reject(.hidden, view) }
            if !(effectiveAlpha >= 0.99) { return reject(.alpha, view) }
            if !supportedTransform(view.layer.transform) { return reject(.transform, view) }
            if !CATransform3DIsIdentity(view.layer.sublayerTransform) { return reject(.sublayer, view) }
            if view.layer.mask != nil { return reject(.mask, view) }
            if !(view.layer.animationKeys() ?? []).isEmpty { return reject(.animations, view) }
            if view.clipsToBounds {
                let sourceBounds = source.bounds
                let rect = source.convert(sourceBounds, to: view)
                let ancestorBounds = view.bounds
                if !ancestorBounds.insetBy(dx: -0.5, dy: -0.5).contains(rect) {
                    return reject(.clipping, view, clipping: NDAClippingGeometry(
                        sourceBounds: sourceBounds, sourceInAncestor: rect, ancestorBounds: ancestorBounds))
                }
            }
            if view === surface { reachedSurface = true }
            if view === window { return reachedSurface ? nil : reject(.hierarchy, view) }
            current = view.superview
        }
        return reject(current == nil ? .hierarchy : .depth, last)
    }
}
