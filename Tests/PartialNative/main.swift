import UIKit
import QuartzCore
import CoreFoundation
import Darwin

// Real production Animator/Entry/bridge; synthetic notification classes,
// main-bundle identity adapter and runtime IMP shim in this unique test host.
// NOT Substrate or private SpringBoard/device coverage.
enum PartialNative {
    static var checks = 0
    static var attempts = 0
    static var prepared: [NDAEffectHandle] = []
    static var tiles: [UUID: [CALayer]] = [:]
    static var finishes: [Bool] = []
    static let keys = ["Enabled", "DiagnosticsSummary", "DiagnosticsUpdated", "DiagnosticsPID"]
    static var saved: [CFPropertyList?] = []
    static let domain = NDASettings.domain as CFString

    static func restore() {
        for (key, value) in zip(keys, saved) { CFPreferencesSetAppValue(key as CFString, value, domain) }
        CFPreferencesAppSynchronize(domain)
        NDATestUseSpringBoardIdentity(false)
    }
    static func check(_ ok: @autoclosure () -> Bool, _ name: String) {
        guard ok() else { print("FAIL partial-native: \(name)"); restore(); exit(1) }
        checks += 1; print("PASS: \(name)")
    }
    static func enabled(_ value: Bool) {
        CFPreferencesSetAppValue("Enabled" as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, domain)
        check(CFPreferencesAppSynchronize(domain), "real CFPreferences synchronize")
        check(NDASettings.enabled == value, "production Entry reads actual Enabled=\(value)")
    }
    static func observe() {
        check(NDAInstallHooks({ source, surface in
            attempts += 1
            let h = NDAAnimator.shared.prepare(source: source, surface: surface)
            print("PARTIAL PREPARE: accepted=\(h != nil) bounds=\(source.bounds) frame=\(source.frame) scene=\(source.window?.windowScene?.activationState.rawValue ?? -999)")
            if h == nil, let w = source.window {
                if case .rejected(let f) = NDAVisibleRegionPlanner.resolve(source, through: surface, window: w) {
                    print("PARTIAL REJECT: \(f.reason.rawValue) depth=\(f.depth)")
                }
            }
            if let h = h { prepared.append(h); tiles[h.lease.id] = h.container.layer.sublayers ?? [] }
            return h
        }, { object, committed in
            guard let h = object as? NDAEffectHandle else { fatalError("nonproduction handle") }
            finishes.append(committed); NDAAnimator.shared.finish(h, committed: committed)
        }), "production installer accepts test bundle and real synthetic ABIs")
        check(NDATestHookCount() == 4, "installer idempotent: four IMP replacements only")
    }
    static func reset() {
        NDAAnimator.shared.cancelAll()
        attempts = 0; prepared = []; tiles = [:]; finishes = []
    }
    static func fresh() -> NDATestFixture {
        reset()
        let f = NDATestMakeFixture()
        NDATestSettle(f) // bootstrap/retry may install; wrap AFTER settling.
        observe()      // no runloop pumping between this and hook assertions.
        check(!f.window.isHidden, "visible real UIKit fixture (scene presence supplied by runtime)")
        return f
    }
    @discardableResult
    static func invoke(_ f: NDATestFixture, three: Bool = true, nested: Bool = false,
                       action: NDATestAction = .removeCell, animated: Bool = true,
                       displaced: Bool = true) -> Bool {
        NDATestInvoke(f, three, nested, action, animated, displaced, 29)
    }
    static func trace(_ f: NDATestFixture, three: Bool = true, nested: Bool = false,
                      animated: Bool, displaced: Bool = true) {
        let t = NDATestReadTrace(f)
        check(t.top == 1 && t.group == 1 && t.identities, "top/group originals once, identical request")
        check(t.three == (three ? 1 : 0) && t.two == (!three || nested ? 1 : 0), "each selected list original exactly once")
        check(t.getters == (nested ? 2 : 1) && t.getterIndex == 29, "real getter ABI preserves index")
        if three { check(t.index3 == 29 && t.animated3 == animated && t.displaced == displaced, "3-arg original exact index/animated/displaced") }
        if !three || nested { check(t.index2 == 29 && t.animated2 == animated, "2-arg original exact index/animated") }
    }
    static func handle() -> NDAEffectHandle {
        check(prepared.count == 1 && attempts == 1 && finishes == [true], "one real prepare and one successful-return finish")
        return prepared[0]
    }
    static func destroyed(_ h: NDAEffectHandle) {
        let retained = tiles[h.lease.id] ?? []
        check(!retained.isEmpty && retained.allSatisfy { $0.contents == nil && ($0.animationKeys() ?? []).isEmpty }, "every retained tile releases pixels and animations")
        check((h.container.layer.sublayers ?? []).isEmpty && h.container.superview == nil, "overlay and tile sublayers removed")
    }
    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        zip([a.minX, a.minY, a.width, a.height], [b.minX, b.minY, b.width, b.height]).allSatisfy { abs($0 - $1) < 0.00001 }
    }
    struct State {
        let view: UIView, bounds: CGRect, center: CGPoint, alpha: CGFloat, hidden: Bool
        let transform: CATransform3D
        init(_ v: UIView) { view = v; bounds = v.bounds; center = v.center; alpha = v.alpha; hidden = v.isHidden; transform = v.layer.transform }
        var unchanged: Bool { view.bounds == bounds && view.center == center && view.alpha == alpha && view.isHidden == hidden && CATransform3DEqualToTransform(view.layer.transform, transform) && (view.layer.animationKeys() ?? []).isEmpty }
    }
    static func geometry(_ f: NDATestFixture, _ h: NDAEffectHandle) {
        check(h.sourceFrame == CGRect(x: 0, y: 521, width: 187, height: 80), "observed -183/370 source becomes x0/187, never shifted full card")
        check(h.region.sourceBounds == CGRect(x: 0, y: 0, width: 370, height: 80) && h.region.sourceRect == CGRect(x: 183, y: 0, width: 187, height: 80) && h.region.partial, "real planner retains exact source-local partial crop")
        check(h.container.frame == h.region.clipRect && h.container.bounds == h.region.clipRect && h.container.clipsToBounds, "fixed overlay frame=bounds=common clipRect")
        let ts = tiles[h.lease.id]!
        check(ts.count == h.plan.particles.count && ts.count == h.lease.tileCount && ts.count <= NDAAnimator.shared.policy.maxTilesPerEffect, "real particle count and lease tile budget")
        let scale = ts[0].contentsScale
        check(NDATestBackingSize(ts[0]) == CGSize(width: 187 * scale, height: 80 * scale), "actual CGImage backing is crop187x80 times capture scale")
        check(h.lease.pixelCount == (Int(187 * scale) + 2) * (Int(80 * scale) + 2), "lease charges cropped backing plus rounding, not full370 card")
        check(NDATestNoHiddenRed(ts[0]), "actual cropped tile backing contains green, no hidden red/blank pixels")
        check(ts.allSatisfy { let uv = $0.contentsRect; return uv.minX >= 0 && uv.minY >= 0 && uv.maxX <= 1 && uv.maxY <= 1 && uv.width > 0 && uv.height > 0 }, "all texture UVs bounded within cropped image 0...1")
        check(zip(ts, h.plan.particles).allSatisfy { tile, particle in
            let r = particle.rect, f = h.sourceFrame
            let expected = CGRect(x: f.minX + CGFloat(r.x) * f.width, y: f.minY + CGFloat(r.y) * f.height,
                                  width: CGFloat(r.width) * f.width, height: CGFloat(r.height) * f.height)
            return near(tile.frame, expected) && tile.contentsRect == CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
        }, "each real particle has exact crop-relative frame and UV mapping")
        check(near(ts.reduce(CGRect.null) { $0.union($1.frame) }, h.sourceFrame), "tile frame union equals real cropped sourceFrame")
        check(h.committed && h.container.superview === f.list && !h.container.isHidden, "removed source commits visible overlay on original surface")
        check(ts.allSatisfy { $0.animation(forKey: "NDA.dissolve") is CAAnimationGroup }, "real Animator commits particle animation groups")
        check(!h.container.isUserInteractionEnabled && h.container.accessibilityElementsHidden && h.container.hitTest(.zero, with: nil) == nil, "overlay remains noninteractive and accessibility-hidden")
    }
}

