import SwiftUI

public enum RotationTargetTrigger: String, CaseIterable, Identifiable {
    case tap
    case blink
    case mouthOpen

    public var id: String { rawValue }
}

/// 套件對外主入口（宿主可以直接放在 NavigationLink 裡）。
/// 目前先提供可編譯骨架；等你把遊戲核心檔案搬進套件後，
public struct RotationTargetGameView: View {
    private let trigger: RotationTargetTrigger

    public init(trigger: RotationTargetTrigger) {
        self.trigger = trigger
    }

    public var body: some View {
        ShootGameView(fixedTrigger: mapToInternalTrigger(trigger))
    }

    private func mapToInternalTrigger(_ value: RotationTargetTrigger) -> InputTrigger {
        switch value {
        case .tap: return .tap
        case .blink: return .blink
        case .mouthOpen: return .mouthOpen
        }
    }
}
