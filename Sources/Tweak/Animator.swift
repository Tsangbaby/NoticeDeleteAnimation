import UIKit
import QuartzCore

/// Noninteractive, scene-local content. Never creates a global window and never
/// writes alpha/transform/hidden to a system-owned notification cell.
final class NDAEffectSurface: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

final class NDAEffectHandle: NSObject {
    let lease: NDAEffectLease
    let container: NDAEffectSurface
    weak var surface: UIView?
    weak var source: UIView?
    weak var window: UIWindow?
    let surfaceBounds: CGRect
    let sourceFrame: CGRect
    let plan: NDAParticlePlan
    var committed = false
    var deadline: CFTimeInterval

    init(lease: NDAEffectLease, container: NDAEffectSurface, surface: UIView,
         frame: CGRect, plan: NDAParticlePlan) {
        self.lease = lease
        self.container = container
        self.surface = surface
        self.window = surface.window
        self.surfaceBounds = surface.bounds
        self.sourceFrame = frame
        self.plan = plan
        self.deadline = CACurrentMediaTime() + 0.12
    }
}

/// Main-thread-only owner. Bitmap content is never persisted or logged.
final class NDAAnimator {
    static let shared = NDAAnimator()
    let policy = NDAEffectPolicy()
    private var admission = NDAAdmissionController()
    private var handles: [UUID: NDAEffectHandle] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var seed: UInt64 = 0

