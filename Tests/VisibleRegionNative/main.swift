import UIKit
import QuartzCore
import Darwin

/// Calls only the production planner against real UIKit objects. No copied
/// visibility algorithm, bridge mock, private-device claim, or saved images.
@main
struct VisibleRegionNativeTests {
    static var checks = 0
    static var category = "geometry"
    static var counts: [String: Int] = [:]
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), "FAIL: " + name)
        checks += 1; counts[category, default: 0] += 1
        print("PASS: " + name)
    }
    struct Fixture {
        let window: UIWindow
        let host: UIView
        let surface: UIView
        let wrapper: UIView
        let source: UIView
        var views: [UIView] { [source, wrapper, surface, host, window] }
    }
    struct State {
        let view: UIView
        let bounds: CGRect
        let position: CGPoint
        let anchor: CGPoint
        let transform: CATransform3D
        let sublayer: CATransform3D
        let alpha: CGFloat
        let hidden: Bool
        let clips: Bool
        let corner: CGFloat
        let parent: UIView?
        let mask: CALayer?
        let keys: [String]
        init(_ view: UIView) {
            self.view = view; bounds = view.bounds; position = view.layer.position
            anchor = view.layer.anchorPoint; transform = view.layer.transform
            sublayer = view.layer.sublayerTransform; alpha = view.alpha
            hidden = view.isHidden; clips = view.clipsToBounds; corner = view.layer.cornerRadius
            parent = view.superview; mask = view.layer.mask
            keys = (view.layer.animationKeys() ?? []).sorted()
        }
        var unchanged: Bool {
            view.bounds == bounds && view.layer.position == position && view.layer.anchorPoint == anchor &&
                CATransform3DEqualToTransform(view.layer.transform, transform) &&
                CATransform3DEqualToTransform(view.layer.sublayerTransform, sublayer) &&
                view.alpha == alpha && view.isHidden == hidden && view.clipsToBounds == clips &&
                view.layer.cornerRadius == corner && view.superview === parent && view.layer.mask === mask &&
                (view.layer.animationKeys() ?? []).sorted() == keys
        }
    }
    static func fixture(scroll: Bool = false, scrollingSurface: Bool = false) -> Fixture {
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        w.isHidden = false
        let host = UIView(frame: w.bounds)
        let surface: UIView = scrollingSurface ? UIScrollView(frame: w.bounds) : UIView(frame: w.bounds)
        let wrapper: UIView = scroll ? UIScrollView(frame: w.bounds) : UIView(frame: w.bounds)
        for view in [surface, wrapper] {
            if let scroll = view as? UIScrollView {
                scroll.contentInsetAdjustmentBehavior = .never
                scroll.contentSize = CGSize(width: 2000, height: 4000)
            }
        }
        let source = UIView(frame: CGRect(x: 20, y: 30, width: 300, height: 80))
        w.addSubview(host); host.addSubview(surface); surface.addSubview(wrapper); wrapper.addSubview(source)
        return Fixture(window: w, host: host, surface: surface, wrapper: wrapper, source: source)
    }
    static func resolve(_ f: Fixture) -> NDAVisibleRegionResult {
        NDAVisibleRegionPlanner.resolve(f.source, through: f.surface, window: f.window)
    }
    static func accepted(_ f: Fixture, _ name: String) -> NDAVisibleRegion {
        let states = f.views.map { State($0) }
        let result = resolve(f)
        check(states.allSatisfy { $0.unchanged }, "resolve does not mutate: " + name)
        guard case .accepted(let plan) = result else { preconditionFailure("expected acceptance: " + name) }
        check(plan.isValid(surface: f.surface, window: f.window), "accepted checkpoint valid: " + name)
        return plan
    }
    @discardableResult
    static func rejected(_ f: Fixture, _ reason: NDAAncestorReason, _ view: UIView,
                         _ depth: Int, _ name: String) -> NDAAncestorFailure {
        let states = f.views.map { State($0) }
        guard case .rejected(let failure) = resolve(f) else { preconditionFailure("expected rejection: " + name) }
        check(failure.reason == reason && failure.view === view && failure.depth == depth,
              "reason/identity/depth: " + name)
        if reason == .clipping {
            check(failure.clipping != nil, "clipping carries operands: " + name)
            if let geometry = failure.clipping {
                check(geometry.sourceBounds == f.source.bounds && geometry.ancestorBounds == view.bounds &&
                      geometry.sourceInAncestor == f.source.convert(f.source.bounds, to: view),
                      "exact UIKit clipping operands: " + name)
            }
        } else { check(failure.clipping == nil, "nonclip has no geometry: " + name) }
        check(states.allSatisfy { $0.unchanged }, "rejection does not mutate: " + name)
        return failure
    }
    static func expect(_ plan: NDAVisibleRegion, source: CGRect, surface: CGRect,
                       clip: CGRect, _ name: String) {
        check(plan.sourceRect == source, "source-local crop: " + name)
        check(plan.surfaceRect == surface, "surface placement: " + name)
        check(plan.clipRect == clip, "common allowed viewport: " + name)
        check(plan.partial == (source != plan.sourceBounds), "partial flag: " + name)
    }
    static func observed() -> Fixture {
        let f = fixture(scroll: true)
        f.source.frame = CGRect(x: -183, y: 521, width: 370, height: 80)
        return f
    }
    static func addAnimation(_ view: UIView) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1; animation.toValue = 0.9; animation.duration = 100
        view.layer.add(animation, forKey: "native.regression")
    }
    static func main() {
        setbuf(stdout, nil)
        precondition(Thread.isMainThread)
        geometryCases()
        originAndScaleCases()
        rejectionCases()
        alignmentCases()
        checkpointCases()
        for key in counts.keys.sorted() { print("CATEGORY \(key): \(counts[key]!) checks") }
        print("VISIBLE REGION NATIVE PASS: \(checks) checks; real UIKit + production AncestorGate/VisibleRegion; no renderer/private-hook claim")
    }
}

