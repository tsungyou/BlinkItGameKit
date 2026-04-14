import SwiftUI

/// G1~G4：給宿主極簡使用（HomeView 只要丟 G1()...G4()）。
public struct G1: View {
    public init() {}
    public var body: some View {
        RotationTargetGameView(trigger: .tap)
    }
}

public struct G2: View {
    public init() {}
    public var body: some View {
        RotationTargetGameView(trigger: .blink)
    }
}

public struct G3: View {
    public init() {}
    public var body: some View {
        RotationTargetGameView(trigger: .mouthOpen)
    }
}

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
