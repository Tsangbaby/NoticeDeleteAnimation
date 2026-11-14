/// UIKit-independent policy: system-owned SpringBoard windows may not carry a
/// UIWindowScene. Never apply that exception to an ordinary application host.
public enum NDAHostSceneState {
    case absent, foregroundActive, foregroundInactive, background, unattached
}

public enum NDAHostVisibility {
    public static func allows(isSpringBoard: Bool, windowVisible: Bool,
                              scene: NDAHostSceneState) -> Bool {
        guard windowVisible else { return false }
        switch scene {
        case .foregroundActive: return true
        case .absent, .foregroundInactive: return isSpringBoard
        case .background, .unattached: return false
        }
    }
}
