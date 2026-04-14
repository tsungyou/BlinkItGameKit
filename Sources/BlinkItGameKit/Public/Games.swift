import SwiftUI

/// 點擊模式
public struct G1: View {
    public init() {}
    public var body: some View {
        RotationTargetGameView(trigger: .tap)
    }
}

/// 眨眼模式
public struct G2: View {
    public init() {}
    public var body: some View {
        RotationTargetGameView(trigger: .blink)
    }
}

/// 張嘴模式
public struct G3: View {
    public init() {}
    public var body: some View {
        RotationTargetGameView(trigger: .mouthOpen)
    }
}

/// 預留入口（之後可換成第 4 個正式遊戲）
public struct G4: View {
    public init() {}
    public var body: some View {
        ZStack {
            Color.blue.opacity(0.15).ignoresSafeArea()
            Text("G4 預留")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}
