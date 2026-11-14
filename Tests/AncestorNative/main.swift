import UIKit
import QuartzCore
import CoreFoundation
import Darwin

@main
struct AncestorNativeTests {
    static var tests = 0
    static var category = "legacy.gate"
    static var categoryCounts: [String: Int] = [:]
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), "FAIL: " + name)
        tests += 1
        categoryCounts[category, default: 0] += 1
        print("PASS: " + name)
    }
    static func fixture() -> (UIWindow, UIView, UIView, UIView) {
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        w.isHidden = false
        let surface = UIView(frame: w.bounds)
        let wrapper = UIView(frame: surface.bounds)
        let source = UIView(frame: CGRect(x: 20, y: 30, width: 300, height: 80))
        w.addSubview(surface); surface.addSubview(wrapper); wrapper.addSubview(source)
        return (w, surface, wrapper, source)
    }
    static func main() {
        setbuf(stdout, nil)
        precondition(Thread.isMainThread)
        check(NDAAncestorReason.allCases.count == 9, "all nine production reasons")
        for reason in NDAAncestorReason.allCases {
            let (w, surface, wrapper, source) = fixture()
            var expectedDepth = 2
            switch reason {
            case .hidden: wrapper.isHidden = true
            case .alpha: wrapper.alpha = 0.98
            case .transform: wrapper.layer.transform = CATransform3DMakeRotation(0.1, 0, 0, 1)
            case .sublayer: wrapper.layer.sublayerTransform = CATransform3DMakeTranslation(1, 0, 0)
            case .mask: wrapper.layer.mask = CALayer()
            case .animations:
                let a = CABasicAnimation(keyPath: "opacity"); a.duration = 100
                wrapper.layer.add(a, forKey: "test")
            case .clipping: wrapper.clipsToBounds = true; source.frame.origin.x = -2
            case .depth:
                // More than 64 ancestors before surface/window.
                source.removeFromSuperview()
                var parent = surface
                for _ in 0..<64 {
                    let v = UIView(frame: surface.bounds); parent.addSubview(v); parent = v
                }
                parent.addSubview(source)
                expectedDepth = 64
            case .hierarchy: wrapper.removeFromSuperview()
            }
            let f = NDAAncestorGate.failure(source, through: surface, window: w)
            check(f?.reason == reason && f?.depth == expectedDepth, "production reason " + reason.rawValue)
            compareAlpha5(f, source: source, surface: surface, window: w, name: reason.rawValue)
            if reason == .clipping {
                checkClippingOperands(f!, source: source, view: wrapper, depth: expectedDepth, name: "baseline clip")
            } else {
                check(f?.clipping == nil, "nonclip has no operands: " + reason.rawValue)
            }
            NDARecordAncestorFailure(reason.event, f!.view, f!.depth, f!.effectiveAlpha)
        }
        do {
            let (w, surface, wrapper, source) = fixture()
            check(NDAAncestorGate.failure(source, through: surface, window: w) == nil, "identity success")
            wrapper.transform = CGAffineTransform(a: 0.9, b: 0, c: 0, d: 0.8, tx: 5, ty: 6)
            check(NDAAncestorGate.failure(source, through: surface, window: w) == nil, "positive scale translation success")
            wrapper.clipsToBounds = true
            check(NDAAncestorGate.failure(source, through: surface, window: w) == nil, "fully contained clip success")
            wrapper.transform = .identity
            wrapper.alpha = 0.995; source.alpha = 0.995; surface.alpha = 0.995
            check(NDAAncestorGate.failure(source, through: surface, window: w)?.reason == .alpha, "cumulative alpha failure")
        }
        for t in [CATransform3DMakeScale(-1, 1, 1), CATransform3DMakeRotation(0.2, 1, 0, 0)] {
            check(!NDAAncestorGate.supportedTransform(t), "flip or perspective rejected")
        }
        do {
            let (w, _, wrapper, source) = fixture()
            let other = UIView()
            check(NDAAncestorGate.failure(source, through: other, window: w)?.reason == .hierarchy, "surface absent at window")
            check(NDAAncestorGate.failure(source, through: wrapper, window: UIWindow())?.reason == .hierarchy, "wrong window")
        }
        do {
            let (w, surface, wrapper, source) = fixture()
            wrapper.isHidden = true; wrapper.alpha = 0.1; wrapper.layer.mask = CALayer()
            check(NDAAncestorGate.failure(source, through: surface, window: w)?.reason == .hidden, "first failure priority")
        }
        runGeometryCases()
        category = "legacy.writer"
        // Exercise the actual production persistence writer, not a copied formatter.
        let privateView = SensitiveView(frame: CGRect(x: 0, y: 0, width: 9000, height: 8000))
        privateView.accessibilityLabel = "PRIVATE-NOTIFICATION-TEXT"
        NDARecordAncestorFailure("ancestor.mask", privateView, 999, .infinity)
        NDARecordEvent("arbitrary.PRIVATE-NOTIFICATION-TEXT")
        NDARecordAncestorFailure("invalid", privateView, 2, 1)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
        let domain = "com.tsangbaby.noticedeleteanimation" as CFString
        let summary = CFPreferencesCopyAppValue("DiagnosticsSummary" as CFString, domain) as? String ?? ""
        check(summary.contains("NoticeDeleteAnimation alpha7"), "production version label")
        check(summary.contains("class=non-system depth=64 alpha_permille=-1"), "class privacy and numeric bounds")
        check(summary.contains("width=4096 height=4096"), "geometry clamped")
        check(!summary.contains("PRIVATE") && !summary.contains("SensitiveView") && !summary.contains("invalid"), "no arbitrary metadata or content")
        check(summary.components(separatedBy: "Last ancestor:").count == 2 && summary.count < 6000, "one bounded last record")
        check(NDAAncestorReason.allCases.allSatisfy { summary.contains($0.event + ":") }, "all production reason counters persisted")
        NDARecordAncestorFailure("ancestor.hidden", UIView(), -99, 10)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
        let systemSummary = CFPreferencesCopyAppValue("DiagnosticsSummary" as CFString, domain) as? String ?? ""
        check(systemSummary.contains("class=UIView depth=1 alpha_permille=1000"), "system class and lower depth clamp")
        runGeometryWriterCases()
        runPreparedWriterCases()
        for key in categoryCounts.keys.sorted() {
            print("CATEGORY \(key): \(categoryCounts[key]!) checks")
        }
        print("ANCESTOR NATIVE PASS: \(tests) checks; production UIKit gate + production writer")
    }
}
final class SensitiveView: UIView {
    override var description: String { "PRIVATE-OBJECT-DESCRIPTION" }
}

