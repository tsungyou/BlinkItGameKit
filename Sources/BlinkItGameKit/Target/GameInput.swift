//
//  GameInput.swift
//  recordGame
//
//  共用輸入：意圖（GameAction）、觸發方式（InputTrigger）、Provider 實作。
//  新遊戲只要處理相同的 GameAction，即可重用點擊／臉部輸入。
//

import Foundation

// MARK: - 意圖（遊戲只認這個）

enum GameAction {
    case fire
}

// MARK: - UI 選擇的觸發方式

enum InputTrigger: String, CaseIterable, Identifiable {
    case tap = "點擊"
    case blink = "眨眼"
    case mouthOpen = "張嘴"

    var id: String { rawValue }
}

// MARK: - Provider

protocol InputProvider: AnyObject {
    var onActionDetected: ((GameAction) -> Void)? { get set }
    func startCapture()
    func stopCapture()
}

final class TouchInputProvider: InputProvider {
    var onActionDetected: ((GameAction) -> Void)?

    func startCapture() {}
    func stopCapture() {}

    func reportTap(normalizedPoint: CGPoint? = nil) {
        onActionDetected?(.fire)
    }
}

final class FaceExpressionInputProvider: InputProvider {
    var onActionDetected: ((GameAction) -> Void)?

    private let mode: FaceExpressionTriggerMode
    private let camera = CameraSessionManager.shared

    init(mode: FaceExpressionTriggerMode) {
        self.mode = mode
    }

    func startCapture() {
        camera.setFaceExpressionMode(mode)
        camera.syncAuthorizationAndStartPreview()
        camera.isFaceAnalysisEnabled = true
        camera.onExpressionFire = { [weak self] in
            self?.onActionDetected?(.fire)
        }
    }

    func stopCapture() {
        camera.isFaceAnalysisEnabled = false
        camera.onExpressionFire = nil
    }
}
