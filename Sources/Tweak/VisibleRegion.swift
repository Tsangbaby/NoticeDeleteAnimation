import UIKit
import QuartzCore

/// Value-only geometry plus weak identities for the surviving surface -> window
/// chain. In particular, a plan never keeps a removed notification view alive.
struct NDARegionCheckpoint {
    fileprivate weak var view: UIView?
    private let identity: ObjectIdentifier
    private let parentIdentity: ObjectIdentifier?
    private let layerIdentity: ObjectIdentifier
    private let bounds: CGRect
    private let center: CGPoint
    private let layerBounds: CGRect
    private let position: CGPoint
    private let anchorPoint: CGPoint
    private let anchorPointZ: CGFloat
    private let zPosition: CGFloat
    private let transform: CATransform3D
    private let sublayerTransform: CATransform3D
    private let alpha: CGFloat
    private let opacity: Float
    private let hidden: Bool
    private let layerHidden: Bool
    private let clips: Bool
    private let masksToBounds: Bool
    private let cornerRadius: CGFloat
    private let maskedCorners: UInt
    private let cornerCurve: String
    private let geometryFlipped: Bool

    fileprivate init(_ view: UIView) {
        self.view = view
        identity = ObjectIdentifier(view)
        parentIdentity = view.superview.map { ObjectIdentifier($0) }
        let layer = view.layer
        layerIdentity = ObjectIdentifier(layer)
        bounds = view.bounds; center = view.center
        layerBounds = layer.bounds; position = layer.position
        anchorPoint = layer.anchorPoint; anchorPointZ = layer.anchorPointZ
        zPosition = layer.zPosition
        transform = layer.transform; sublayerTransform = layer.sublayerTransform
        alpha = view.alpha; opacity = layer.opacity
        hidden = view.isHidden; layerHidden = layer.isHidden
        clips = view.clipsToBounds; masksToBounds = layer.masksToBounds
        cornerRadius = layer.cornerRadius; maskedCorners = layer.maskedCorners.rawValue
        cornerCurve = layer.cornerCurve.rawValue
        geometryFlipped = layer.isGeometryFlipped
    }

    fileprivate func matches(_ candidate: UIView) -> Bool {
        let layer = candidate.layer
        return view === candidate && ObjectIdentifier(candidate) == identity &&
            candidate.superview.map { ObjectIdentifier($0) } == parentIdentity &&
            ObjectIdentifier(layer) == layerIdentity &&
            candidate.bounds == bounds && candidate.center == center &&
            layer.bounds == layerBounds && layer.position == position &&
            layer.anchorPoint == anchorPoint && layer.anchorPointZ == anchorPointZ &&
            layer.zPosition == zPosition &&
            CATransform3DEqualToTransform(layer.transform, transform) &&
            CATransform3DEqualToTransform(layer.sublayerTransform, sublayerTransform) &&
            candidate.alpha == alpha && layer.opacity == opacity &&
            candidate.isHidden == hidden && layer.isHidden == layerHidden &&
            candidate.clipsToBounds == clips && layer.masksToBounds == masksToBounds &&
            layer.cornerRadius == cornerRadius && layer.maskedCorners.rawValue == maskedCorners &&
            layer.cornerCurve.rawValue == cornerCurve && layer.isGeometryFlipped == geometryFlipped &&
            layer.mask == nil && (layer.animationKeys() ?? []).isEmpty
    }
}

struct NDAVisibleRegion {
    let sourceBounds: CGRect
    let sourceRect: CGRect
    let surfaceRect: CGRect
    /// The common allowed viewport, not the source's footprint (unless it clips).
    let clipRect: CGRect
    let partial: Bool
    let checkpoints: [NDARegionCheckpoint]
    private let captureCheckpoints: [NDARegionCheckpoint]

    fileprivate init(sourceBounds: CGRect, sourceRect: CGRect, surfaceRect: CGRect,
                     clipRect: CGRect, partial: Bool, checkpoints: [NDARegionCheckpoint],
                     captureCheckpoints: [NDARegionCheckpoint]) {
        self.sourceBounds = sourceBounds; self.sourceRect = sourceRect
        self.surfaceRect = surfaceRect; self.clipRect = clipRect; self.partial = partial
        self.checkpoints = checkpoints; self.captureCheckpoints = captureCheckpoints
    }