// All decisions and formatted diagnostics below come from the real production APIs.
// The alpha5 gate is compiled separately by the native harness, not reimplemented here.
extension AncestorNativeTests {
    struct GeometryFixture {
        let window: UIWindow
        let surface: UIView
        let ancestor: UIView
        let source: UIView
    }
    struct ViewState {
        let view: UIView
        let bounds: CGRect
        let center: CGPoint
        let transform: CATransform3D
        let sublayerTransform: CATransform3D
        let alpha: CGFloat
        let hidden: Bool
        let clips: Bool
        let parent: UIView?
        let mask: CALayer?
        let animationKeys: [String]
        init(_ view: UIView) {
            self.view = view; bounds = view.bounds; center = view.center
            transform = view.layer.transform; sublayerTransform = view.layer.sublayerTransform
            alpha = view.alpha; hidden = view.isHidden; clips = view.clipsToBounds
            parent = view.superview; mask = view.layer.mask
            animationKeys = (view.layer.animationKeys() ?? []).sorted()
        }
        var unchanged: Bool {
            view.bounds == bounds && view.center == center &&
                CATransform3DEqualToTransform(view.layer.transform, transform) &&
                CATransform3DEqualToTransform(view.layer.sublayerTransform, sublayerTransform) &&
                view.alpha == alpha && view.isHidden == hidden && view.clipsToBounds == clips &&
                view.superview === parent && view.layer.mask === mask &&
                (view.layer.animationKeys() ?? []).sorted() == animationKeys
        }
    }
    static func geometryFixture(ancestor: UIView, sourceFrame: CGRect,
                                source: UIView = UIView()) -> GeometryFixture {
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        w.isHidden = false
        let surface = UIView(frame: w.bounds)
        w.addSubview(surface); surface.addSubview(ancestor)
        source.frame = sourceFrame; ancestor.addSubview(source)
        ancestor.clipsToBounds = true
        return GeometryFixture(window: w, surface: surface, ancestor: ancestor, source: source)
    }
    static func scrollFixture(origin: CGPoint, sourceFrame: CGRect,
                              source: UIView = UIView()) -> GeometryFixture {
        let scroll = UIScrollView(frame: CGRect(x: 20, y: 30, width: 200, height: 200))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 2000, height: 4000)
        let f = geometryFixture(ancestor: scroll, sourceFrame: sourceFrame, source: source)
        scroll.bounds.origin = origin
        return f
    }
    static func compareAlpha5(_ actual: NDAAncestorFailure?, source: UIView, surface: UIView,
                              window: UIWindow, name: String) {
        let baseline = NDAAlpha5AncestorGate.failure(source, through: surface, window: window)
        let previous = category; category = "geometry.alpha5-differential"
        check((actual == nil) == (baseline == nil) &&
              actual?.reason.rawValue == baseline?.reason.rawValue && actual?.depth == baseline?.depth,
              "alpha5/alpha6 nil/reason/depth: " + name)
        category = previous
    }
    static func checkClippingOperands(_ failure: NDAAncestorFailure, source: UIView,
                                      view: UIView, depth: Int, name: String) {
        check(failure.reason == .clipping && failure.view === view && failure.depth == depth,
              "actual failed ancestor/reason/depth: " + name)
        check(failure.clipping != nil, "immutable clipping payload exists: " + name)
        guard let geometry = failure.clipping else { return }
        check(geometry.sourceBounds == source.bounds && geometry.ancestorBounds == view.bounds &&
              geometry.sourceInAncestor == source.convert(source.bounds, to: view),
              "saved operands equal actual UIKit operands: " + name)
        check(!geometry.ancestorBounds.insetBy(dx: -0.5, dy: -0.5).contains(geometry.sourceInAncestor),
              "actual saved half-point predicate rejects: " + name)
    }
    @discardableResult
    static func evaluate(_ f: GeometryFixture, name: String, fails: Bool = false,
                         failedView: UIView? = nil, depth: Int = 2) -> NDAAncestorFailure? {
        let views = [f.source, f.ancestor, f.surface, f.window] + (failedView.map { [$0] } ?? [])
        let states = views.map { ViewState($0) }
        let result = NDAAncestorGate.failure(f.source, through: f.surface, window: f.window)
        compareAlpha5(result, source: f.source, surface: f.surface, window: f.window, name: name)
        if fails {
            check(result != nil, "production rejects: " + name)
            if let result = result {
                checkClippingOperands(result, source: f.source, view: failedView ?? f.ancestor,
                                      depth: depth, name: name)
            }
        } else {
            check(result == nil, "production accepts: " + name)
        }
        check(states.allSatisfy { $0.unchanged }, "gate does not mutate UIKit: " + name)
        return result
    }
    static func flushedSummary() -> String {
        // Production coalesces writes after 0.5s; service the main runloop, never sleep.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
        return CFPreferencesCopyAppValue("DiagnosticsSummary" as CFString,
                                        "com.tsangbaby.noticedeleteanimation" as CFString) as? String ?? ""
    }
    static func write(_ failure: NDAAncestorFailure, source: UIView) {
        guard let g = failure.clipping else { preconditionFailure("expected production clip payload") }
        NDARecordClippingFailure(source, failure.view, failure.depth, failure.effectiveAlpha,
                                 g.sourceBounds, g.sourceInAncestor, g.ancestorBounds)
    }
    static func line(_ summary: String, _ expected: String) -> Bool {
        summary.components(separatedBy: "\n").contains(expected)
    }
    static func checkSingleGeometry(_ summary: String, _ name: String) {
        check(summary.components(separatedBy: "Last ancestor:").count == 2 &&
              summary.components(separatedBy: "Clip geometry:").count == 2 &&
              summary.count < 6000, "one bounded latest ancestor/geometry: " + name)
        for field in ["source_bounds=", "ancestor_bounds=", "source_in_ancestor=",
                      "local_intersection=", "edge_overflow_ltrb="] {
            check(summary.components(separatedBy: field).count == 2, "one field " + field + name)
        }
    }
}

