import Foundation
import SpriteKit
import AudioToolbox
import UIKit

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let projectile: UInt32 = 0b1
    static let target: UInt32 = 0b10
}

final class ShootGameScene: BaseGameScene, @preconcurrency SKPhysicsContactDelegate {
    let targetContainer = SKNode()
    private let skin: RotationTargetSkin
    private let config: RotationTargetConfig

    var bulletsCount: Int
    var currentSpeed: CGFloat
    var score = 0
    var totalTargets: Int

    private var labelAmmo: SKLabelNode?
    private lazy var targetTexture: SKTexture? = {
        guard let imageName = skin.targetImageName,
              let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return SKTexture(image: image)
    }()
    private lazy var bulletTexture: SKTexture? = {
        guard let imageName = skin.bulletImageName,
              let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return SKTexture(image: image)
    }()
    private lazy var hitSoundID: SystemSoundID? = {
        guard let fileName = config.hitSoundFileName else { return nil }
        let nsName = fileName as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? "wav" : nsName.pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext) else { return nil }
        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        return status == kAudioServicesNoError ? soundID : nil
    }()
    private var ammoHintLabel: SKLabelNode?
    private var didFinishByNoAmmo = false

    private static let weaponPlaceholderName = "weaponPlaceholder"

    init(skin: RotationTargetSkin = .init(), config: RotationTargetConfig = .init()) {
        self.skin = skin
        self.config = config
        self.bulletsCount = config.bulletsCount
        self.currentSpeed = config.initialRotationSpeed
        self.totalTargets = config.totalTargets
        super.init(size: .zero)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero

        setupTarget()

        targetContainer.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
        addChild(targetContainer)

        startRotation()
        setupHUD()
        setupWeaponPlaceholder()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutHUD()
        layoutWeaponPlaceholder()
    }

    private func setupHUD() {
        childNode(withName: "hudRoot")?.removeFromParent()

        let root = SKNode()
        root.name = "hudRoot"
        root.zPosition = 500
        let ammo = makeHUDLabel()
        labelAmmo = ammo

        root.addChild(ammo)
        let hint = makeAmmoHintLabel()
        ammoHintLabel = hint
        root.addChild(hint)
        addChild(root)

        layoutHUD()
        refreshHUD()
    }

    private func makeHUDLabel() -> SKLabelNode {
        let n = SKLabelNode(text: "")
        n.fontName = "PingFangTC-Medium"
        n.fontSize = 20
        n.fontColor = .white
        n.horizontalAlignmentMode = .left
        n.verticalAlignmentMode = .top
        return n
    }

    private func makeAmmoHintLabel() -> SKLabelNode {
        let n = SKLabelNode(text: "")
        n.fontName = "PingFangTC-Medium"
        n.fontSize = 13
        n.fontColor = UIColor.white.withAlphaComponent(0.85)
        n.horizontalAlignmentMode = .center
        n.verticalAlignmentMode = .baseline
        n.alpha = 0
        return n
    }

    private func layoutHUD() {
        let bottomPad: CGFloat = 36
        labelAmmo?.horizontalAlignmentMode = .center
        labelAmmo?.verticalAlignmentMode = .baseline
        labelAmmo?.position = CGPoint(x: size.width / 2, y: bottomPad)
        ammoHintLabel?.position = CGPoint(x: size.width / 2, y: bottomPad + 20)
    }

    private func refreshHUD() {
        labelAmmo?.text = "\(bulletsCount)"
    }

    private func setupWeaponPlaceholder() {
        childNode(withName: Self.weaponPlaceholderName)?.removeFromParent()

        let root = SKNode()
        root.name = Self.weaponPlaceholderName
        root.zPosition = 80

        let ring = SKShapeNode(circleOfRadius: 48)
        ring.fillColor = SKColor(white: 1, alpha: 0.1)
        ring.strokeColor = SKColor(white: 1, alpha: 0.4)
        ring.lineWidth = 2

        let cross = SKShapeNode()
        let path = CGMutablePath()
        let r: CGFloat = 14
        path.move(to: CGPoint(x: -r, y: 0))
        path.addLine(to: CGPoint(x: r, y: 0))
        path.move(to: CGPoint(x: 0, y: -r))
        path.addLine(to: CGPoint(x: 0, y: r))
        cross.path = path
        cross.strokeColor = SKColor(white: 1, alpha: 0.35)
        cross.lineWidth = 1.5

        root.addChild(ring)
        root.addChild(cross)
        addChild(root)
        layoutWeaponPlaceholder()
    }

    private func layoutWeaponPlaceholder() {
        guard let root = childNode(withName: Self.weaponPlaceholderName) else { return }
        root.position = CGPoint(x: size.width / 2, y: size.height * 0.11)
    }

    private func setupTarget() {
        let radius: CGFloat = 100
        let angleIncrement = (CGFloat.pi * 2) / CGFloat(totalTargets)
        let targetRadius: CGFloat = 20

        for i in 0..<totalTargets {
            let targetNode: SKNode
            if let targetTexture {
                targetNode = SKSpriteNode(texture: targetTexture, size: CGSize(width: 40, height: 40))
            } else {
                let fallback = SKShapeNode(circleOfRadius: targetRadius)
                fallback.fillColor = .blue
                fallback.strokeColor = .white
                targetNode = fallback
            }
            targetNode.name = "target"
            let angle = angleIncrement * CGFloat(i)
            targetNode.position = CGPoint(x: radius * cos(angle), y: radius * sin(angle))

            targetNode.physicsBody = SKPhysicsBody(circleOfRadius: targetRadius)
            targetNode.physicsBody?.isDynamic = true
            targetNode.physicsBody?.categoryBitMask = PhysicsCategory.target
            targetNode.physicsBody?.contactTestBitMask = PhysicsCategory.projectile
            targetNode.physicsBody?.collisionBitMask = PhysicsCategory.none

            targetContainer.addChild(targetNode)
        }
    }

    private func startRotation() {
        targetContainer.removeAllActions()
        let rotateDuration = config.rotationBaseDuration / max(currentSpeed, 0.1)
        let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: rotateDuration)
        targetContainer.run(SKAction.repeatForever(rotateAction))
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard config.keepTargetUpright else { return }

        let counterRotation = -targetContainer.zRotation
        for targetNode in targetContainer.children {
            targetNode.zRotation = counterRotation
        }
        updateAmmoHint()
        evaluateFailureIfOutOfAmmo()
    }

    private func updateAmmoHint() {
        let isWaitingLastShot = bulletsCount == 0
            && children.contains { $0.name == "projectile" }
            && !targetContainer.children.isEmpty

        ammoHintLabel?.text = isWaitingLastShot ? "子彈用完，等待最後一發結果..." : ""
        ammoHintLabel?.alpha = isWaitingLastShot ? 1 : 0
    }

    override func handleInput(action: GameAction) {
        switch action {
        case .fire:
            tryShoot()
        }
    }

    private func tryShoot() {
        guard bulletsCount > 0 else {
            // User may tap again after ammo runs out; treat it as a final-state check trigger.
            evaluateFailureIfOutOfAmmo()
            return
        }
        let isLastShot = (bulletsCount == 1)
        shootProjectile(isLastShot: isLastShot)
        bulletsCount -= 1
        refreshHUD()
        if bulletsCount == 0 {
            evaluateFailureIfOutOfAmmo()
        }
    }

    private func shootProjectile(isLastShot: Bool = false) {
        let projectile: SKNode
        if let bulletTexture {
            projectile = SKSpriteNode(texture: bulletTexture, size: CGSize(width: 20, height: 20))
        } else {
            let fallback = SKShapeNode(circleOfRadius: 10)
            fallback.fillColor = .yellow
            projectile = fallback
        }
        projectile.position = CGPoint(x: size.width / 2, y: size.height * 0.1)
        projectile.name = "projectile"

        projectile.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        projectile.physicsBody?.isDynamic = true
        projectile.physicsBody?.categoryBitMask = PhysicsCategory.projectile
        projectile.physicsBody?.contactTestBitMask = PhysicsCategory.target
        projectile.physicsBody?.collisionBitMask = PhysicsCategory.none
        projectile.physicsBody?.usesPreciseCollisionDetection = true

        addChild(projectile)

        let moveAction = SKAction.move(
            to: CGPoint(x: size.width / 2, y: size.height + 50),
            duration: config.bulletTravelDuration
        )
        let removeAction = SKAction.removeFromParent()
        let finalShotCheck = SKAction.run { [weak self] in
            guard let self, isLastShot else { return }
            self.evaluateFailureIfOutOfAmmo()
        }
        projectile.run(SKAction.sequence([moveAction, removeAction, finalShotCheck]))
    }

    private func evaluateFailureIfOutOfAmmo() {
        guard !didFinishByNoAmmo else { return }
        guard bulletsCount == 0 else { return }
        let hasProjectileInFlight = children.contains { $0.name == "projectile" }
        guard !hasProjectileInFlight else { return }
        guard !targetContainer.children.isEmpty else { return }

        didFinishByNoAmmo = true
        targetContainer.removeAllActions()
        gameOver(didWin: false)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        var firstBody: SKPhysicsBody
        var secondBody: SKPhysicsBody

        if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
            firstBody = contact.bodyA
            secondBody = contact.bodyB
        } else {
            firstBody = contact.bodyB
            secondBody = contact.bodyA
        }

        if firstBody.categoryBitMask == PhysicsCategory.projectile && secondBody.categoryBitMask == PhysicsCategory.target {
            if let projectileNode = firstBody.node,
               let targetNode = secondBody.node {
                projectileDidCollideWithTarget(projectile: projectileNode, target: targetNode)
            }
        }
    }

    private func projectileDidCollideWithTarget(projectile: SKNode, target: SKNode) {
        projectile.removeFromParent()
        target.removeFromParent()
        if let hitSoundID {
            AudioServicesPlaySystemSound(hitSoundID)
        }

        score += 1
        currentScore = score

        currentSpeed += config.speedIncrementPerHit
        startRotation()
        refreshHUD()

        if targetContainer.children.isEmpty {
            levelCompleted()
        } else {
            evaluateFailureIfOutOfAmmo()
        }
    }

    private func levelCompleted() {
        targetContainer.removeAllActions()
        currentScore = score
        gameOver(didWin: true)
    }
}
