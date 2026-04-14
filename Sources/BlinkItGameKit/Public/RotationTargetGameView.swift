import SwiftUI

public enum RotationTargetTrigger: String, CaseIterable, Identifiable {
    case tap
    case blink
    case mouthOpen

    public var id: String { rawValue }
}

/// 套件對外主入口（宿主可以直接放在 NavigationLink 裡）。
/// 目前先提供可編譯骨架；等你把遊戲核心檔案搬進套件後，
/// 只要把 `RotationTargetPlaceholderView` 換成真正的遊戲 View 即可。
public struct RotationTargetGameView: View {
    private let trigger: RotationTargetTrigger

    public init(trigger: RotationTargetTrigger) {
        self.trigger = trigger
    }

    public var body: some View {
        RotationTargetPlaceholderView(trigger: trigger)
    }
}

private struct RotationTargetPlaceholderView: View {
    let trigger: RotationTargetTrigger

    private var triggerLabel: String {
        switch trigger {
        case .tap: return "點擊"
        case .blink: return "眨眼"
        case .mouthOpen: return "張嘴"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.86), Color.black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                Text("BlinkItGameKit")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("旋轉靶（\(triggerLabel)）")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("已成功走到套件 public 入口")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
            .multilineTextAlignment(.center)
        }
    }
}