    /// Attached-source pre/post capture validation, including weak identities
    /// BELOW the surface. Equal numerical rectangles alone cannot detect a
    /// drawing callback reparenting a notification into an identical wrapper.
    func isCaptureValid(source: UIView, surface: UIView, window: UIWindow) -> Bool {
        guard Thread.isMainThread, source.window === window, source.bounds == sourceBounds,
              !captureCheckpoints.isEmpty, captureCheckpoints.count <= 64,
              captureCheckpoints.first?.view === source, captureCheckpoints.last?.view === window,
              isValid(surface: surface, window: window) else { return false }
        var current: UIView? = source
        var reachedSurface = false
        var effectiveAlpha: CGFloat = 1
        for (index, checkpoint) in captureCheckpoints.enumerated() {
            guard let view = current, checkpoint.matches(view) else { return false }
            effectiveAlpha *= min(view.alpha, CGFloat(view.layer.opacity))
            guard effectiveAlpha.isFinite, effectiveAlpha >= 0.99,
                  !view.isHidden, !view.layer.isHidden else { return false }
            if view === surface { reachedSurface = true }
            if view === window { return reachedSurface && index == captureCheckpoints.count - 1 }
            current = view.superview
        }
        return false
    }

    /// Align inward on the source.bounds-origin capture grid, including signed
    /// origins. No frame/bounds/contentOffset writes, and no expansion tolerance.
    func inwardAligned(scale: CGFloat, source: UIView, surface: UIView) -> NDAVisibleRegion? {
        guard Thread.isMainThread, scale.isFinite, scale > 0, (1 / scale).isFinite,
              source.bounds == sourceBounds, let window = surface.window,
              isCaptureValid(source: source, surface: surface, window: window),
              case .accepted(let fresh) = NDAVisibleRegionPlanner.resolve(source, through: surface, window: window),
              fresh.sourceBounds == sourceBounds, fresh.clipRect == clipRect,
              fresh.sourceRect.contains(sourceRect), fresh.surfaceRect.contains(surfaceRect),
              NDAVisibleRegionPlanner.map(sourceRect, from: source, to: surface) == surfaceRect else { return nil }
        // Below 2^52, adding one grid index is representable; never convert an
        // unchecked CGFloat to Int (including in overflow/underflow cases).
        let indexLimit: CGFloat = 4_503_599_627_370_496
        let origin = sourceBounds.origin
        let products = [(sourceRect.minX - origin.x) * scale, (sourceRect.minY - origin.y) * scale,
                        (sourceRect.maxX - origin.x) * scale, (sourceRect.maxY - origin.y) * scale]
        guard products.allSatisfy({ $0.isFinite && abs($0) < indexLimit }) else { return nil }
        var left = products[0].rounded(.up), top = products[1].rounded(.up)
        var right = products[2].rounded(.down), bottom = products[3].rounded(.down)
        // Division can round an aligned endpoint outward by one ULP. Move a
        // whole pixel inward instead of accepting epsilon-sized hidden content.
        if origin.x + left / scale < sourceRect.minX { left += 1 }
        if origin.y + top / scale < sourceRect.minY { top += 1 }
        if origin.x + right / scale > sourceRect.maxX { right -= 1 }
        if origin.y + bottom / scale > sourceRect.maxY { bottom -= 1 }
        for _ in 0..<4 {
            let x = origin.x + left / scale, y = origin.y + top / scale
            let maxX = origin.x + right / scale, maxY = origin.y + bottom / scale
            let crop = CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
            let pixelsWide = crop.width * scale, pixelsHigh = crop.height * scale
            guard right - left > 1, bottom - top > 1,
                  pixelsWide.isFinite, pixelsHigh.isFinite, pixelsWide > 1, pixelsHigh > 1,
                  pixelsWide < indexLimit, pixelsHigh < indexLimit,
                  NDAVisibleRegionPlanner.safeRect(crop), sourceRect.contains(crop),
                  let mapped = NDAVisibleRegionPlanner.map(crop, from: source, to: surface) else { return nil }
            if clipRect.contains(mapped) && surfaceRect.contains(mapped) {
                return NDAVisibleRegion(sourceBounds: sourceBounds, sourceRect: crop,
                    surfaceRect: mapped, clipRect: clipRect, partial: crop != sourceBounds,
                    checkpoints: checkpoints, captureCheckpoints: captureCheckpoints)
            }
            if mapped.minX < max(clipRect.minX, surfaceRect.minX) { left += 1 }
            if mapped.minY < max(clipRect.minY, surfaceRect.minY) { top += 1 }
            if mapped.maxX > min(clipRect.maxX, surfaceRect.maxX) { right -= 1 }
            if mapped.maxY > min(clipRect.maxY, surfaceRect.maxY) { bottom -= 1 }
        }
        return nil
    }

