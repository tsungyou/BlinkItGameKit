//
//  GameEngine.swift
//  recordGame
//
//  SpriteKit 場景基底 + 連接輸入與結束回呼；旋轉靶的具體場景由 makeScene 建立。
//

import Combine
import Foundation
import SpriteKit
import UIKit

// MARK: - SpriteKit 基底
@MainActor
class BaseGameScene: SKScene {
    var onGameOver: ((Int, Bool) -> Void)?
    var currentScore: Int = 0
    private var hasEnded = false

    func handleInput(action: GameAction) {}

    func gameOver(didWin: Bool = true) {
        guard !hasEnded else { return }
        hasEnded = true
        isPaused = true
        onGameOver?(currentScore, didWin)
    }
}

// MARK: - 引擎（輸入 → 場景 → 結算狀態）
@MainActor
final class GameEngine: ObservableObject {
    @Published var isGameOver = false
    @Published var finalScore = 0
    @Published var lastGameDidWin = true

    let currentScene: BaseGameScene
    var inputProvider: InputProvider
    private(set) var touchInput: TouchInputProvider?

    init(scene: BaseGameScene, input: InputProvider) {
        self.currentScene = scene
        self.inputProvider = input
        self.touchInput = input as? TouchInputProvider
        inputProvider.onActionDetected = { [weak self] action in
            DispatchQueue.main.async { self?.currentScene.handleInput(action: action) }
        }
        currentScene.onGameOver = { [weak self] score, didWin in
            DispatchQueue.main.async {
                self?.finalScore = score
                self?.lastGameDidWin = didWin
                self?.isGameOver = true
                self?.inputProvider.stopCapture()
            }
        }
    }

    func startGame() {
        inputProvider.startCapture()
    }

    // deinit {
    //     inputProvider.stopCapture()
    // }

    private static func safeSceneSize(_ proposed: CGSize) -> CGSize {
        let fallback = CGSize(width: 390, height: 844)
        let ww = (proposed.width.isFinite && proposed.width > 0) ? proposed.width : fallback.width
        let hh = (proposed.height.isFinite && proposed.height > 0) ? proposed.height : fallback.height
        return CGSize(width: max(320, ww), height: max(568, hh))
    }

    static func makeScene(
        size: CGSize,
        skin: RotationTargetSkin = .init(),
        config: RotationTargetConfig = .init()
    ) -> BaseGameScene {
        let scene = ShootGameScene(skin: skin, config: config)
        scene.size = safeSceneSize(size)
        scene.scaleMode = .resizeFill
        return scene
    }

    static func makeInput(trigger: InputTrigger) -> InputProvider {
        switch trigger {
        case .tap: return TouchInputProvider()
        case .blink: return FaceExpressionInputProvider(mode: .blink)
        case .mouthOpen: return FaceExpressionInputProvider(mode: .mouthOpen)
        }
    }
}