extension AncestorNativeTests {
    static func runGeometryCases() {
        category = "geometry.scroll-and-transform"
        let positive = scrollFixture(origin: CGPoint(x: 40, y: 500),
                                     sourceFrame: CGRect(x: 60, y: 520, width: 100, height: 80))
        check(positive.ancestor.bounds.origin == CGPoint(x: 40, y: 500), "real positive scroll bounds origin")
        evaluate(positive, name: "positive scroll content offset fully visible")
        let negative = scrollFixture(origin: CGPoint(x: -40, y: -80),
                                     sourceFrame: CGRect(x: -30, y: -70, width: 100, height: 80))
        check(negative.ancestor.bounds.origin == CGPoint(x: -40, y: -80), "real negative scroll bounds origin")
        evaluate(negative, name: "negative scroll bounds origin fully visible")
        // Intentional WRONG comparator, used only as a negative control, never as an oracle.
        category = "geometry.zero-origin-negative-control"
        for f in [positive, negative] {
            let actual = f.source.convert(f.source.bounds, to: f.ancestor)
            let wrong = CGRect(origin: .zero, size: f.ancestor.bounds.size)
            check(f.ancestor.bounds.insetBy(dx: -0.5, dy: -0.5).contains(actual) &&
                  !wrong.insetBy(dx: -0.5, dy: -0.5).contains(actual),
                  "discarding bounds.origin would falsely reject visible scroll source")
        }
        category = "geometry.scroll-and-transform"
        positive.source.bounds.origin = CGPoint(x: 17, y: -23)
        check(positive.source.bounds.origin == CGPoint(x: 17, y: -23), "nonzero source bounds fixture")
        evaluate(positive, name: "source bounds origin preserved through scroll conversion")
        positive.source.transform = CGAffineTransform(a: 0.75, b: 0, c: 0, d: 0.5, tx: 4, ty: 6)
        positive.ancestor.transform = CGAffineTransform(a: 0.9, b: 0, c: 0, d: 0.8, tx: 5, ty: 6)
        evaluate(positive, name: "positive scales/translations on source and scrolling ancestor")
        let outer = scrollFixture(origin: CGPoint(x: 20, y: 300),
                                  sourceFrame: CGRect(x: 30, y: 310, width: 160, height: 160))
        outer.source.removeFromSuperview()
        let inner = UIScrollView(frame: CGRect(x: 30, y: 310, width: 160, height: 160))
        inner.contentInsetAdjustmentBehavior = .never
        inner.contentSize = CGSize(width: 1000, height: 2000)
        outer.ancestor.addSubview(inner); inner.bounds.origin = CGPoint(x: -20, y: 100)
        outer.source.frame = CGRect(x: -10, y: 110, width: 80, height: 60)
        inner.addSubview(outer.source)
        let nested = GeometryFixture(window: outer.window, surface: outer.surface,
                                     ancestor: inner, source: outer.source)
        evaluate(nested, name: "nested positive and negative scroll offsets")

        category = "geometry.edges-and-source-size"
        let edges: [(String, CGRect)] = [
            ("left", CGRect(x: -20, y: 50, width: 80, height: 80)),
            ("right", CGRect(x: 150, y: 50, width: 80, height: 80)),
            ("top", CGRect(x: 50, y: -20, width: 80, height: 80)),
            ("bottom", CGRect(x: 50, y: 150, width: 80, height: 80)),
            ("fully outside", CGRect(x: 230, y: 250, width: 80, height: 80))]
        for (name, frame) in edges {
            let f = scrollFixture(origin: .zero, sourceFrame: frame)
            evaluate(f, name: name + " actual scroll clipping", fails: true)
        }
        let oversized = scrollFixture(origin: .zero,
                                       sourceFrame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let largeWrapper = UIView(frame: CGRect(x: -300, y: -300, width: 1000, height: 1000))
        oversized.ancestor.addSubview(largeWrapper)
        oversized.source.removeFromSuperview(); largeWrapper.addSubview(oversized.source)
        oversized.source.frame = CGRect(x: 320, y: 320, width: 80, height: 60)
        evaluate(oversized, name: "oversized intermediate wrapper but actual child visible")
        oversized.source.frame = CGRect(x: 0, y: 0, width: 500, height: 500)
        let tinyChild = UIView(frame: CGRect(x: 330, y: 330, width: 10, height: 10))
        oversized.source.addSubview(tinyChild)
        evaluate(oversized, name: "oversized source rejected despite small visible child", fails: true, depth: 3)

        category = "geometry.half-point-boundary"
        for (edge, frame) in [
            ("left", CGRect(x: -0.5, y: 20, width: 100, height: 100)),
            ("top", CGRect(x: 20, y: -0.5, width: 100, height: 100)),
            ("right", CGRect(x: 100.5, y: 20, width: 100, height: 100)),
            ("bottom", CGRect(x: 20, y: 100.5, width: 100, height: 100))] {
            let f = scrollFixture(origin: .zero, sourceFrame: frame)
            evaluate(f, name: "exact .5 accepted at " + edge)
            var outside = frame
            // Binary-exact >.5 distance avoids float/rounding ambiguity in UIKit.
            switch edge {
            case "left": outside.origin.x -= 0.03125
            case "top": outside.origin.y -= 0.03125
            case "right": outside.origin.x += 0.03125
            default: outside.origin.y += 0.03125
            }
            f.source.frame = outside
            evaluate(f, name: "greater than .5 rejected at " + edge, fails: true)
        }
        category = "geometry.screen-depth"
        let screen = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let deep = geometryFixture(ancestor: screen, sourceFrame: CGRect(x: 20, y: 20, width: 80, height: 80))
        deep.source.removeFromSuperview()
        var parent = screen
        for _ in 0..<8 {
            let wrapper = UIView(frame: screen.bounds); parent.addSubview(wrapper); parent = wrapper
        }
        parent.addSubview(deep.source)
        evaluate(deep, name: "390x844 clipping ancestor at depth10 contained")
        deep.source.frame.origin.y = 820
        evaluate(deep, name: "390x844 clipping ancestor at depth10 bottom failure", fails: true, depth: 10)
    }
}

extension AncestorNativeTests {
    static func runGeometryWriterCases() {
        category = "writer.saved-signed-geometry"
        let source = SensitiveView()
        source.accessibilityLabel = "PRIVATE-NOTIFICATION-TEXT"
        source.accessibilityValue = "PRIVATE-NOTIFICATION-VALUE"
        let half = scrollFixture(origin: CGPoint(x: -40, y: 500),
                                 sourceFrame: CGRect(x: -90, y: 520, width: 100, height: 80), source: source)
        source.bounds.origin = CGPoint(x: 7, y: -9)
        guard let failure = evaluate(half, name: "writer real half-overlap failure", fails: true),
              let saved = failure.clipping else { preconditionFailure("missing half failure") }
        let states = [source, half.ancestor, half.surface, half.window].map { ViewState($0) }
        write(failure, source: source)
        check(states.allSatisfy { $0.unchanged }, "clipping writer leaves actual views unchanged")
        // Deliberately change live geometry AFTER capture; writer must use the saved operands.
        source.bounds.origin = CGPoint(x: 111, y: 222)
        half.ancestor.bounds.origin = CGPoint(x: 20, y: 200)
        check(saved.sourceBounds != source.bounds && saved.ancestorBounds != half.ancestor.bounds,
              "saved geometry is immutable after live bounds changes")
        let changedStates = [source, half.ancestor].map { ViewState($0) }
        write(failure, source: source)
        check(changedStates.allSatisfy { $0.unchanged }, "writer does not restore or otherwise mutate changed views")
        var summary = flushedSummary()
        check(line(summary, "Clip geometry: source_class=non-system valid=1 clamped=0 contains_half_pt=0 local_overlap_permille=500"),
              "actual half overlap and private source class")
        for expected in ["source_bounds=(7.00,-9.00,100.00,80.00)",
                         "ancestor_bounds=(-40.00,500.00,200.00,200.00)",
                         "source_in_ancestor=(-90.00,520.00,100.00,80.00)",
                         "local_intersection=(-40.00,520.00,50.00,80.00)",
                         "edge_overflow_ltrb=(50.00,0.00,0.00,0.00)"] {
            check(line(summary, expected), "saved real signed operands: " + expected)
        }
        check(!summary.contains("PRIVATE") && !summary.contains("SensitiveView"), "clip record never exposes user content/class/description")
        checkSingleGeometry(summary, "signed half")

        category = "writer.local-overlap"
        let quarter = scrollFixture(origin: CGPoint(x: -40, y: 500),
                                    sourceFrame: CGRect(x: -90, y: 460, width: 100, height: 80))
        // A second clipping ancestor reduces global visibility further. The record must
        // still describe ONLY the first failed ancestor (the scroll view) and its 25%.
        quarter.surface.clipsToBounds = true
        quarter.surface.bounds.size.width = 50
        guard let q = evaluate(quarter, name: "quarter local overlap not global visibility", fails: true) else {
            preconditionFailure("missing quarter failure")
        }
        write(q, source: quarter.source)
        summary = flushedSummary()
        check(line(summary, "Clip geometry: source_class=UIView valid=1 clamped=0 contains_half_pt=0 local_overlap_permille=250"),
              "quarter overlap is local to first failed ancestor")
        check(line(summary, "local_intersection=(-40.00,500.00,50.00,40.00)") &&
              line(summary, "edge_overflow_ltrb=(50.00,40.00,0.00,0.00)"), "quarter intersection and LTRB edge order")
        check(!line(summary, "source_bounds=(7.00,-9.00,100.00,80.00)"), "new clipping record replaces prior geometry")
        checkSingleGeometry(summary, "quarter replacement")
        let outside = scrollFixture(origin: CGPoint(x: -40, y: 500),
                                    sourceFrame: CGRect(x: 300, y: 900, width: 100, height: 80))
        guard let o = evaluate(outside, name: "writer actual disjoint source", fails: true) else {
            preconditionFailure("missing disjoint failure")
        }
        write(o, source: outside.source)
        summary = flushedSummary()
        check(summary.contains("contains_half_pt=0 local_overlap_permille=0") &&
              line(summary, "local_intersection=empty"), "disjoint is empty, not invalid, with zero overlap")
        check(line(summary, "edge_overflow_ltrb=(0.00,0.00,240.00,280.00)"), "disjoint positive right/bottom overflow")
        checkSingleGeometry(summary, "disjoint")

        category = "writer.rounding-and-bounds"
        let systemSource = UIView(), systemAncestor = UIView()
        // Formatter-only adversarial inputs go directly to the actual production writer.
        // Unrounded +.501 is rejected even though the output rounds to +.50.
        NDARecordClippingFailure(systemSource, systemAncestor, 2, 1,
            CGRect(x: -1.234, y: 2.345, width: 100, height: 100),
            CGRect(x: -0.501, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 100))
        summary = flushedSummary()
        check(summary.contains("valid=1 clamped=0 contains_half_pt=0 local_overlap_permille=995"),
              "contains flag and overlap use unrounded finite operands")
        check(line(summary, "source_bounds=(-1.23,2.35,100.00,100.00)") &&
              line(summary, "source_in_ancestor=(-0.50,0.00,100.00,100.00)") &&
              line(summary, "edge_overflow_ltrb=(0.50,0.00,0.00,0.00)"), "signed fixed two-decimal rounding")
        NDARecordClippingFailure(systemSource, systemAncestor, 2, 1,
            CGRect(x: -1_000_000_000, y: 1_000_000_000, width: 100, height: 100),
            CGRect(x: -1_000_000_000, y: 1_000_000_000, width: 100, height: 100),
            CGRect(x: -1_000_000_000, y: 1_000_000_000, width: 50, height: 100))
        summary = flushedSummary()
        check(summary.contains("valid=1 clamped=1 contains_half_pt=0 local_overlap_permille=500"),
              "clamp flags and ratio are computed before formatting huge coordinates")
        check(line(summary, "source_bounds=(-32768.00,32768.00,100.00,100.00)") &&
              line(summary, "ancestor_bounds=(-32768.00,32768.00,50.00,100.00)"), "signed huge operands limited to plus/minus32768")
        checkSingleGeometry(summary, "huge")
        NDARecordClippingFailure(systemSource, systemAncestor, 2, 1,
            CGRect(x: CGFloat.infinity, y: CGFloat.nan, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 50, height: 100))
        summary = flushedSummary()
        check(summary.contains("valid=0 clamped=0 contains_half_pt=-1 local_overlap_permille=-1"), "nonfinite geometry flags are invalid sentinels")
        check(line(summary, "source_bounds=(invalid,invalid,100.00,100.00)") &&
              line(summary, "local_intersection=invalid") && line(summary, "edge_overflow_ltrb=invalid"), "nonfinite components cannot leak raw nan/infinity")
        checkSingleGeometry(summary, "nonfinite")
        runExtremeAndClearWriterCases(systemSource, systemAncestor)
    }
}

extension AncestorNativeTests {
    static func runExtremeAndClearWriterCases(_ source: UIView, _ ancestor: UIView) {
        category = "writer.extreme-axis-ratios"
        let states = [source, ancestor].map { ViewState($0) }
        // Normal extents whose AREA underflows. Rounded coordinates all become 0.00;
        // neither validity, containment nor overlap may be inferred from that display.
        NDARecordClippingFailure(source, ancestor, 2, 1,
            CGRect(x: 0, y: 0, width: 1e-200, height: 1e-200),
            CGRect(x: 0, y: 0, width: 1e-200, height: 1e-200),
            CGRect(x: 0, y: 0, width: 0.2e-200, height: 1e-200))
        var summary = flushedSummary()
        check(summary.contains("valid=1 clamped=0 contains_half_pt=1 local_overlap_permille=200"),
              "normal tiny extents preserve 200 permille despite area underflow")
        check(line(summary, "source_bounds=(0.00,0.00,0.00,0.00)") &&
              line(summary, "local_intersection=(0.00,0.00,0.00,0.00)"),
              "rounded zero geometry does not imply invalid or empty")
        NDARecordClippingFailure(source, ancestor, 2, 1,
            CGRect(x: 0, y: 0, width: 1e200, height: 1e200),
            CGRect(x: 0, y: 0, width: 1e200, height: 1e200),
            CGRect(x: 0, y: 0, width: 0.2e200, height: 1e200))
        summary = flushedSummary()
        check(summary.contains("valid=1 clamped=1 contains_half_pt=0 local_overlap_permille=200"),
              "normal huge extents preserve 200 permille despite area overflow")
        check(line(summary, "source_in_ancestor=(0.00,0.00,32768.00,32768.00)"),
              "huge finite sizes bounded without invalidating ratio")
        check(states.allSatisfy { $0.unchanged }, "adversarial writer calls do not mutate views")
        category = "writer.replacement-and-clear"
        checkSingleGeometry(summary, "most recent extreme record")
        NDARecordAncestorFailure("ancestor.hidden", ancestor, 2, 1)
        summary = flushedSummary()
        check(summary.contains("Last ancestor: ancestor.hidden") &&
              !summary.contains("Clip geometry:") && !summary.contains("source_bounds=") &&
              !summary.contains("local_intersection=") && !summary.contains("edge_overflow_ltrb="),
              "later nonclip replacement clears all clipping geometry")
        NDARecordClippingFailure(source, ancestor, 2, 1,
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: -50, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 100))
        NDARecordAncestorFailure("ancestor.clipping", ancestor, 2, 1)
        summary = flushedSummary()
        check(summary.contains("Last ancestor: ancestor.clipping") && !summary.contains("Clip geometry:"),
              "legacy ancestor writer clears geometry even for clipping reason")
        check(summary.components(separatedBy: "Last ancestor:").count == 2 && summary.count < 6000,
              "clear keeps one bounded most-recent ancestor record")
    }
}