extension VisibleRegionNativeTests {
    static func geometryCases() {
        category = "observed-and-edges"
        do {
            let f = observed(), p = accepted(f, "alpha6 observed")
            expect(p, source: CGRect(x: 183, y: 0, width: 187, height: 80),
                   surface: CGRect(x: 0, y: 521, width: 187, height: 80), clip: f.surface.bounds, "alpha6 observed")
            check(p.sourceBounds == CGRect(x: 0, y: 0, width: 370, height: 80), "unaltered source bounds")
            check(p.checkpoints.count == 3, "only surface/host/window checkpointed")
            check(NDAAncestorGate.failure(f.source, through: f.surface, window: f.window)?.reason == .clipping,
                  "unchanged alpha6 gate still rejects observed partial (negative control)")
            let q = p.inwardAligned(scale: 2, source: f.source, surface: f.surface)
            check(q?.sourceRect == p.sourceRect && q?.surfaceRect == p.surfaceRect, "observed exact crop survives 2x alignment")
        }
        let cases: [(String, CGRect, CGRect, CGRect)] = [
            ("full", CGRect(x: 20, y: 30, width: 100, height: 80), CGRect(x: 0, y: 0, width: 100, height: 80), CGRect(x: 50, y: 70, width: 100, height: 80)),
            ("left", CGRect(x: -10, y: 20, width: 100, height: 80), CGRect(x: 10, y: 0, width: 90, height: 80), CGRect(x: 30, y: 60, width: 90, height: 80)),
            ("top", CGRect(x: 20, y: -10, width: 100, height: 80), CGRect(x: 0, y: 10, width: 100, height: 70), CGRect(x: 50, y: 40, width: 100, height: 70)),
            ("right", CGRect(x: 150, y: 20, width: 100, height: 80), CGRect(x: 0, y: 0, width: 50, height: 80), CGRect(x: 180, y: 60, width: 50, height: 80)),
            ("bottom", CGRect(x: 20, y: 150, width: 100, height: 80), CGRect(x: 0, y: 0, width: 100, height: 50), CGRect(x: 50, y: 190, width: 100, height: 50)),
            ("all four edges", CGRect(x: -10, y: -20, width: 240, height: 260), CGRect(x: 10, y: 20, width: 200, height: 200), CGRect(x: 30, y: 40, width: 200, height: 200))
        ]
        for (name, frame, crop, mapped) in cases {
            let f = fixture()
            f.wrapper.frame = CGRect(x: 30, y: 40, width: 200, height: 200)
            f.wrapper.clipsToBounds = true; f.source.frame = frame
            expect(accepted(f, name), source: crop, surface: mapped,
                   clip: CGRect(x: 30, y: 40, width: 200, height: 200), name)
        }
        do {
            let f = observed()
            f.host.frame = CGRect(x: 0, y: 0, width: 120, height: 560)
            f.host.clipsToBounds = true
            let p = accepted(f, "second clip above partial")
            expect(p, source: CGRect(x: 183, y: 0, width: 120, height: 39),
                   surface: CGRect(x: 0, y: 521, width: 120, height: 39),
                   clip: CGRect(x: 0, y: 0, width: 120, height: 560), "second clip above partial")
        }
        do {
            let f = observed()
            let inner = UIView(frame: CGRect(x: -30, y: 500, width: 140, height: 80))
            inner.clipsToBounds = true; f.wrapper.addSubview(inner); inner.addSubview(f.source)
            f.source.frame = CGRect(x: -153, y: 21, width: 370, height: 80)
            expect(accepted(f, "nested clip below scroll"), source: CGRect(x: 183, y: 0, width: 110, height: 59),
                   surface: CGRect(x: 0, y: 521, width: 110, height: 59),
                   clip: CGRect(x: 0, y: 500, width: 110, height: 80), "nested clip below scroll")
        }
        do {
            let f = fixture(), p = accepted(f, "nonclipping source")
            check(p.clipRect == f.surface.bounds && p.clipRect != p.surfaceRect, "viewport is not source footprint")
            f.source.clipsToBounds = true
            let q = accepted(f, "source clips itself")
            check(q.clipRect == q.surfaceRect, "source bounds participate only when source clips")
        }
        do {
            let f = fixture()
            f.surface.frame = CGRect(x: -20, y: 10, width: 390, height: 844)
            f.source.frame = CGRect(x: 0, y: 30, width: 100, height: 80)
            expect(accepted(f, "window bounds always apply"), source: CGRect(x: 20, y: 0, width: 80, height: 80),
                   surface: CGRect(x: 20, y: 30, width: 80, height: 80),
                   clip: CGRect(x: 20, y: 0, width: 370, height: 834), "window bounds always apply")
        }
        do {
            let f = fixture()
            f.source.frame = CGRect(x: -10, y: 30, width: 100, height: 80)
            expect(accepted(f, "surface bounds always apply"), source: CGRect(x: 10, y: 0, width: 90, height: 80),
                   surface: CGRect(x: 0, y: 30, width: 90, height: 80), clip: f.surface.bounds,
                   "surface bounds always apply")
            f.source.frame.origin.x = -100
            rejected(f, .clipping, f.surface, 3, "empty surface intersection")
        }
    }

