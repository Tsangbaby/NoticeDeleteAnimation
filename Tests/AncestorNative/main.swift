import UIKit
import QuartzCore
import CoreFoundation

@main
struct AncestorNativeTests {
    static var tests = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), "FAIL: " + name)
        tests += 1
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
        // Exercise the actual production persistence writer, not a copied formatter.
        let privateView = SensitiveView(frame: CGRect(x: 0, y: 0, width: 9000, height: 8000))
        privateView.accessibilityLabel = "PRIVATE-NOTIFICATION-TEXT"
        NDARecordAncestorFailure("ancestor.mask", privateView, 999, .infinity)
        NDARecordEvent("arbitrary.PRIVATE-NOTIFICATION-TEXT")
        NDARecordAncestorFailure("invalid", privateView, 2, 1)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
        let domain = "com.tsangbaby.noticedeleteanimation" as CFString
        let summary = CFPreferencesCopyAppValue("DiagnosticsSummary" as CFString, domain) as? String ?? ""
        check(summary.contains("NoticeDeleteAnimation alpha5"), "production version label")
        check(summary.contains("class=non-system depth=64 alpha_permille=-1"), "class privacy and numeric bounds")
        check(summary.contains("width=4096 height=4096"), "geometry clamped")
        check(!summary.contains("PRIVATE") && !summary.contains("SensitiveView") && !summary.contains("invalid"), "no arbitrary metadata or content")
        check(summary.components(separatedBy: "Last ancestor:").count == 2 && summary.count < 6000, "one bounded last record")
        check(NDAAncestorReason.allCases.allSatisfy { summary.contains($0.event + ":") }, "all production reason counters persisted")
        NDARecordAncestorFailure("ancestor.hidden", UIView(), -99, 10)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
        let systemSummary = CFPreferencesCopyAppValue("DiagnosticsSummary" as CFString, domain) as? String ?? ""
        check(systemSummary.contains("class=UIView depth=1 alpha_permille=1000"), "system class and lower depth clamp")
        print("ANCESTOR NATIVE PASS: \(tests) checks; production UIKit gate + production writer")
    }
}
final class SensitiveView: UIView {
    override var description: String { "PRIVATE-OBJECT-DESCRIPTION" }
}