    private init() {
        let names: [Notification.Name] = [UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIApplication.didReceiveMemoryWarningNotification,
            UIWindow.didBecomeHiddenNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name,
                object: nil, queue: .main) { [weak self] _ in self?.cancelAll() })
        }
    }

    func prepare(source: UIView, surface: UIView) -> NDAEffectHandle? {
        guard Thread.isMainThread else { return nil }
        NDARecordEvent("capture.enter")
        guard NDASettings.enabled else { NDARecordEvent("capture.disabled"); return nil }
        guard !UIAccessibility.isReduceMotionEnabled else { NDARecordEvent("capture.reduce_motion"); return nil }
        guard !source.isHidden, source.alpha > 0.01,
              let window = source.window, surface.window === window, !window.isHidden else {
            NDARecordEvent("capture.window"); return nil
        }
        guard hostVisible(window) else { NDARecordEvent("capture.scene"); return nil }
        guard source.bounds.width > 1, source.bounds.height > 1,
              source.bounds.width.isFinite, source.bounds.height.isFinite,
              source.bounds.width <= 2048, source.bounds.height <= 2048 else {
            NDARecordEvent("capture.geometry"); return nil
        }
        guard visibleSource(source, through: surface, window: window) else {
            NDARecordEvent("capture.ancestors"); return nil
        }
        sweep()
        guard handles.count < policy.maxConcurrent else { NDARecordEvent("capture.capacity"); return nil }
        let frame = source.convert(source.bounds, to: surface)
        guard frame.width.isFinite, frame.height.isFinite,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width > 1, frame.height > 1,
              surface.bounds.intersects(frame),
              surface.bounds.insetBy(dx: -1, dy: -1).contains(frame) else {
            NDARecordEvent("capture.geometry"); return nil
        }
        seed &+= 1
        guard let plan = NDAParticlePlan.make(width: Double(frame.width),
            height: Double(frame.height), seed: seed, policy: policy) else { NDARecordEvent("capture.plan"); return nil }
        // Capture at <=2x and <=220k pixels per effect. Reject before allocation if
        // accounting is already full. UIGraphics may ceil each bitmap dimension.
        let desiredScale = min(window.screen.scale, 2,
            sqrt(220_000 / (source.bounds.width * source.bounds.height)))
        guard desiredScale.isFinite, desiredScale > 0 else { NDARecordEvent("capture.bitmap"); return nil }
        let width = Int(ceil(source.bounds.width * desiredScale))
        let height = Int(ceil(source.bounds.height * desiredScale))
        let result = admission.admit(NDAAdmissionRequest(token: UUID(),
            tileCount: plan.particles.count, bitmapWidth: width + 2,
            bitmapHeight: height + 2), at: CACurrentMediaTime())
        for lease in result.expiredLeases { destroy(lease.id) }
        guard case .accepted(let lease) = result.decision else { NDARecordEvent("capture.capacity"); return nil }
        guard let image = NDACaptureView(source, desiredScale), let cgImage = image.cgImage,
              cgImage.width <= width + 2, cgImage.height <= height + 2 else {
            admission.release(lease)
            NDARecordEvent("capture.bitmap")
            return nil
        }
        let container = NDAEffectSurface(frame: surface.bounds)
        // UIScrollView bounds may have a nonzero contentOffset. Preserve that
        // coordinate origin rather than adding the offset a second time.
        container.bounds = surface.bounds
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear
        container.clipsToBounds = true
        container.accessibilityElementsHidden = true
        container.isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for particle in plan.particles {
            let r = particle.rect
            let tile = CALayer()
            tile.frame = CGRect(x: frame.minX + CGFloat(r.x) * frame.width,
                y: frame.minY + CGFloat(r.y) * frame.height,
                width: CGFloat(r.width) * frame.width,
                height: CGFloat(r.height) * frame.height)
            tile.contents = cgImage
            tile.contentsScale = image.scale
            tile.contentsRect = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            tile.contentsGravity = .resize
            tile.magnificationFilter = .linear
            tile.minificationFilter = .linear
            container.layer.addSublayer(tile)
        }
        CATransaction.commit()
        let handle = NDAEffectHandle(lease: lease, container: container,
                                     surface: surface, frame: frame, plan: plan)
        handle.source = source
        handles[lease.id] = handle
        startTimer()
        NDARecordEvent("capture.prepared")
        return handle
    }

    func finish(_ handle: NDAEffectHandle, committed: Bool) {
        guard Thread.isMainThread, handles[handle.lease.id] === handle else { return }
        guard committed, !handle.committed else {
            NDARecordEvent("commit.failed"); destroy(handle.lease.id); return
        }
        guard let surface = handle.surface else {
            NDARecordEvent("commit.surface"); destroy(handle.lease.id); return
        }
        // A synchronous return alone is not a successful visual removal.
        guard handle.source?.isDescendant(of: surface) != true else {
            NDARecordEvent("commit.source_attached"); destroy(handle.lease.id); return
        }
        guard surface.window === handle.window, validSurface(handle) else {
            NDARecordEvent("commit.surface"); destroy(handle.lease.id); return
        }
        handle.committed = true
        handle.deadline = CACurrentMediaTime() + handle.plan.totalDuration + 0.10
        surface.addSubview(handle.container)
        handle.container.isHidden = false
        NDARecordEvent("commit.shown")
        let baseTime = handle.container.layer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (tile, particle) in zip(handle.container.layer.sublayers ?? [], handle.plan.particles) {
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(cgPoint: tile.position)
            position.toValue = NSValue(cgPoint: CGPoint(
                x: tile.position.x + CGFloat(particle.dx) * handle.sourceFrame.width,
                y: tile.position.y + CGFloat(particle.dy) * handle.sourceFrame.height))
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = particle.rotation
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = particle.scaleEnd
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.keyTimes = particle.opacityKeyframes.map { NSNumber(value: $0.time) }
            opacity.values = particle.opacityKeyframes.map { NSNumber(value: $0.opacity) }
            let group = CAAnimationGroup()
            let animations: [CAAnimation] = [position, rotation, scale, opacity]
            for animation in animations { animation.duration = particle.duration }
            group.animations = animations
            group.beginTime = baseTime + particle.delay
            group.duration = particle.duration
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            tile.add(group, forKey: "NDA.dissolve")
        }
        CATransaction.commit()
    }

    /// Fail closed exactly as before; diagnostics contain only the first failure.
    private func visibleSource(_ source: UIView, through surface: UIView, window: UIWindow) -> Bool {
        guard let failure = NDAAncestorGate.failure(source, through: surface, window: window) else { return true }
        NDARecordAncestorFailure(failure.reason.event, failure.view, failure.depth, failure.effectiveAlpha)
        return false
    }

    private func hostVisible(_ window: UIWindow) -> Bool {
        let scene: NDAHostSceneState
        if let windowScene = window.windowScene {
            switch windowScene.activationState {
            case .foregroundActive: scene = .foregroundActive
            case .foregroundInactive: scene = .foregroundInactive
            case .background: scene = .background
            case .unattached: scene = .unattached
            @unknown default: return false
            }
        } else { scene = .absent }
        return NDAHostVisibility.allows(
            isSpringBoard: Bundle.main.bundleIdentifier == "com.apple.springboard",
            windowVisible: !window.isHidden && window.alpha > 0.01, scene: scene)
    }

    private func validSurface(_ handle: NDAEffectHandle) -> Bool {
        guard let surface = handle.surface, let window = handle.window,
              surface.window === window, !surface.isHidden, surface.alpha > 0.01,
              !window.isHidden,
              hostVisible(window),
              surface.bounds == handle.surfaceBounds else { return false }
        var parent: UIView? = surface
        var effectiveAlpha: CGFloat = 1
        while let view = parent {
            effectiveAlpha *= view.alpha
            if view.isHidden || effectiveAlpha < 0.99 ||
                !CATransform3DIsIdentity(view.layer.transform) ||
                !CATransform3DIsIdentity(view.layer.sublayerTransform) ||
                view.layer.mask != nil || !(view.layer.animationKeys() ?? []).isEmpty { return false }
            if view === window { return true }
            parent = view.superview
        }
        return false
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.sweep() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sweep() {
        let now = CACurrentMediaTime()
        for lease in admission.expire(at: now) { destroy(lease.id) }
        let invalid = handles.values.filter {
            now >= $0.deadline || !validSurface($0) || UIAccessibility.isReduceMotionEnabled
        }.map { $0.lease.id }
        for id in invalid { destroy(id) }
    }

    private func destroy(_ id: UUID) {
        guard let handle = handles.removeValue(forKey: id) else { return }
        handle.container.layer.sublayers?.forEach { $0.removeAllAnimations(); $0.contents = nil }
        handle.container.layer.sublayers = nil
        handle.container.removeFromSuperview()
        admission.release(handle.lease)
        if handles.isEmpty { timer?.invalidate(); timer = nil }
    }

    func cancelAll() {
        guard Thread.isMainThread else { return }
        for id in Array(handles.keys) { destroy(id) }
        admission.cancelAll()
    }
}