extension AncestorNativeTests {
    static func runPreparedWriterCases() {
        category = "writer.prepared-region"
        let source = SensitiveView()
        source.accessibilityLabel = "PRIVATE-NOTIFICATION-TEXT"
        NDARecordRegionPrepared(source, CGRect(x: 183, y: 0, width: 187, height: 80),
            CGRect(x: 0, y: 521, width: 187, height: 80),
            CGRect(x: 0, y: 0, width: 390, height: 844), true)
        var summary = flushedSummary()
        check(summary.contains("Prepared region: source_class=non-system partial=1 valid=1 clamped=0"), "bounded private prepared crop header")
        check(line(summary, "source_crop=(183.00,0.00,187.00,80.00)") &&
              line(summary, "surface_crop=(0.00,521.00,187.00,80.00)") &&
              line(summary, "safe_clip=(0.00,0.00,390.00,844.00)"), "prepared crop is not a restored card")
        check(!summary.contains("PRIVATE") && !summary.contains("SensitiveView") &&
              !summary.contains("Last ancestor:") && !summary.contains("Clip geometry:"), "prepared record clears stale failure without content")
        check(summary.components(separatedBy: "Prepared region:").count == 2 && summary.count < 6000,
              "exactly one bounded prepared record")
        NDARecordRegionPrepared(UIView(), CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 5, y: 6, width: 10, height: 10), CGRect(x: 0, y: 0, width: 40, height: 40), false)
        summary = flushedSummary()
        check(summary.contains("source_class=UIView partial=0 valid=1") && summary.contains("capture.full:"),
              "full-source event is fixed allowlist only")
        NDARecordAncestorFailure("ancestor.mask", UIView(), 3, 1)
        summary = flushedSummary()
        check(summary.contains("Last ancestor: ancestor.mask") && !summary.contains("Prepared region:"),
              "new rejection clears stale prepared metadata")
    }
}
