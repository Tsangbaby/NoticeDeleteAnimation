import Foundation
import UIKit

/// Enabled by default. The Settings bundle writes the same preferences domain.
enum NDASettings {
    static let domain = "com.tsangbaby.noticedeleteanimation"
    static var enabled: Bool {
        CFPreferencesAppSynchronize(domain as CFString)
        guard let value = CFPreferencesCopyAppValue("Enabled" as CFString, domain as CFString) else {
            return true
        }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return true }
        return (value as? NSNumber)?.boolValue ?? true
    }
}

private enum NDABoot {
    static var started = false
    static var retries = 0
    static var sawReady = false
    static var timer: Timer?
    static func install() {
        let ready = NDAInstallHooks({ source, surface in
            NDAAnimator.shared.prepare(source: source, surface: surface)
        }, { object, committed in
            guard let handle = object as? NDAEffectHandle else { return }
            NDAAnimator.shared.finish(handle, committed: committed)
        })
        sawReady = sawReady || ready
        // A partial ready set must not stop discovering late-loaded classes or
        // overloads. Per-hook flags make the full 60-second window idempotent.
        if retries >= 60 {
            timer?.invalidate()
            timer = nil
            if !sawReady { NDARecordEvent("install.retry_exhausted") }
        }
    }
    static func start() {
        guard !started else { return }
        started = true
        NDARecordEvent("bootstrap")
        timer = Timer(timeInterval: 1, repeats: true) { _ in
            retries += 1
            install()
        }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        install()
    }
}

@_cdecl("NDASwiftStart")
func NDASwiftStart() {
    DispatchQueue.main.async {
        guard Bundle.main.bundleIdentifier == "com.apple.springboard" else { return }
        NDABoot.start()
    }
}
