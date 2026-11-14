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
    let region: NDAVisibleRegion
    let plan: NDAParticlePlan
    var committed = false
    var deadline: CFTimeInterval

    init(lease: NDAEffectLease, container: NDAEffectSurface, surface: UIView,
         region: NDAVisibleRegion, plan: NDAParticlePlan) {
        self.lease = lease
        self.container = container
        self.surface = surface
        self.window = surface.window
        self.surfaceBounds = surface.bounds
        self.sourceFrame = region.surfaceRect
        self.region = region
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
    private var cancellationEpoch: UInt64 = 0

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
        guard let visible = visibleSource(source, through: surface, window: window) else {
            NDARecordEvent("capture.ancestors"); return nil
        }
        // Pick scale BEFORE inward alignment. Capture never rounds a hidden edge outward.
        let area = visible.sourceRect.width * visible.sourceRect.height
        guard area.isFinite, area > 0 else { NDARecordEvent("capture.geometry"); return nil }
        let desiredScale = captureScale(area: area, nativeScale: window.screen.scale)
        guard desiredScale.isFinite, desiredScale > 0,
              let region = visible.inwardAligned(scale: desiredScale, source: source, surface: surface),
              region.sourceRect.width > 1, region.sourceRect.height > 1,
              region.isCaptureValid(source: source, surface: surface, window: window) else {
            NDARecordEvent("capture.geometry"); return nil
        }
        sweep()
        guard handles.count < policy.maxConcurrent else { NDARecordEvent("capture.capacity"); return nil }
        let frame = region.surfaceRect
        guard frame.width.isFinite, frame.height.isFinite,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width > 1, frame.height > 1,
              region.clipRect.contains(frame) else {
            NDARecordEvent("capture.geometry"); return nil
        }
        seed &+= 1
        guard let plan = NDAParticlePlan.make(width: Double(frame.width),
            height: Double(frame.height), seed: seed, policy: policy) else { NDARecordEvent("capture.plan"); return nil }
        // Reserve actual crop pixels (plus bounded renderer rounding), never full hidden card.
        let width = Int(ceil(region.sourceRect.width * desiredScale))
        let height = Int(ceil(region.sourceRect.height * desiredScale))
        let result = admission.admit(NDAAdmissionRequest(token: UUID(),
            tileCount: plan.particles.count, bitmapWidth: width + 2,
            bitmapHeight: height + 2), at: CACurrentMediaTime())
        for lease in result.expiredLeases { destroy(lease.id) }
        guard case .accepted(let lease) = result.decision else { NDARecordEvent("capture.capacity"); return nil }
        let epoch = cancellationEpoch
        guard let image = NDACaptureRegion(source, region.sourceRect, desiredScale), let cgImage = image.cgImage,
              cgImage.width == width, cgImage.height == height,
              cancellationEpoch == epoch, admission.activeLeases.contains(where: { $0.id == lease.id }),
              NDASettings.enabled, !UIAccessibility.isReduceMotionEnabled, hostVisible(window),
              source.bounds == region.sourceBounds,
              region.isCaptureValid(source: source, surface: surface, window: window),
              case .accepted(let checked) = NDAVisibleRegionPlanner.resolve(source, through: surface, window: window),
              let checkedAligned = checked.inwardAligned(scale: desiredScale, source: source, surface: surface),
              checkedAligned.sourceRect == region.sourceRect,
              checkedAligned.surfaceRect == region.surfaceRect,
              checkedAligned.clipRect == region.clipRect else {
            admission.release(lease)
            NDARecordEvent("capture.bitmap")
            return nil
        }
        let container = NDAEffectSurface(frame: region.clipRect)
        // Keep list-local coordinates, but clip particle travel to the entire chain's
        // shared allowed viewport. No concealed source pixels exist in the crop texture.
        container.bounds = region.clipRect
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
                                     surface: surface, region: region, plan: plan)
        handle.source = source
        handles[lease.id] = handle
        startTimer()
        NDARecordRegionPrepared(source, region.sourceRect, region.surfaceRect, region.clipRect, region.partial)
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
        guard handle.source?.isDescendant(of: surface) != true,
              handle.source?.window == nil else {
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

    /// Full chain is inspected even after a partial clip, so a later mask/hidden
    /// ancestor can never be skipped by accepting the first local intersection.
    private func visibleSource(_ source: UIView, through surface: UIView, window: UIWindow) -> NDAVisibleRegion? {
        switch NDAVisibleRegionPlanner.resolve(source, through: surface, window: window) {
        case .accepted(let region): return region
        case .rejected(let failure):
            if let geometry = failure.clipping {
                NDARecordClippingFailure(source, failure.view, failure.depth, failure.effectiveAlpha,
                    geometry.sourceBounds, geometry.sourceInAncestor, geometry.ancestorBounds)
            } else {
                NDARecordAncestorFailure(failure.reason.event, failure.view, failure.depth, failure.effectiveAlpha)
            }
            return nil
        }
    }

    private func captureScale(area: CGFloat, nativeScale: CGFloat) -> CGFloat {
        guard area.isFinite, area > 0, nativeScale.isFinite, nativeScale > 0 else { return 0 }
        // Binary scales keep pixel extents exact without renderer edge expansion.
        var scale: CGFloat = 2
        for _ in 0..<32 {
            if scale <= nativeScale && area * scale * scale <= 218_000 { return scale }
            scale /= 2
        }
        return 0
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
              surface.bounds == handle.surfaceBounds,
              handle.region.isValid(surface: surface, window: window) else { return false }
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
        cancellationEpoch &+= 1
        for id in Array(handles.keys) { destroy(id) }
        admission.cancelAll()
    }
}