    static func originAndScaleCases() {
        category = "signed-origins-and-scale"
        for (origin, frame) in [
            (CGPoint(x: 40, y: 500), CGRect(x: 10, y: 520, width: 100, height: 80)),
            (CGPoint(x: -40, y: -80), CGRect(x: -70, y: -60, width: 100, height: 80))
        ] {
            let f = fixture(scroll: true)
            f.wrapper.frame = CGRect(x: 20, y: 30, width: 200, height: 200)
            f.wrapper.bounds.origin = origin; f.source.frame = frame
            f.source.bounds.origin = CGPoint(x: -12, y: 7)
            let name = "scroll \(origin) with signed source bounds"
            expect(accepted(f, name), source: CGRect(x: 18, y: 7, width: 70, height: 80),
                   surface: CGRect(x: 20, y: 50, width: 70, height: 80),
                   clip: CGRect(x: 20, y: 30, width: 200, height: 200), name)
        }
        for origin in [CGPoint(x: 50, y: 300), CGPoint(x: -50, y: -300)] {
            let f = fixture(scrollingSurface: true)
            f.surface.bounds.origin = origin
            f.source.removeFromSuperview(); f.surface.addSubview(f.source)
            f.source.frame = CGRect(x: origin.x - 30, y: origin.y + 20, width: 100, height: 80)
            let p = accepted(f, "signed scrolling surface \(origin)")
            expect(p, source: CGRect(x: 30, y: 0, width: 70, height: 80),
                   surface: CGRect(x: origin.x, y: origin.y + 20, width: 70, height: 80),
                   clip: f.surface.bounds, "surface offset not subtracted twice")
            let overlay = UIView(frame: f.surface.bounds); overlay.bounds = f.surface.bounds
            f.surface.addSubview(overlay)
            check(overlay.convert(p.surfaceRect, to: f.surface) == p.surfaceRect, "surface-origin overlay preserves placement")
        }
        do {
            let f = fixture()
            f.wrapper.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
            f.wrapper.layer.anchorPoint = .zero; f.wrapper.layer.position = CGPoint(x: 20, y: 30)
            f.wrapper.transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 0.5, tx: 7, ty: 9)
            f.wrapper.clipsToBounds = true
            f.source.frame = CGRect(x: -10, y: 20, width: 100, height: 80)
            let p = accepted(f, "positive scaled ancestor with anchor/translation")
            expect(p, source: CGRect(x: 10, y: 0, width: 90, height: 80),
                   surface: CGRect(x: 27, y: 49, width: 180, height: 40),
                   clip: CGRect(x: 27, y: 39, width: 363, height: 100), "positive scaled ancestor")
            check(p.inwardAligned(scale: 2, source: f.source, surface: f.surface)?.surfaceRect == p.surfaceRect,
                  "scaled ancestor maps inward crop without source mutation")
        }
        do {
            let f = fixture()
            f.wrapper.frame = CGRect(x: 30, y: 40, width: 200, height: 200); f.wrapper.clipsToBounds = true
            f.source.bounds = CGRect(x: -5, y: 7, width: 100, height: 80)
            f.source.layer.anchorPoint = .zero; f.source.layer.position = CGPoint(x: -20, y: 40)
            f.source.transform = CGAffineTransform(scaleX: 2, y: 0.5)
            expect(accepted(f, "positive scaled source with signed bounds"),
                   source: CGRect(x: 5, y: 7, width: 90, height: 80),
                   surface: CGRect(x: 30, y: 80, width: 180, height: 40),
                   clip: CGRect(x: 30, y: 40, width: 200, height: 200), "positive scaled source")
        }
    }
}