extension PartialNative {
    static func contracts() {
        for (three, nested, action) in [(true, false, NDATestAction.removeSource), (false, false, .removeCell), (true, true, .removeCell)] {
            let f = fresh(), states = [State(f.source!), State(f.cell)]
            check(!invoke(f, three: three, nested: nested, action: action), "normal original returns")
            trace(f, three: three, nested: nested, animated: false)
            geometry(f, handle())
            check(states.allSatisfy { $0.unchanged }, "production never writes system cell/source geometry, alpha, hidden, transform or animations")
            let h = prepared[0]; NDAAnimator.shared.cancelAll(); destroyed(h)
            NDAAnimator.shared.finish(h, committed: true); destroyed(h)
            trace(f, three: three, nested: nested, animated: false)
        }
        do {
            let f = fresh()
            f.source!.bounds.origin.x = -10.1
            NDATestSettle(f); observe()
            check(!invoke(f), "decimal-origin production planner/capture/commit")
            trace(f, animated: false)
            let h = handle(), ts = tiles[h.lease.id]!
            check(h.committed && h.region.sourceRect.width == 187 && h.region.sourceRect.height == 80,
                  "decimal origin retains exact visible187x80 region")
            check(NDATestBackingSize(ts[0]) == CGSize(width: 374, height: 160),
                  "decimal-origin actual backing374x160")
            check(NDATestNoHiddenRed(ts[0]), "decimal-origin actual crop has no hidden-side red")
            NDAAnimator.shared.cancelAll(); destroyed(h)
        }
        for action: NDATestAction in [.keepAttached, .reparentSource, .surfaceBounds, .ancestorBounds, .reparentSurface] {
            let f = fresh()
            check(!invoke(f, action: action), "commit rejection original returned once")
            trace(f, animated: false)
            let h = handle()
            check(!h.committed, "attached/reparented source or changed surviving chain rejects commit")
            destroyed(h) // Suppression is never 'repaired' by replaying the original.
            trace(f, animated: false)
        }
        do {
            let f = fresh()
            check(invoke(f, nested: true, action: .throwOriginal), "ObjC helper contains original exception")
            trace(f, nested: true, animated: false)
            check(NDATestReadTrace(f).didThrow && attempts == 1 && finishes == [false] && prepared.count == 1, "exception invokes outer finish(false) once despite nested overload")
            destroyed(prepared[0])
            reset(); observe()
            check(!invoke(f), "same request retries after exception")
            trace(f, animated: false)
            check(handle().committed, "request scopes and seenViews unwind after exception")
        }
    }
    static func rejection() {
        let cases: [(String, (NDATestFixture) -> Void)] = [
            ("disabled", { _ in enabled(false) }),
            ("hidden window", { $0.window.isHidden = true }),
            ("privacy alpha", { $0.host.alpha = 0.98 }),
            ("ancestor mask", { $0.host.layer.mask = CALayer() }),
            ("draw geometry", { NDATestMutateDuringDraw($0) }),
            ("draw cancel", { NDATestOnDraw($0) { NDAAnimator.shared.cancelAll() } })
        ]
        for (name, mutate) in cases {
            for (three, animated) in [(true, true), (false, true), (true, false)] {
                let f = fresh(); mutate(f)
                let nested = name == "disabled" && three
                check(!invoke(f, three: three, nested: nested, animated: animated, displaced: false), "reject: \(name)")
                trace(f, three: three, nested: nested, animated: animated, displaced: false)
                check(attempts == 1 && prepared.isEmpty && finishes.isEmpty, "nil prepare: native flags, no finish")
                if name.hasPrefix("draw") { check(f.draws > 0, "real draw callback executed") }
                enabled(true)
            }
        }
        let f = fresh(); NDATestMismatchRequest(f)
        check(!invoke(f, nested: true), "mismatched request")
        trace(f, nested: true, animated: true)
        check(attempts == 0 && finishes.isEmpty, "identity/seenViews reject before prepare")
        let g = fresh(); NDATestUnscoped(g, 43, false, true)
        let t = NDATestReadTrace(g)
        check(t.top == 0 && t.group == 0 && t.three == 1 && t.index3 == 43 && !t.animated3 && t.displaced && t.getters == 0 && attempts == 0, "unscoped native false/displaced/index")
    }
    static func lifecycle() {
        // Settle all fixtures BEFORE any lease: no boot/retry callback can replace
        // our observers, and no snapshot is intentionally aged before admission.
        reset()
        let fs = (0..<3).map { _ -> NDATestFixture in let f = NDATestMakeFixture(); NDATestSettle(f); return f }
        observe()
        for f in fs { check(!invoke(f), "capacity original still returns") }
        check(prepared.count == 2 && attempts == 3 && finishes == [true, true], "real singleton capacity rejects third capture")
        trace(fs[2], animated: true)
        let active = prepared
        NDAAnimator.shared.cancelAll(); active.forEach { destroyed($0) }
        reset(); observe(); fs[2].list.addSubview(fs[2].cell)
        check(!invoke(fs[2]), "same source can reuse admission after cancel")
        trace(fs[2], animated: false); check(handle().committed, "cancel releases actual bitmap/tile/concurrent budgets")

        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIApplication.didReceiveMemoryWarningNotification, UIAccessibility.reduceMotionStatusDidChangeNotification,
                     UIWindow.didBecomeHiddenNotification] {
            let f = fresh(); check(!invoke(f), "lifecycle setup original")
            let h = handle(); check(h.committed, "lifecycle setup committed")
            NotificationCenter.default.post(name: name, object: f.window)
            destroyed(h); trace(f, animated: false)
        }
        do {
            let f = fresh(); check(!invoke(f), "lifetime checkpoint setup")
            let h = handle(); f.host.bounds.origin.x += 1
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            destroyed(h); trace(f, animated: false)
        }
        do {
            var f: NDATestFixture!; weak var source: UIView?
            autoreleasepool {
                f = fresh(); source = f.source
                check(!invoke(f, action: .removeSource), "weak-source setup")
                check(handle().committed, "weak-source committed")
                NDATestForgetSource(f)
            }
            check(source == nil && prepared[0].source == nil, "active handle/checkpoints do not retain removed source")
            let h = prepared[0]
            RunLoop.main.run(until: Date().addingTimeInterval(h.plan.totalDuration + 0.25))
            destroyed(h); trace(f, animated: false)
        }
    }
    static func run() {
        saved = keys.map { CFPreferencesCopyAppValue($0 as CFString, domain) }
        check(Thread.isMainThread && Bundle.main.bundleIdentifier == "com.tsangbaby.noticedeleteanimation.partial-native-tests", "unique real UIKit test-host identity")
        check(!NDAInstallHooks({ _, _ in nil }, { _, _ in }), "production process guard rejects ordinary test host before identity adapter")
        NDATestUseSpringBoardIdentity(true)
        check(Bundle.main.bundleIdentifier == "com.apple.springboard", "explicit main-bundle identity adapter active only in test process")
        NDASwiftStart()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(!UIAccessibility.isReduceMotionEnabled, "explicit real Reduce Motion prerequisite OFF (not mocked)")
        enabled(true)
        contracts(); rejection(); lifecycle()
        reset()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let summary = CFPreferencesCopyAppValue("DiagnosticsSummary" as CFString, domain) as? String ?? ""
        let pid = CFPreferencesCopyAppValue("DiagnosticsPID" as CFString, domain) as? NSNumber
        check(pid?.int32Value == getpid(), "real production diagnostics flushed in this process")
        for event in ["bootstrap", "install.ready", "capture.partial", "commit.shown", "commit.source_attached", "commit.surface", "commit.failed", "capture.bitmap", "capture.capacity"] {
            check(summary.contains("\n\(event): "), "real production event observed: \(event)")
        }
        restore()
        print("PARTIAL NATIVE PASS: \(checks) checks; actual production Core/Animator/Entry/ObjC bridge+capture+diagnostics, real UIKit; synthetic classes + runtime IMP and process-identity adapters, NOT actual Substrate/private SpringBoard/device integration")
        exit(0)
    }
}

@objc(NDAPartialTestDelegate)
final class PartialDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window!.rootViewController = UIViewController(); window!.makeKeyAndVisible()
        // Run from a runloop timer, not inside a GCD main-queue block: nested
        // settling must service the real bootstrap/diagnostics dispatches too.
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in PartialNative.run() }
        return true
    }
}
@main
struct PartialMain {
    static func main() {
        setbuf(stdout, nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            fputs("FAIL partial-native: runtime watchdog\n", stderr); _Exit(1)
        }
        _ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(PartialDelegate.self))
    }
}
