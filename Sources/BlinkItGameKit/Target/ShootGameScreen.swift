//
//  ShootGameScreen.swift
//  recordGame
//
//  旋轉靶 SwiftUI：相機背景、觸發選擇、SpriteView、結算 overlay。
//  輸入見 GameInput.swift；引擎與 BaseGameScene 見 GameEngine.swift。
//

import Foundation
import ReplayKit
import SpriteKit
import SwiftUI
import UIKit

// MARK: - SwiftUI

struct ShootGameView: View {
    @Environment(\.dismiss) private var dismiss
    private let fixedTrigger: InputTrigger?
    private let skin: RotationTargetSkin
    private let config: RotationTargetConfig
    @State private var trigger: InputTrigger
    @State private var sessionKey = UUID()
    @StateObject private var recordingManager = GameRecordingManager()

    init(
        fixedTrigger: InputTrigger? = nil,
        skin: RotationTargetSkin = .init(),
        config: RotationTargetConfig = .init()
    ) {
        self.fixedTrigger = fixedTrigger
        self.skin = skin
        self.config = config
        _trigger = State(initialValue: fixedTrigger ?? .tap)
    }

    var body: some View {
        ZStack {
            CameraBackgroundView()

            ShootGameRoot(
                trigger: trigger,
                skin: skin,
                config: config,
                recordingManager: recordingManager
            )
                .id(sessionKey)

            VStack {
                HStack {
                    Button {
                        recordingManager.discardRecordingIfNeeded {
                            dismiss()
                        }
                    } label: {
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
    let skin: RotationTargetSkin
    let config: RotationTargetConfig

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var camera = CameraSessionManager.shared
    @StateObject private var engine: GameEngine
    @ObservedObject var recordingManager: GameRecordingManager
    @State private var showGameOver = false
    @State private var didStartGame = false

    @State private var showIntroOverlay = false
    @State private var introDetected = false
    @State private var countdownValue: Int?
    @State private var introSessionID = UUID()
    @State private var introDetectedImage: UIImage?

    init(
        trigger: InputTrigger,
        skin: RotationTargetSkin,
        config: RotationTargetConfig,
        recordingManager: GameRecordingManager
    ) {
        self.trigger = trigger
        self.skin = skin
        self.config = config
        self.recordingManager = recordingManager
        let size = UIScreen.main.bounds.size
        let scene = GameEngine.makeScene(size: size, skin: skin, config: config)
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

            if recordingManager.isRecording {
                VStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .opacity(0.95)
                        Text("REC")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.opacity)
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
            recordingManager.discardRecordingIfNeeded()
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
                Button("分享錄影") {
                    recordingManager.stopRecordingForSharing()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .foregroundStyle(Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.divider, lineWidth: 1)
                )
                .disabled(!recordingManager.isRecording)
                .opacity(recordingManager.isRecording ? 1 : 0.55)
                Button("返回") {
                    recordingManager.discardRecordingIfNeeded {
                        dismiss()
                    }
                }
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
        .sheet(item: $recordingManager.previewControllerItem) { item in
            RecordingPreviewSheet(controller: item.controller)
                .ignoresSafeArea()
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
                    if let introDetectedImage {
                        Image(uiImage: introDetectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
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
        recordingManager.startRecording()
        engine.startGame()
    }

    private func beginIntroFlow() {
        showIntroOverlay = true
        introDetected = false
        countdownValue = nil
        didStartGame = false
        introDetectedImage = loadImageFromModule(named: skin.targetImageName)

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

    private func loadImageFromModule(named imageName: String?) -> UIImage? {
        guard let imageName,
              let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
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

private struct RecordingPreviewSheet: UIViewControllerRepresentable {
    let controller: RPPreviewViewController

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {}
}

@MainActor
private final class GameRecordingManager: NSObject, ObservableObject, RPPreviewViewControllerDelegate {
    struct PreviewItem: Identifiable {
        let id = UUID()
        let controller: RPPreviewViewController
    }

    @Published var previewControllerItem: PreviewItem?
    @Published private(set) var isRecording = false

    private var isStopping = false
    private var pendingDiscardCompletions: [() -> Void] = []

    func startRecording() {
        let recorder = RPScreenRecorder.shared()
        guard !isRecording else { return }
        guard !recorder.isRecording else {
            isRecording = true
            return
        }
        recorder.isMicrophoneEnabled = true
        recorder.startRecording { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = (error == nil)
            }
        }
    }

    func stopRecordingForSharing() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        RPScreenRecorder.shared().stopRecording { [weak self] previewController, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                self.isStopping = false

                if let previewController {
                    previewController.previewControllerDelegate = self
                    self.previewControllerItem = PreviewItem(controller: previewController)
                }
            }
        }
    }

    func stopRecordingIfNeeded() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        RPScreenRecorder.shared().stopRecording { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isRecording = false
                self?.isStopping = false
            }
        }
    }

    func discardRecordingIfNeeded(completion: (() -> Void)? = nil) {
        if let completion {
            pendingDiscardCompletions.append(completion)
        }

        let recorder = RPScreenRecorder.shared()
        guard recorder.isRecording else {
            isRecording = false
            flushDiscardCompletions()
            return
        }
        guard !isStopping else { return }

        isStopping = true
        recorder.stopRecording { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecording = false
                self.isStopping = false
                self.flushDiscardCompletions()
            }
        }
    }

    private func flushDiscardCompletions() {
        let completions = pendingDiscardCompletions
        pendingDiscardCompletions.removeAll()
        completions.forEach { $0() }
    }

    nonisolated func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        DispatchQueue.main.async { [weak self] in
            previewController.dismiss(animated: true)
            self?.previewControllerItem = nil
        }
    }
}