extension VisibleRegionNativeTests {
    static func rejectionCases() {
        category = "full-chain-rejections"
        let policies: [(String, NDAAncestorReason, (UIView) -> Void)] = [
            ("hidden", .hidden, { $0.isHidden = true }),
            ("alpha", .alpha, { $0.alpha = 0.98 }),
            ("rotation", .transform, { $0.layer.transform = CATransform3DMakeRotation(0.1, 0, 0, 1) }),
            ("initial geometry flip", .transform, { $0.layer.isGeometryFlipped = true }),
            ("sublayer", .sublayer, { $0.layer.sublayerTransform = CATransform3DMakeTranslation(1, 0, 0) }),
            ("mask", .mask, { $0.layer.mask = CALayer() }),
            ("animations", .animations, { addAnimation($0) })
        ]
        for (name, reason, mutate) in policies {
            for index in 0..<5 {
                let f = fixture(), view = f.views[index]
                mutate(view)
                rejected(f, reason, view, index + 1, name + " at depth \(index + 1)")
            }
            let f = observed()
            mutate(f.host)
            rejected(f, reason, f.host, 4, "partial then higher " + name)
        }
        do {
            let f = fixture()
            f.source.alpha = 0.995; f.wrapper.alpha = 0.995; f.surface.alpha = 0.995
            rejected(f, .alpha, f.surface, 3, "cumulative alpha below 0.99")
            let g = fixture(); g.wrapper.alpha = 0.995
            _ = accepted(g, "alpha above threshold")
        }
        let transforms: [(String, CATransform3D)] = [
            ("tiny exact b shear", CATransform3DMakeAffineTransform(CGAffineTransform(a: 1, b: 1e-12, c: 0, d: 1, tx: 0, ty: 0))),
            ("tiny exact c shear", CATransform3DMakeAffineTransform(CGAffineTransform(a: 1, b: 0, c: -1e-12, d: 1, tx: 0, ty: 0))),
            ("flip", CATransform3DMakeScale(-1, 1, 1)),
            ("zero scale", CATransform3DMakeScale(0, 1, 1)),
            ("3D", CATransform3DMakeRotation(0.2, 1, 0, 0))
        ]
        for (name, transform) in transforms {
            let f = fixture(); f.wrapper.layer.transform = transform
            rejected(f, .transform, f.wrapper, 2, name)
        }
        do {
            let f = fixture()
            var perspective = CATransform3DIdentity; perspective.m34 = 0.001
            f.wrapper.layer.transform = perspective
            rejected(f, .transform, f.wrapper, 2, "perspective")
        }
        for index in 2..<5 {
            let f = fixture(), view = f.views[index]
            view.layer.transform = CATransform3DMakeScale(0.9, 0.9, 1)
            rejected(f, .transform, view, index + 1, "surface/window chain cannot scale")
        }
        do {
            let f = fixture(); f.host.layer.transform = CATransform3DMakeTranslation(1, 0, 0)
            rejected(f, .transform, f.host, 4, "surface/window chain cannot translate via transform")
        }
        for index in 0..<5 {
            let f = observed(), view = f.views[index]
            view.clipsToBounds = true; view.layer.cornerRadius = 10
            rejected(f, .clipping, view, index + 1, "rounded clipping at depth \(index + 1)")
        }
        do {
            let f = observed()
            f.host.layer.masksToBounds = true; f.host.layer.cornerRadius = 5
            rejected(f, .clipping, f.host, 4, "partial then layer-only rounded clip")
        }
        do {
            let f = fixture(); f.wrapper.layer.cornerRadius = 12
            _ = accepted(f, "non-clipping rounded decoration is not a clip")
        }
        do {
            let f = observed(); f.host.clipsToBounds = true
            f.host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            rejected(f, .clipping, f.host, 4, "partial then later empty clip")
        }
        for frame in [CGRect(x: 390, y: 30, width: 80, height: 80),
                      CGRect(x: -80, y: 30, width: 80, height: 80),
                      CGRect(x: 30, y: 844, width: 80, height: 80)] {
            let f = fixture(); f.wrapper.clipsToBounds = true; f.source.frame = frame
            rejected(f, .clipping, f.wrapper, 2, "touching/empty clip \(frame)")
        }
        do {
            let f = fixture(); f.source.bounds.size.width = 0
            rejected(f, .clipping, f.source, 1, "zero source bounds")
            let g = fixture(); g.source.bounds.size.width = 2049
            rejected(g, .clipping, g.source, 1, "bounded source guard")
            let h = fixture(); h.wrapper.bounds.size.height = 0
            rejected(h, .clipping, h.wrapper, 2, "zero nonclip ancestor bounds")
        }
        do {
            let f = fixture(); f.wrapper.removeFromSuperview()
            rejected(f, .hierarchy, f.wrapper, 2, "detached source/surface")
        }
        do {
            let f = fixture(), absent = UIView(frame: f.window.bounds)
            f.window.addSubview(absent)
            let result = NDAVisibleRegionPlanner.resolve(f.source, through: absent, window: f.window)
            if case .rejected(let failure) = result {
                check(failure.reason == .hierarchy && failure.view === f.window && failure.depth == 5,
                      "same-window sibling is not an ancestor surface")
            } else { preconditionFailure("missing surface accepted") }
            let wrong = UIWindow(frame: f.window.bounds); wrong.isHidden = false
            if case .rejected(let failure) = NDAVisibleRegionPlanner.resolve(f.source, through: f.surface, window: wrong) {
                check(failure.reason == .hierarchy && failure.view === f.window && failure.depth == 5,
                      "specified window identity must match")
            } else { preconditionFailure("wrong window accepted") }
            f.surface.removeFromSuperview()
            rejected(f, .hierarchy, f.surface, 3, "detached surface")
        }
        for added in [59, 60, 64] {
            let f = fixture(); f.source.removeFromSuperview()
            var parent = f.wrapper
            var chain: [UIView] = []
            for _ in 0..<added {
                let child = UIView(frame: f.wrapper.bounds)
                parent.addSubview(child); chain.append(child); parent = child
            }
            parent.addSubview(f.source)
            if added == 59 { _ = accepted(f, "window is exactly node 64") }
            else {
                let failedView = added == 60 ? f.host : chain[added - 63]
                rejected(f, .depth, failedView, 64, "depth cap with \(added) extra nodes")
            }
        }
        invalidGeometryCases()
    }

