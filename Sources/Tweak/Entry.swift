import Foundation
import UIKit

/// No Settings injection or private Preferences framework dependency. The source
/// candidate is enabled by default; persistent opt-out is read on each removal.
enum NDASettings {
    static let domain = "com.tsangbaby.noticedeleteanimation"
    static var enabled: Bool {
        guard let value = CFPreferencesCopyAppValue("Enabled" as CFString, domain as CFString) else {
            return true
        }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return true }
        return (value as? NSNumber)?.boolValue ?? true
    }
}

@_cdecl("NDASwiftStart")
func NDASwiftStart() {
    DispatchQueue.main.async {
        guard Bundle.main.bundleIdentifier == "com.apple.springboard" else { return }
        NDAInstallHooks({ source, surface in
            NDAAnimator.shared.prepare(source: source, surface: surface)
        }, { object, committed in
            guard let handle = object as? NDAEffectHandle else { return }
            NDAAnimator.shared.finish(handle, committed: committed)
        })
    }
}