    /// Only surviving nodes are checked: the source and wrappers below the
    /// surface are deliberately absent, since removal is the commit operation.
    func isValid(surface: UIView, window: UIWindow) -> Bool {
        guard Thread.isMainThread, !checkpoints.isEmpty, checkpoints.count <= 64,
              checkpoints.first?.view === surface, checkpoints.last?.view === window,
              surface.window === window,
              NDAVisibleRegionPlanner.safeRect(sourceBounds),
              NDAVisibleRegionPlanner.safeRect(sourceRect), sourceBounds.contains(sourceRect),
              NDAVisibleRegionPlanner.safeRect(surfaceRect),
              NDAVisibleRegionPlanner.safeRect(clipRect), clipRect.contains(surfaceRect) else { return false }
        var current: UIView? = surface
        var effectiveAlpha: CGFloat = 1
        for (index, checkpoint) in checkpoints.enumerated() {
            guard let view = current, checkpoint.matches(view) else { return false }
            effectiveAlpha *= min(view.alpha, CGFloat(view.layer.opacity))
            guard effectiveAlpha.isFinite, effectiveAlpha >= 0.99,
                  !view.isHidden, !view.layer.isHidden,
                  CATransform3DIsIdentity(view.layer.transform),
                  CATransform3DIsIdentity(view.layer.sublayerTransform),
                  NDAVisibleRegionPlanner.safeViewGeometry(view),
                  (!(view.clipsToBounds || view.layer.masksToBounds || view === surface || view === window) ||
                    view.layer.cornerRadius == 0) else { return false }
            if view === window { return index == checkpoints.count - 1 }
            current = view.superview
        }
        return false
    }
}

enum NDAVisibleRegionResult {
    case accepted(NDAVisibleRegion)
    case rejected(NDAAncestorFailure)
}

/// Full-chain, rectangular-only geometry preflight. This intentionally does not
/// call or relax NDAAncestorGate: the alpha6 gate remains an unchanged control.
enum NDAVisibleRegionPlanner {
    private struct Node {
        let view: UIView
        let depth: Int
        let effectiveAlpha: CGFloat
    }
    // A finite bound also avoids CGRect endpoint overflow and geometry whose
    // subpixel positions cannot be represented usefully by UIKit. It is NOT an
    // allocation budget; the existing capture/admission guards still apply.
    private static let coordinateLimit: CGFloat = 1_099_511_627_776