    static func invalidGeometryCases() {
        category = "invalid-and-unrepresentable"
        for bad in [CGRect(x: 0, y: 0, width: -10, height: 80),
                    CGRect(x: 4_398_046_511_104, y: 0, width: 100, height: 80),
                    CGRect(x: CGFloat.nan, y: 0, width: 100, height: 80),
                    CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 80)] {
            let f = fixture()
            let source = ReportedBoundsView(frame: f.source.frame)
            f.source.removeFromSuperview(); f.wrapper.addSubview(source)
            source.reported = bad
            let result = NDAVisibleRegionPlanner.resolve(source, through: f.surface, window: f.window)
            guard case .rejected(let failure) = result else { preconditionFailure("invalid bounds accepted") }
            check(failure.reason == .clipping && failure.view === source && failure.depth == 1,
                  "invalid reported bounds fail closed: \(bad)")
            check(failure.clipping != nil, "invalid geometry still has exact diagnostic operands")
        }
        do {
            let f = fixture(); f.source.layer.position = CGPoint(x: 1e15, y: 40)
            rejected(f, .clipping, f.source, 1, "unbounded model position")
        }
        for (name, scale) in [("cumulative scale overflow", CGFloat(1e20)),
                              ("inverse scale overflow", CGFloat(1e-20))] {
            let f = fixture(); f.source.removeFromSuperview()
            var parent = f.wrapper
            var outermost: UIView?
            // Every local coefficient is finite even in float-backed runtimes;
            // only the full-chain product becomes unusable at node sixteen.
            for _ in 0..<15 {
                let node = UIView(frame: f.wrapper.bounds)
                node.layer.transform = CATransform3DMakeScale(scale, 1, 1)
                parent.addSubview(node); parent = node
                if outermost == nil { outermost = node }
            }
            parent.addSubview(f.source)
            f.source.layer.transform = CATransform3DMakeScale(scale, 1, 1)
            guard case .rejected(let failure) = resolve(f) else { preconditionFailure(name + " accepted") }
            check(failure.reason == .clipping && failure.view === outermost && failure.depth == 16,
                  name + " fails at exact checked product")
            check(failure.clipping != nil, name + " carries conversion operands (which may be nonfinite)")
        }
        do {
            let f = fixture()
            f.wrapper.layer.transform = CATransform3DMakeScale(1e-20, 1, 1)
            // The transform is locally positive, but adding its mapped width
            // to the parent's translation collapses both endpoint coordinates.
            guard case .rejected(let failure) = resolve(f) else { preconditionFailure("collapsed conversion accepted") }
            check(failure.reason == .clipping, "unrepresentable converted extent fails closed")
        }
    }

    static func alignmentCases() {
        category = "inward-pixel-grid"
        do {
            let f = observed(); f.source.bounds.origin = CGPoint(x: -12.125, y: 7.375)
            let p = accepted(f, "fractional source-origin grid")
            guard let q = p.inwardAligned(scale: 2, source: f.source, surface: f.surface) else {
                preconditionFailure("origin-relative alignment missing")
            }
            check(q.sourceRect == CGRect(x: 170.875, y: 7.375, width: 187, height: 80),
                  "grid is relative to source bounds, not absolute coordinates")
            check(q.surfaceRect == CGRect(x: 0, y: 521, width: 187, height: 80), "fractional origin never double-offsets")
        }
        do {
            let f = observed(); f.source.bounds.origin.x = -10.1
            let p = accepted(f, "decimal origin integer grid extent")
            guard let q = p.inwardAligned(scale: 2, source: f.source, surface: f.surface) else {
                preconditionFailure("decimal bounds origin must not erase a representable crop")
            }
            check(q.sourceRect.width == 187 && q.sourceRect.height == 80 &&
                  q.sourceRect.width * 2 == 374 && q.sourceRect.height * 2 == 160,
                  "decimal-origin crop uses integer grid differences, not cancelling absolute endpoints")
            check(q.clipRect.contains(q.surfaceRect) && f.source.bounds.contains(q.sourceRect),
                  "decimal-origin extent correction never expands outside visibility")
        }
        do {
            let f = fixture(scroll: true)
            f.source.frame = CGRect(x: -183.25, y: 521.125, width: 370.375, height: 80.375)
            f.source.bounds.origin = CGPoint(x: -12.125, y: 7.375)
            let p = accepted(f, "fractional partial edges")
            let states = f.views.map { State($0) }
            guard let q = p.inwardAligned(scale: 2, source: f.source, surface: f.surface) else {
                preconditionFailure("fractional crop missing")
            }
            expect(q, source: CGRect(x: 171.375, y: 7.375, width: 186.5, height: 80),
                   surface: CGRect(x: 0.25, y: 521.125, width: 186.5, height: 80), clip: p.clipRect,
                   "fractional edges round inward")
            check(p.sourceRect.contains(q.sourceRect) && f.source.bounds.contains(q.sourceRect), "aligned source subset without tolerance")
            check(p.surfaceRect.contains(q.surfaceRect) && p.clipRect.contains(q.surfaceRect), "aligned surface subset without tolerance")
            check(q.checkpoints.count == p.checkpoints.count && q.isValid(surface: f.surface, window: f.window),
                  "alignment preserves surviving checkpoint chain")
            check(q.inwardAligned(scale: 2, source: f.source, surface: f.surface)?.sourceRect == q.sourceRect,
                  "binary-grid alignment is idempotent")
            check(states.allSatisfy { $0.unchanged }, "alignment has no UIKit mutations")
        }
        for scale in [CGFloat(0.5), 1, 2, 4] {
            let f = fixture()
            f.wrapper.clipsToBounds = true
            f.source.frame = CGRect(x: -10.25, y: -3.125, width: 100.375, height: 80.375)
            f.source.bounds.origin = CGPoint(x: -4.125, y: -9.375)
            let p = accepted(f, "alignment scale \(scale)")
            guard let q = p.inwardAligned(scale: scale, source: f.source, surface: f.surface) else {
                preconditionFailure("inward alignment unavailable at \(scale)")
            }
            check(p.sourceRect.contains(q.sourceRect) && f.source.bounds.contains(q.sourceRect), "source crop never grows at \(scale)")
            check(p.surfaceRect.contains(q.surfaceRect) && q.clipRect.contains(q.surfaceRect), "mapped crop never grows at \(scale)")
            check(q.sourceRect.width * scale > 1 && q.sourceRect.height * scale > 1, "positive multi-pixel crop at \(scale)")
            check(q.sourceRect.width * scale == (q.sourceRect.width * scale).rounded(.down) &&
                  q.sourceRect.height * scale == (q.sourceRect.height * scale).rounded(.down),
                  "successful alignment has exactly integral renderer extents at \(scale)")
            check(f.source.convert(q.sourceRect.origin, to: f.surface) == q.surfaceRect.origin,
                  "actual UIKit source-crop placement at \(scale)")
        }
        do {
            let f = fixture()
            f.wrapper.clipsToBounds = true
            f.source.frame = CGRect(x: -10.25, y: -3.125, width: 100.375, height: 80.375)
            f.source.bounds.origin = CGPoint(x: -4.125, y: -9.375)
            let p = accepted(f, "non-binary grid division")
            if let q = p.inwardAligned(scale: 1.5, source: f.source, surface: f.surface) {
                check(q.sourceRect.width * 1.5 == (q.sourceRect.width * 1.5).rounded(.down) &&
                      q.sourceRect.height * 1.5 == (q.sourceRect.height * 1.5).rounded(.down) &&
                      p.sourceRect.contains(q.sourceRect) && p.clipRect.contains(q.surfaceRect),
                      "non-binary grid accepted only when actual pixel extents remain integral and contained")
            } else {
                check(true, "non-binary represented grid fails closed without outward epsilon")
            }
        }
        for size in [CGSize(width: 300, height: 2), CGSize(width: 2, height: 300)] {
            let f = fixture(); f.source.frame = CGRect(origin: .zero, size: size)
            let p = accepted(f, "renderer dimension ceiling \(size)")
            check(p.inwardAligned(scale: 16, source: f.source, surface: f.surface) == nil,
                  "reject renderer pixel dimension above 4096")
        }
        do {
            let f = fixture(); f.source.frame = f.surface.bounds
            let p = accepted(f, "renderer pixel budget")
            check(p.inwardAligned(scale: 1, source: f.source, surface: f.surface) == nil,
                  "reject renderer bitmap above 220000 pixels")
            check(p.inwardAligned(scale: 0.5, source: f.source, surface: f.surface) != nil,
                  "smaller binary capture scale meets strict bitmap budget")
        }
        do {
            let f = fixture(), p = accepted(f, "invalid scale inputs")
            for scale in [CGFloat(0), -1, .nan, .infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude] {
                check(p.inwardAligned(scale: scale, source: f.source, surface: f.surface) == nil,
                      "reject invalid/overflow scale \(scale)")
            }
            f.source.frame.origin.x += 1
            check(p.inwardAligned(scale: 2, source: f.source, surface: f.surface) == nil, "source movement before alignment rejected")
        }
        do {
            let f = fixture(), p = accepted(f, "source policy recheck")
            f.source.layer.mask = CALayer()
            check(p.inwardAligned(scale: 2, source: f.source, surface: f.surface) == nil, "source mask introduced before alignment rejected")
        }
        do {
            let f = fixture(); f.source.frame = CGRect(x: -99.75, y: 30, width: 100, height: 80)
            let p = accepted(f, "subpixel visible sliver")
            check(p.inwardAligned(scale: 2, source: f.source, surface: f.surface) == nil, "at most one pixel cannot be captured")
        }
    }
}

