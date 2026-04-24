import SwiftUI

public enum RotationTargetTrigger: String, CaseIterable, Identifiable {
    case tap
    case blink
    case mouthOpen

    public var id: String { rawValue }
}

public struct RotationTargetSkin {
    public let targetImageName: String?
    public let bulletImageName: String?

    public init(targetImageName: String? = nil, bulletImageName: String? = nil) {
        self.targetImageName = targetImageName
        self.bulletImageName = bulletImageName
    }
}

public struct RotationTargetConfig {
    public let bulletsCount: Int
    public let totalTargets: Int
    public let initialRotationSpeed: CGFloat
    public let speedIncrementPerHit: CGFloat
    public let rotationBaseDuration: TimeInterval
    public let bulletTravelDuration: TimeInterval
    public let keepTargetUpright: Bool
    public let hitSoundFileName: String?

    public init(
        bulletsCount: Int = 10,
        totalTargets: Int = 8,
        initialRotationSpeed: CGFloat = 2.0,
        speedIncrementPerHit: CGFloat = 1.0,
        rotationBaseDuration: TimeInterval = 10.0,
        bulletTravelDuration: TimeInterval = 0.5,
        keepTargetUpright: Bool = true,
        hitSoundFileName: String? = nil
    ) {
        self.bulletsCount = max(1, bulletsCount)
        self.totalTargets = max(1, totalTargets)
        self.initialRotationSpeed = max(0.1, initialRotationSpeed)
        self.speedIncrementPerHit = max(0.0, speedIncrementPerHit)
        self.rotationBaseDuration = max(0.1, rotationBaseDuration)
        self.bulletTravelDuration = max(0.05, bulletTravelDuration)
        self.keepTargetUpright = keepTargetUpright
        self.hitSoundFileName = hitSoundFileName
    }
}

/// 套件對外主入口（宿主可以直接放在 NavigationLink 裡）。
/// 目前先提供可編譯骨架；等你把遊戲核心檔案搬進套件後，
public struct RotationTargetGameView: View {
    private let trigger: RotationTargetTrigger
    private let skin: RotationTargetSkin
    private let config: RotationTargetConfig

    public init(
        trigger: RotationTargetTrigger,
        skin: RotationTargetSkin = .init(),
        config: RotationTargetConfig = .init()
    ) {
        self.trigger = trigger
        self.skin = skin
        self.config = config
    }

    public var body: some View {
        ShootGameView(
            fixedTrigger: mapToInternalTrigger(trigger),
            skin: skin,
            config: config
        )
    }

    private func mapToInternalTrigger(_ value: RotationTargetTrigger) -> InputTrigger {
        switch value {
        case .tap: return .tap
        case .blink: return .blink
        case .mouthOpen: return .mouthOpen
        }
    }
}
