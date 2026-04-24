import SwiftUI

/// 單一對外遊戲入口：宿主自行決定觸發方式與素材。
public struct RouletteShootingGame: View {
    private let trigger: RotationTargetTrigger
    private let targetImageName: String?
    private let bulletImageName: String?
    private let config: RotationTargetConfig

    public init(
        trigger: RotationTargetTrigger,
        targetImageName: String? = nil,
        bulletImageName: String? = nil,
        config: RotationTargetConfig = .init()
    ) {
        self.trigger = trigger
        self.targetImageName = targetImageName
        self.bulletImageName = bulletImageName
        self.config = config
    }

    public var body: some View {
        RotationTargetGameView(
            trigger: trigger,
            skin: .init(targetImageName: targetImageName, bulletImageName: bulletImageName),
            config: config
        )
    }
}