    fileprivate static func safeRect(_ rect: CGRect) -> Bool {
        let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
                      rect.maxX, rect.maxY]
        return !rect.isNull && !rect.isInfinite &&
            values.allSatisfy { $0.isFinite && abs($0) <= coordinateLimit } &&
            rect.size.width > 0 && rect.size.height > 0 &&
            rect.maxX > rect.origin.x && rect.maxY > rect.origin.y
    }
    private static func safePoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite &&
            abs(point.x) <= coordinateLimit && abs(point.y) <= coordinateLimit
    }
    fileprivate static func safeViewGeometry(_ view: UIView) -> Bool {
        let layer = view.layer
        return safeRect(view.bounds) && safeRect(layer.bounds) &&
            safePoint(view.center) && safePoint(layer.position) && safePoint(layer.anchorPoint) &&
            layer.anchorPointZ.isFinite && abs(layer.anchorPointZ) <= coordinateLimit &&
            layer.zPosition.isFinite && abs(layer.zPosition) <= coordinateLimit &&
            layer.cornerRadius.isFinite && layer.cornerRadius >= 0
    }
    private static func supported(_ transform: CATransform3D) -> Bool {
        guard CATransform3DIsAffine(transform) else { return false }
        let a = CATransform3DGetAffineTransform(transform)
        return a.a.isFinite && a.d.isFinite && a.tx.isFinite && a.ty.isFinite &&
            a.a > 0 && a.d > 0 && a.b == 0 && a.c == 0
    }

    /// Actual UIKit point conversion, not an AABB of a rotated rectangle or a
    /// hand-subtracted scroll offset. Checking all corners catches collapsed,
    /// reversed or otherwise unrepresentable cumulative mappings as well.
    fileprivate static func map(_ rect: CGRect, from: UIView, to: UIView) -> CGRect? {
        guard safeRect(rect) else { return nil }
        let p = from.convert(rect.origin, to: to)
        let x = from.convert(CGPoint(x: rect.maxX, y: rect.minY), to: to)
        let y = from.convert(CGPoint(x: rect.minX, y: rect.maxY), to: to)
        let xy = from.convert(CGPoint(x: rect.maxX, y: rect.maxY), to: to)
        guard [p, x, y, xy].allSatisfy({ safePoint($0) }),
              p.y == x.y, p.x == y.x, x.x == xy.x, y.y == xy.y,
              x.x > p.x, y.y > p.y else { return nil }
        let result = CGRect(x: p.x, y: p.y, width: x.x - p.x, height: y.y - p.y)
        return safeRect(result) ? result : nil
    }

    private static func rejected(_ reason: NDAAncestorReason, source: UIView,
                                 node: Node, geometry: Bool = false) -> NDAVisibleRegionResult {
        let operands = geometry ? NDAClippingGeometry(sourceBounds: source.bounds,
            sourceInAncestor: source.convert(source.bounds, to: node.view),
            ancestorBounds: node.view.bounds) : nil
        return .rejected(NDAAncestorFailure(reason: reason, view: node.view,
            depth: node.depth, effectiveAlpha: node.effectiveAlpha, clipping: operands))
    }

    static func resolve(_ source: UIView, through surface: UIView, window: UIWindow) -> NDAVisibleRegionResult {
        var nodes: [Node] = []
        var checkpoints: [NDARegionCheckpoint] = []
        var current: UIView? = source
        var reachedSurface = false
        var effectiveAlpha: CGFloat = 1
        var cumulativeX: CGFloat = 1, cumulativeY: CGFloat = 1
        var last = Node(view: source, depth: 1, effectiveAlpha: 1)
        guard Thread.isMainThread else { return rejected(.hierarchy, source: source, node: last) }
        while let view = current, nodes.count < 64 {
            effectiveAlpha *= min(view.alpha, CGFloat(view.layer.opacity))
            let node = Node(view: view, depth: nodes.count + 1, effectiveAlpha: effectiveAlpha)
            last = node
            if view.isHidden || view.layer.isHidden { return rejected(.hidden, source: source, node: node) }
            if !view.alpha.isFinite || !view.layer.opacity.isFinite ||
                !effectiveAlpha.isFinite || effectiveAlpha < 0.99 || view.alpha > 1 || view.layer.opacity > 1 {
                return rejected(.alpha, source: source, node: node)
            }
            if !supported(view.layer.transform) { return rejected(.transform, source: source, node: node) }
            if !CATransform3DIsIdentity(view.layer.sublayerTransform) {
                return rejected(.sublayer, source: source, node: node)
            }
            if view.layer.mask != nil { return rejected(.mask, source: source, node: node) }
            if !(view.layer.animationKeys() ?? []).isEmpty {
                return rejected(.animations, source: source, node: node)
            }
            if view === surface { reachedSurface = true }
            if (reachedSurface || view === window) && !CATransform3DIsIdentity(view.layer.transform) {
                return rejected(.transform, source: source, node: node)
            }
            let affine = CATransform3DGetAffineTransform(view.layer.transform)
            cumulativeX *= affine.a; cumulativeY *= affine.d
            if !safeViewGeometry(view) ||
                !cumulativeX.isFinite || !cumulativeY.isFinite || cumulativeX <= 0 || cumulativeY <= 0 ||
                !(1 / cumulativeX).isFinite || !(1 / cumulativeY).isFinite ||
                (view === source && (source.bounds.width > 2048 || source.bounds.height > 2048)) ||
                ((view.clipsToBounds || view.layer.masksToBounds || view === surface || view === window) &&
                    view.layer.cornerRadius != 0) {
                return rejected(.clipping, source: source, node: node, geometry: true)
            }
            nodes.append(node)
            if reachedSurface { checkpoints.append(NDARegionCheckpoint(view)) }
            if view === window {
                guard reachedSurface, source.window === window, surface.window === window else {
                    return rejected(.hierarchy, source: source, node: node)
                }
                return intersect(source, surface: surface, nodes: nodes, checkpoints: checkpoints)
            }
            current = view.superview
        }
        return rejected(current == nil ? .hierarchy : .depth, source: source, node: last)
    }

    private static func intersect(_ source: UIView, surface: UIView, nodes: [Node],
                                  checkpoints: [NDARegionCheckpoint]) -> NDAVisibleRegionResult {
        // Policies for ALL nodes have already passed. A partial clip never
        // short-circuits the traversal and cannot hide a later mask/hidden node.
        let surfaceNode = nodes.first { $0.view === surface }!
        let captureCheckpoints = nodes.map { NDARegionCheckpoint($0.view) }
        guard let whole = map(source.bounds, from: source, to: surface) else {
            return rejected(.clipping, source: source, node: surfaceNode, geometry: true)
        }
        var viewport = surface.bounds
        for node in nodes {
            let view = node.view
            // Check intermediate mappings even for non-clipping ancestors;
            // scale/translation cancellation must not disguise a collapsed step.
            guard map(source.bounds, from: source, to: view) != nil else {
                return rejected(.clipping, source: source, node: node, geometry: true)
            }
            guard view.clipsToBounds || view.layer.masksToBounds || view === surface || view === nodes.last?.view else {
                continue
            }
            guard let allowed = map(view.bounds, from: view, to: surface) else {
                return rejected(.clipping, source: source, node: node, geometry: true)
            }
            viewport = viewport.intersection(allowed)
            guard safeRect(viewport), safeRect(whole.intersection(viewport)) else {
                return rejected(.clipping, source: source, node: node, geometry: true)
            }
        }
        guard let inverse = map(viewport, from: surface, to: source) else {
            return rejected(.clipping, source: source, node: surfaceNode, geometry: true)
        }
        var crop = source.bounds.intersection(inverse)
        guard safeRect(crop) else {
            return rejected(.clipping, source: source, node: surfaceNode, geometry: true)
        }
        // Round-trip conversion can overshoot a clip edge by one ULP. Only
        // shrink; no epsilon enlargement or offscreen restoration is allowed.
        for _ in 0..<8 {
            guard source.bounds.contains(crop), let mapped = map(crop, from: source, to: surface) else { break }
            if viewport.contains(mapped) {
                return .accepted(NDAVisibleRegion(sourceBounds: source.bounds, sourceRect: crop,
                    surfaceRect: mapped, clipRect: viewport, partial: crop != source.bounds,
                    checkpoints: checkpoints, captureCheckpoints: captureCheckpoints))
            }
            var left = crop.minX, top = crop.minY, right = crop.maxX, bottom = crop.maxY
            if mapped.minX < viewport.minX {
                let delta = (viewport.minX - mapped.minX) / mapped.width * crop.width
                left = max(left.nextUp, (left + delta).nextUp)
            }
            if mapped.minY < viewport.minY {
                let delta = (viewport.minY - mapped.minY) / mapped.height * crop.height
                top = max(top.nextUp, (top + delta).nextUp)
            }
            if mapped.maxX > viewport.maxX {
                let delta = (mapped.maxX - viewport.maxX) / mapped.width * crop.width
                right = min(right.nextDown, (right - delta).nextDown)
            }
            if mapped.maxY > viewport.maxY {
                let delta = (mapped.maxY - viewport.maxY) / mapped.height * crop.height
                bottom = min(bottom.nextDown, (bottom - delta).nextDown)
            }
            crop = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            guard safeRect(crop) else { break }
        }
        return rejected(.clipping, source: source, node: surfaceNode, geometry: true)
    }
}
