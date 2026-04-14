//
//  ShootGameScreen.swift
//  recordGame
//
//  旋轉靶 SwiftUI：相機背景、觸發選擇、SpriteView、結算 overlay。
//  輸入見 GameInput.swift；引擎與 BaseGameScene 見 GameEngine.swift。
//

import Foundation
import SpriteKit
import SwiftUI
import UIKit

// MARK: - SwiftUI

private enum Theme {
    static let accent = Color(red: 0.941, green: 0.725, blue: 0.035)
    static let textPrimary = Color(red: 0.118, green: 0.137, blue: 0.161)
    static let textSecondary = Color(red: 0.439, green: 0.478, blue: 0.541)
    static let divider = Color(red: 0.918, green: 0.925, blue: 0.933)
    static let surface = Color.white
}

struct ShootGameView: View {
    @Environment(\.dismiss) private var dismiss
    private let fixedTrigger: InputTrigger?
    @State private var trigger: InputTrigger
    @State private var sessionKey = UUID()

    init(fixedTrigger: InputTrigger? = nil) {
        self.fixedTrigger = fixedTrigger
        _trigger = State(initialValue: fixedTrigger ?? .tap)
    }

    var body: some View {
        ZStack {
            CameraBackgroundView()

            ShootGameRoot(trigger: trigger)
                .id(sessionKey)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Theme.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
                            )
                            .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if fixedTrigger == nil {
                    Picker("觸發", selection: $trigger) {
                        ForEach(InputTrigger.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.surface.opacity(0.95))
                            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.divider, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .onChange(of: trigger) { _ in sessionKey = UUID() }
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

private struct ShootGameRoot: View {
    let trigger: InputTrigger

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var camera = CameraSessionManager.shared
    @StateObject private var engine: GameEngine
    @State private var showGameOver = false
    @State private var didStartGame = false

    @State private var showIntroOverlay = false
    @State private var introDetected = false
    @State private var countdownValue: Int?
    @State private var introSessionID = UUID()

    init(trigger: InputTrigger) {
        self.trigger = trigger
        let size = UIScreen.main.bounds.size
        let scene = GameEngine.makeScene(size: size)
        let input = GameEngine.makeInput(trigger: trigger)
        _engine = StateObject(wrappedValue: GameEngine(scene: scene, input: input))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: engine.currentScene, options: [.allowsTransparency])
                .background(Color.clear)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if trigger == .tap {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if showIntroOverlay {
                            handleTapIntroTrigger()
                        } else {
                            engine.touchInput?.reportTap(normalizedPoint: nil)
                        }
                    }
                    .ignoresSafeArea()
            }

            if showGameOver {
                gameOverOverlay
            }

            if showIntroOverlay {
                introOverlay
            }

#if DEBUG
            debugMetricsOverlay
#endif
        }
        .onAppear {
            showGameOver = false
            beginIntroFlow()
        }
        .onDisappear {
            stopFaceIntroListening()
        }
        .onChange(of: engine.isGameOver) { ended in
            if ended {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    showGameOver = true
                }
            }
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(engine.lastGameDidWin ? "通關" : "未能通關")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("分數 \(engine.finalScore)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Button("返回") { dismiss() }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .foregroundStyle(Theme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.divider, lineWidth: 1))
            .padding(24)
        }
    }

    private var introOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(introTitle)
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if introDetected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }

                if let n = countdownValue {
                    Text("\(n)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .transition(.scale.combined(with: .opacity))
                } else if !introDetected {
                    Text(introHint)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if trigger == .tap {
                handleTapIntroTrigger()
            }
        }
    }

    private var introTitle: String {
        switch trigger {
        case .tap: return "tap to start!"
        case .blink: return "wink now!"
        case .mouthOpen: return "open your mouth!"
        }
    }

    private var introHint: String {
        switch trigger {
        case .tap: return "點擊畫面開始"
        case .blink: return "偵測到扎眼後開始"
        case .mouthOpen: return "偵測到張嘴後開始"
        }
    }

    private func startGameIfNeeded() {
        guard !didStartGame else { return }
        didStartGame = true
        engine.startGame()
    }

    private func beginIntroFlow() {
        showIntroOverlay = true
        introDetected = false
        countdownValue = nil
        didStartGame = false

        let sessionID = UUID()
        introSessionID = sessionID

        switch trigger {
        case .tap:
            break
        case .blink:
            beginFaceIntroListening(mode: .blink, sessionID: sessionID)
        case .mouthOpen:
            beginFaceIntroListening(mode: .mouthOpen, sessionID: sessionID)
        }
    }

    private func handleTapIntroTrigger() {
        guard trigger == .tap else { return }
        guard !introDetected else { return }
        let sessionID = introSessionID
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            introDetected = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            runCountdown(start: 3, sessionID: sessionID)
        }
    }

    private func beginFaceIntroListening(mode: FaceExpressionTriggerMode, sessionID: UUID) {
        let camera = CameraSessionManager.shared
        camera.setFaceExpressionMode(mode)
        camera.syncAuthorizationAndStartPreview()
        camera.isFaceAnalysisEnabled = true
        camera.onExpressionFire = {
            DispatchQueue.main.async {
                guard introSessionID == sessionID else { return }
                guard !introDetected else { return }

                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    introDetected = true
                }
                stopFaceIntroListening()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    runCountdown(start: 3, sessionID: sessionID)
                }
            }
        }
    }

    private func runCountdown(start: Int, sessionID: UUID) {
        guard introSessionID == sessionID else { return }
        guard start >= 1 else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showIntroOverlay = false
                countdownValue = nil
            }
            startGameIfNeeded()
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            countdownValue = start
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            runCountdown(start: start - 1, sessionID: sessionID)
        }
    }

    private func stopFaceIntroListening() {
        guard trigger != .tap else { return }
        let camera = CameraSessionManager.shared
        camera.onExpressionFire = nil
        camera.isFaceAnalysisEnabled = false
    }

#if DEBUG
    private var debugMetricsOverlay: some View {
        VStack {
            HStack {
                if let s = camera.expressionDebugState, showDebug(for: s) {
                    VStack(alignment: .leading, spacing: 4) {
                        if trigger == .blink {
                            Text("EAR \(fmt(s.eyeAspectRatio))")
                            Text("Baseline \(fmt(s.blinkBaselineEAR))")
                            Text("Close<th \(fmt(s.blinkClosedThreshold))")
                            Text("Reopen>th \(fmt(s.blinkReopenThreshold))")
                        } else if trigger == .mouthOpen {
                            Text("Mouth \(fmt(s.mouthOpenRatio))")
                            Text("Threshold \(fmt(s.mouthOpenThreshold))")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 58)
                    .padding(.leading, 12)
                }
                Spacer()
            }
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func showDebug(for state: FaceExpressionDebugState) -> Bool {
        switch trigger {
        case .blink: return state.mode == .blink
        case .mouthOpen: return state.mode == .mouthOpen
        case .tap: return false
        }
    }

    private func fmt(_ v: CGFloat?) -> String {
        guard let v else { return "-" }
        return String(format: "%.3f", v)
    }
#endif
}
