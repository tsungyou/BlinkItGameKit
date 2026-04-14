import Foundation
import SpriteKit

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let projectile: UInt32 = 0b1
    static let target: UInt32 = 0b10
}

final class ShootGameScene: BaseGameScene, @preconcurrency SKPhysicsContactDelegate {
    let targetContainer = SKNode()

    var bulletsCount = 10
    var currentSpeed: CGFloat = 2.0
    var score = 0
    var totalTargets = 8

    private var labelAmmo: SKLabelNode?

    private static let weaponPlaceholderName = "weaponPlaceholder"

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

    private func layoutHUD() {
        let pad: CGFloat = 20

        let bottomPad: CGFloat = 36
        labelAmmo?.horizontalAlignmentMode = .center
        labelAmmo?.verticalAlignmentMode = .baseline
        labelAmmo?.position = CGPoint(x: size.width / 2, y: bottomPad)
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

        for i in 0..<totalTargets {
            let targetNode = SKShapeNode(circleOfRadius: 20)
            targetNode.fillColor = .blue
            targetNode.strokeColor = .white
            targetNode.name = "target"

            let angle = angleIncrement * CGFloat(i)
            targetNode.position = CGPoint(x: radius * cos(angle), y: radius * sin(angle))

            targetNode.physicsBody = SKPhysicsBody(circleOfRadius: 20)
            targetNode.physicsBody?.isDynamic = true
            targetNode.physicsBody?.categoryBitMask = PhysicsCategory.target
            targetNode.physicsBody?.contactTestBitMask = PhysicsCategory.projectile
            targetNode.physicsBody?.collisionBitMask = PhysicsCategory.none

            targetContainer.addChild(targetNode)
        }
    }

    private func startRotation() {
        targetContainer.removeAllActions()
        let rotateAction = SKAction.rotate(byAngle: .pi * 2, duration: TimeInterval(10.0 / currentSpeed))
        targetContainer.run(SKAction.repeatForever(rotateAction))
    }

    override func handleInput(action: GameAction) {
        switch action {
        case .fire:
            tryShoot()
        }
    }

    private func tryShoot() {
        guard bulletsCount > 0 else { return }
        shootProjectile()
        bulletsCount -= 1
        refreshHUD()
        if bulletsCount == 0 {
            let wait = SKAction.wait(forDuration: 0.55)
            let check = SKAction.run { [weak self] in
                guard let self else { return }
                if !self.targetContainer.children.isEmpty {
                    self.targetContainer.removeAllActions()
                    self.gameOver(didWin: false)
                }
            }
            run(SKAction.sequence([wait, check]))
        }
    }

    private func shootProjectile() {
        let projectile = SKShapeNode(circleOfRadius: 10)
        projectile.fillColor = .yellow
        projectile.position = CGPoint(x: size.width / 2, y: size.height * 0.1)
        projectile.name = "projectile"

        projectile.physicsBody = SKPhysicsBody(circleOfRadius: 10)
        projectile.physicsBody?.isDynamic = true
        projectile.physicsBody?.categoryBitMask = PhysicsCategory.projectile
        projectile.physicsBody?.contactTestBitMask = PhysicsCategory.target
        projectile.physicsBody?.collisionBitMask = PhysicsCategory.none
        projectile.physicsBody?.usesPreciseCollisionDetection = true

        addChild(projectile)

        let moveAction = SKAction.move(to: CGPoint(x: size.width / 2, y: size.height + 50), duration: 0.5)
        let removeAction = SKAction.removeFromParent()
        projectile.run(SKAction.sequence([moveAction, removeAction]))
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
            if let projectileNode = firstBody.node as? SKShapeNode,
               let targetNode = secondBody.node as? SKShapeNode {
                projectileDidCollideWithTarget(projectile: projectileNode, target: targetNode)
            }
        }
    }

    private func projectileDidCollideWithTarget(projectile: SKShapeNode, target: SKShapeNode) {
        projectile.removeFromParent()
        target.removeFromParent()

        score += 1
        currentScore = score

        currentSpeed += 1.0
        startRotation()
        refreshHUD()

        if targetContainer.children.isEmpty {
            levelCompleted()
        }
    }

    private func levelCompleted() {
        targetContainer.removeAllActions()
        currentScore = score
        gameOver(didWin: true)
    }
}