final class ReportedBoundsView: UIView {
    var reported: CGRect?
    override var bounds: CGRect {
        get { reported ?? super.bounds }
        set { super.bounds = newValue }
    }
}

extension VisibleRegionNativeTests {
    static func checkpointCases() {
        category = "commit-lifetime-checkpoints"
        let changes: [(String, (UIView) -> Void)] = [
            ("bounds origin", { $0.bounds.origin.x += 1 }),
            ("bounds size", { $0.bounds.size.width += 1 }),
            ("position", { $0.layer.position.x += 1 }),
            ("anchor", { $0.layer.anchorPoint.x += 0.125 }),
            ("anchor Z", { $0.layer.anchorPointZ += 1 }),
            ("Z position", { $0.layer.zPosition += 1 }),
            ("transform", { $0.layer.transform = CATransform3DMakeTranslation(1, 0, 0) }),
            ("sublayer transform", { $0.layer.sublayerTransform = CATransform3DMakeTranslation(1, 0, 0) }),
            ("alpha", { $0.alpha = 0.999 }),
            ("hidden", { $0.isHidden = true }),
            ("clip flag", { $0.clipsToBounds.toggle() }),
            ("layer clip flag", { $0.layer.masksToBounds.toggle() }),
            ("corner radius", { $0.layer.cornerRadius = 1 }),
            ("masked corners", { $0.layer.maskedCorners = [] }),
            ("corner curve", { $0.layer.cornerCurve = $0.layer.cornerCurve == .continuous ? .circular : .continuous }),
            ("geometry flipped", { $0.layer.isGeometryFlipped.toggle() }),
            ("mask", { $0.layer.mask = CALayer() }),
            ("animation", { addAnimation($0) })
        ]
        for (name, mutate) in changes {
            for index in 2..<5 {
                let f = fixture(), p = accepted(f, "checkpoint baseline " + name)
                let view = f.views[index]
                mutate(view)
                check(!p.isValid(surface: f.surface, window: f.window), "checkpoint detects \(name) at depth \(index + 1)")
                check(!p.isCaptureValid(source: f.source, surface: f.surface, window: f.window),
                      "capture checkpoint detects \(name) at depth \(index + 1)")
            }
        }
        do {
            let f = observed(), p = accepted(f, "after removal")
            check(p.isCaptureValid(source: f.source, surface: f.surface, window: f.window), "attached complete-chain snapshot valid")
            f.source.removeFromSuperview()
            check(p.isValid(surface: f.surface, window: f.window), "source removal does not invalidate lifetime viewport")
            check(!p.isCaptureValid(source: f.source, surface: f.surface, window: f.window), "capture validity requires attached original source")
            f.wrapper.removeFromSuperview()
            f.source.isHidden = true; f.source.layer.mask = CALayer()
            check(p.isValid(surface: f.surface, window: f.window), "removed source/wrapper policies are not lifetime predicates")
        }
        for removeHost in [false, true] {
            let f = fixture(), p = accepted(f, "surface-chain removal")
            if removeHost { f.host.removeFromSuperview() } else { f.surface.removeFromSuperview() }
            check(!p.isValid(surface: f.surface, window: f.window), "surface/host removal invalidates checkpoints")
        }
        do {
            let f = fixture(), p = accepted(f, "same-window reparent")
            let twin = UIView(frame: f.host.frame); f.window.addSubview(twin); twin.addSubview(f.surface)
            check(!p.isValid(surface: f.surface, window: f.window), "same geometry with different surface parent is invalid")
            let fresh = accepted(f, "same-window reparent fresh plan")
            check(fresh.sourceRect == p.sourceRect && fresh.surfaceRect == p.surfaceRect && fresh.clipRect == p.clipRect,
                  "numerical equality cannot substitute for parent identity checks")
        }
        do {
            let f = fixture(), p = accepted(f, "wrong surface/window identity")
            let other = UIView(frame: f.surface.frame); f.host.addSubview(other)
            check(!p.isValid(surface: other, window: f.window), "same-sized sibling surface is not original surface")
            let window = UIWindow(frame: f.window.frame); window.isHidden = false
            check(!p.isValid(surface: f.surface, window: window), "window identity is fixed")
            window.isHidden = true
        }
        category = "capture-full-chain-identity"
        for (name, mutate) in changes {
            for index in 0..<2 {
                let f = fixture(), p = accepted(f, "capture baseline " + name)
                mutate(f.views[index])
                check(!p.isCaptureValid(source: f.source, surface: f.surface, window: f.window),
                      "pre/post capture detects below-surface \(name) at depth \(index + 1)")
                check(p.isValid(surface: f.surface, window: f.window), "below-surface changes do not retain commit dependencies")
            }
        }
        do {
            let f = fixture(), p = accepted(f, "below-surface same-geometry reparent")
            guard let aligned = p.inwardAligned(scale: 2, source: f.source, surface: f.surface) else {
                preconditionFailure("capture alignment missing")
            }
            let twin = UIView(frame: f.wrapper.frame); f.surface.addSubview(twin); twin.addSubview(f.source)
            let fresh = accepted(f, "reparent numeric negative control")
            check(fresh.sourceRect == p.sourceRect && fresh.surfaceRect == p.surfaceRect && fresh.clipRect == p.clipRect,
                  "below-surface reparent can preserve every numeric crop operand")
            check(!p.isCaptureValid(source: f.source, surface: f.surface, window: f.window), "weak capture identity catches equal-geometry reparent")
            check(!aligned.isCaptureValid(source: f.source, surface: f.surface, window: f.window), "aligned plan copies full capture checkpoints")
            check(p.isValid(surface: f.surface, window: f.window), "equal-geometry source reparent leaves surviving viewport valid")
        }
        do {
            var plan: NDAVisibleRegion?
            weak var source: UIView?
            weak var wrapper: UIView?
            weak var surface: UIView?
            autoreleasepool {
                let f = observed()
                plan = accepted(f, "weak checkpoint ownership")
                source = f.source; wrapper = f.wrapper; surface = f.surface
                f.source.removeFromSuperview(); f.wrapper.removeFromSuperview(); f.surface.removeFromSuperview()
                f.window.isHidden = true
            }
            check(plan != nil && source == nil && wrapper == nil && surface == nil,
                  "plans/checkpoints retain neither removed notification nor surviving UIView objects")
        }
    }
}
