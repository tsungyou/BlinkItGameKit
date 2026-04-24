//
//  Camera.swift
//  recordGame
//
//  相機權限 + 單一 AVCaptureSession + SwiftUI 預覽與背景。
//

import AVFoundation
import Combine
import QuartzCore
import SwiftUI
import UIKit
import Vision

// MARK: - 五官 Debug 用資料模型（Vision → 畫面）

struct FaceLandmarkDebugSnapshot: Equatable {
    var imageWidth: Int
    var imageHeight: Int
    var faces: [FaceDebugFaceInfo]
    var captureTime: TimeInterval
}

struct FaceDebugFaceInfo: Equatable {
    var index: Int
    var confidence: Float
    var boundingBoxVisionNormalized: CGRect
    var rollRadians: Double?
    var yawRadians: Double?
    var regions: [FaceDebugRegion]
    var eyeAspectRatio: CGFloat
    var mouthOpenRatio: CGFloat
}

struct FaceDebugRegion: Equatable {
    var name: String
    var pointsVisionNormalized: [CGPoint]
    var isClosedPath: Bool
}

enum VisionImageToViewMapping {
    static func viewPoint(
        visionNormalized p: CGPoint,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        viewSize: CGSize,
        mirrorHorizontally: Bool
    ) -> CGPoint {
        let img = CGSize(width: imageWidth, height: imageHeight)
        let scale = max(viewSize.width / img.width, viewSize.height / img.height)
        let scaledW = img.width * scale
        let scaledH = img.height * scale
        let ox = (viewSize.width - scaledW) / 2
        let oy = (viewSize.height - scaledH) / 2
        let xPix = p.x * img.width
        let yPixFromTop = (1 - p.y) * img.height
        var vx = xPix * scale + ox
        let vy = yPixFromTop * scale + oy
        if mirrorHorizontally { vx = viewSize.width - vx }
        return CGPoint(x: vx, y: vy)
    }

    static func viewRect(
        visionBBox: CGRect,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        viewSize: CGSize,
        mirrorHorizontally: Bool
    ) -> CGRect {
        let corners = [
            CGPoint(x: visionBBox.minX, y: visionBBox.minY),
            CGPoint(x: visionBBox.maxX, y: visionBBox.minY),
            CGPoint(x: visionBBox.minX, y: visionBBox.maxY),
            CGPoint(x: visionBBox.maxX, y: visionBBox.maxY),
        ]
        let mapped = corners.map {
            viewPoint(
                visionNormalized: $0,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                viewSize: viewSize,
                mirrorHorizontally: mirrorHorizontally
            )
        }
        let xs = mapped.map(\.x)
        let ys = mapped.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}

enum FaceDebugLandmarkPalette {
    static func color(forRegionName name: String) -> Color {
        switch name {
        case "faceContour": return .green
        case "leftEye", "rightEye": return .cyan
        case "leftPupil", "rightPupil": return .yellow
        case "leftEyebrow", "rightEyebrow": return .mint
        case "nose", "noseCrest": return .orange
        case "medianLine": return .white.opacity(0.7)
        case "outerLips", "innerLips": return .pink
        default: return .purple
        }
    }
}

/// 與 `CameraSessionManager` 內眨眼／張嘴邏輯對應。
enum FaceExpressionTriggerMode {
    case blink
    case mouthOpen
}

struct FaceExpressionDebugState: Equatable {
    var mode: FaceExpressionTriggerMode
    var eyeAspectRatio: CGFloat?
    var blinkBaselineEAR: CGFloat?
    var blinkClosedThreshold: CGFloat?
    var blinkReopenThreshold: CGFloat?
    var mouthOpenRatio: CGFloat?
    var mouthOpenThreshold: CGFloat?
}


final class CameraSessionManager: NSObject, ObservableObject {
    nonisolated(unsafe) static let shared = CameraSessionManager()
    
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var faceLandmarkDebugSnapshot: FaceLandmarkDebugSnapshot?
    @Published private(set) var expressionDebugState: FaceExpressionDebugState?

    var isFaceLandmarkDebugEnabled = false {
        didSet {
            if !isFaceLandmarkDebugEnabled {
                if Thread.isMainThread {
                    faceLandmarkDebugSnapshot = nil
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.faceLandmarkDebugSnapshot = nil
                    }
                }
            }
        }
    }

    var isFaceAnalysisEnabled = false {
        didSet {
            if !isFaceAnalysisEnabled {
                lastBlinkFireTime = 0
                lastMouthFireTime = 0
                wasEyesOpen = true
                wasMouthClosed = true
                blinkBaselineEAR = 0
                blinkHasBaseline = false
                blinkClosedLatch = false
                if Thread.isMainThread {
                    expressionDebugState = nil
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.expressionDebugState = nil
                    }
                }
            }
        }
    }

    var onExpressionFire: (() -> Void)?

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "recordGame.camera.video", qos: .userInitiated)

    private var lastDebugSnapshotTime: CFAbsoluteTime = 0
    private let debugSnapshotMinInterval: CFAbsoluteTime = 1.0 / 18.0
    private var wasEyesOpen = true
    private var wasMouthClosed = true
    private var lastBlinkFireTime: CFAbsoluteTime = 0
    private var lastMouthFireTime: CFAbsoluteTime = 0
    private let blinkCooldown: CFAbsoluteTime = 0.45
    private let mouthCooldown: CFAbsoluteTime = 0.5
    private var blinkBaselineEAR: CGFloat = 0
    private var blinkHasBaseline = false
    private var blinkClosedLatch = false
    private var lastExpressionDebugPushTime: CFAbsoluteTime = 0
    private let expressionDebugPushMinInterval: CFAbsoluteTime = 1.0 / 15.0

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private var faceExpressionMode: FaceExpressionTriggerMode = .blink

    override private init() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        super.init()
        configureSession()
    }

    func setFaceExpressionMode(_ mode: FaceExpressionTriggerMode) {
        faceExpressionMode = mode
    }

    func syncAuthorizationAndStartPreview() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = status
        }

        switch status {
        case .authorized:
            DispatchQueue.main.async { [weak self] in
                self?.authorizationStatus = .authorized
                self?.startRunning()
            }
        case .notDetermined:
//            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
//                DispatchQueue.main.async {
//                    guard let self else { return }
//                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
//                    if granted { self.startRunning() }
//                }
//            }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                let manager = CameraSessionManager.shared
                manager.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                if granted { manager.startRunning() }
            }
        }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.authorizationStatus = status
                self?.stopRunning()
            }
        @unknown default:
            break
        }
    }

    func refreshAuthorizationAndStartIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = status
            if status == .authorized {
                self?.startRunning()
            } else if status == .denied || status == .restricted {
                self?.stopRunning()
            }
        }
    }

    private func configureSession() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        }

        session.commitConfiguration()
    }

    func startRunning() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopRunning() {
        guard session.isRunning else { return }
        session.stopRunning()
    }
}
extension CameraSessionManager: @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isFaceAnalysisEnabled || isFaceLandmarkDebugEnabled,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let orientation: CGImagePropertyOrientation = .leftMirrored
        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            guard let self else { return }
            let results = (request.results as? [VNFaceObservation]) ?? []

            if self.isFaceAnalysisEnabled, let face = results.first {
                self.process(face: face)
            }

            if self.isFaceLandmarkDebugEnabled {
                let snap = self.buildLandmarkDebugSnapshot(faces: results, imageWidth: width, imageHeight: height)
                DispatchQueue.main.async {
                    let now = CACurrentMediaTime()
                    if now - self.lastDebugSnapshotTime >= self.debugSnapshotMinInterval {
                        self.lastDebugSnapshotTime = now
                        self.faceLandmarkDebugSnapshot = snap
                    }
                }
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([request])
    }

    private func buildLandmarkDebugSnapshot(faces: [VNFaceObservation], imageWidth: Int, imageHeight: Int) -> FaceLandmarkDebugSnapshot {
        let infos: [FaceDebugFaceInfo] = faces.enumerated().map { index, obs in
            FaceDebugFaceInfo(
                index: index,
                confidence: obs.confidence,
                boundingBoxVisionNormalized: obs.boundingBox,
                rollRadians: obs.roll?.doubleValue,
                yawRadians: obs.yaw?.doubleValue,
                regions: Self.landmarkRegions(from: obs),
                eyeAspectRatio: eyeAspectRatio(face: obs),
                mouthOpenRatio: mouthOpenRatio(face: obs)
            )
        }
        return FaceLandmarkDebugSnapshot(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            faces: infos,
            captureTime: CACurrentMediaTime()
        )
    }

    private static func landmarkRegions(from face: VNFaceObservation) -> [FaceDebugRegion] {
        guard let lm = face.landmarks else { return [] }
        let pairs: [(String, VNFaceLandmarkRegion2D?)] = [
            ("faceContour", lm.faceContour),
            ("leftEyebrow", lm.leftEyebrow),
            ("rightEyebrow", lm.rightEyebrow),
            ("leftEye", lm.leftEye),
            ("rightEye", lm.rightEye),
            ("leftPupil", lm.leftPupil),
            ("rightPupil", lm.rightPupil),
            ("nose", lm.nose),
            ("noseCrest", lm.noseCrest),
            ("medianLine", lm.medianLine),
            ("outerLips", lm.outerLips),
            ("innerLips", lm.innerLips),
        ]
        let closedNames: Set<String> = [
            "faceContour", "leftEye", "rightEye", "leftEyebrow", "rightEyebrow",
            "outerLips", "innerLips", "leftPupil", "rightPupil",
        ]
        let bbox = face.boundingBox
        return pairs.compactMap { name, region -> FaceDebugRegion? in
            guard let region, region.pointCount > 0 else { return nil }
            var pts: [CGPoint] = []
            pts.reserveCapacity(region.pointCount)
            for i in 0..<region.pointCount {
                let p = region.normalizedPoints[i]
                pts.append(CGPoint(x: bbox.origin.x + p.x * bbox.width, y: bbox.origin.y + p.y * bbox.height))
            }
            return FaceDebugRegion(name: name, pointsVisionNormalized: pts, isClosedPath: closedNames.contains(name))
        }
    }

    private func process(face: VNFaceObservation) {
        let now = CFAbsoluteTimeGetCurrent()

        switch faceExpressionMode {
        case .blink:
            let ear = eyeAspectRatio(face: face)
            guard ear > 0.01 else { return }

            if !blinkHasBaseline {
                blinkBaselineEAR = ear
                blinkHasBaseline = true
            } else if !blinkClosedLatch {
                // 只在非閉眼狀態更新基準，避免把閉眼值學進去。
                let alpha: CGFloat = 0.08
                blinkBaselineEAR = blinkBaselineEAR * (1 - alpha) + ear * alpha
            }

            let closedThreshold = blinkBaselineEAR * 0.72
            let reopenThreshold = blinkBaselineEAR * 0.90
            let eyesClosed = ear < closedThreshold
            let eyesReopened = ear > reopenThreshold

            if !blinkClosedLatch && eyesClosed {
                blinkClosedLatch = true
                if now - lastBlinkFireTime >= blinkCooldown {
                    lastBlinkFireTime = now
                    DispatchQueue.main.async { [weak self] in
                        self?.onExpressionFire?()
                    }
                }
            } else if blinkClosedLatch && eyesReopened {
                blinkClosedLatch = false
            }
            wasEyesOpen = !blinkClosedLatch
            pushExpressionDebugState(
                now: now,
                state: FaceExpressionDebugState(
                    mode: .blink,
                    eyeAspectRatio: ear,
                    blinkBaselineEAR: blinkBaselineEAR,
                    blinkClosedThreshold: closedThreshold,
                    blinkReopenThreshold: reopenThreshold,
                    mouthOpenRatio: nil,
                    mouthOpenThreshold: nil
                )
            )

        case .mouthOpen:
            let open = mouthOpenRatio(face: face)
            let mouthThreshold: CGFloat = 0.28
            let mouthOpen = open > mouthThreshold
            if wasMouthClosed && mouthOpen {
                if now - lastMouthFireTime >= mouthCooldown {
                    lastMouthFireTime = now
                    DispatchQueue.main.async { [weak self] in
                        self?.onExpressionFire?()
                    }
                }
            }
            wasMouthClosed = !mouthOpen
            pushExpressionDebugState(
                now: now,
                state: FaceExpressionDebugState(
                    mode: .mouthOpen,
                    eyeAspectRatio: nil,
                    blinkBaselineEAR: nil,
                    blinkClosedThreshold: nil,
                    blinkReopenThreshold: nil,
                    mouthOpenRatio: open,
                    mouthOpenThreshold: mouthThreshold
                )
            )
        }
    }

    private func pushExpressionDebugState(now: CFAbsoluteTime, state: FaceExpressionDebugState) {
        guard now - lastExpressionDebugPushTime >= expressionDebugPushMinInterval else { return }
        lastExpressionDebugPushTime = now
        DispatchQueue.main.async { [weak self] in
            self?.expressionDebugState = state
        }
    }

    private func eyeAspectRatio(face: VNFaceObservation) -> CGFloat {
        guard let landmarks = face.landmarks else { return 1 }
        let lw = aspectForEye(landmarks.leftEye, in: face)
        let rw = aspectForEye(landmarks.rightEye, in: face)
        if lw == 0 && rw == 0 { return 1 }
        if lw == 0 { return rw }
        if rw == 0 { return lw }
        return (lw + rw) / 2
    }

    private func aspectForEye(_ region: VNFaceLandmarkRegion2D?, in face: VNFaceObservation) -> CGFloat {
        guard let region else { return 0 }
        let bbox = face.boundingBox
        let points = region.normalizedPoints
        guard !points.isEmpty else { return 0 }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0, maxY: CGFloat = 0
        for p in points {
            let x = bbox.origin.x + p.x * bbox.width
            let y = bbox.origin.y + p.y * bbox.height
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        let w = max(maxX - minX, 1e-4)
        let h = max(maxY - minY, 1e-4)
        return h / w
    }

    private func mouthOpenRatio(face: VNFaceObservation) -> CGFloat {
        guard let outer = face.landmarks?.outerLips?.normalizedPoints, outer.count >= 4 else { return 0 }
        let bbox = face.boundingBox
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY: CGFloat = 0
        for p in outer {
            let y = bbox.origin.y + p.y * bbox.height
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        let mouthHeight = maxY - minY
        return mouthHeight / max(bbox.height, 1e-4)
    }
}

// MARK: - UIKit 預覽層

struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        guard let layer = CameraSessionManager.shared.previewLayer else { return view }
        layer.removeFromSuperlayer()
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        CameraSessionManager.shared.isFaceAnalysisEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let layer = CameraSessionManager.shared.previewLayer else { return }
            if layer.superlayer !== uiView.layer {
                layer.removeFromSuperlayer()
                uiView.layer.addSublayer(layer)
            }
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - SwiftUI 背景（權限分支）

struct CameraBackgroundView: View {
    @ObservedObject private var camera = CameraSessionManager.shared
    @Environment(\.openURL) private var openURL
    @State private var showDeniedAlert = false
    private static var didPresentDeniedAlertThisSession = false

    var body: some View {
        ZStack {
            switch camera.authorizationStatus {
            case .authorized:
                CameraPreviewView()
            case .notDetermined:
                placeholder(title: "相機權限", subtitle: "請在系統對話框中選擇是否允許使用相機。", settings: false)
            case .denied, .restricted:
                placeholder(title: "無法使用相機", subtitle: "請到「設定」開啟相機權限。", settings: true)
            @unknown default:
                placeholder(title: "無法使用相機", subtitle: "", settings: true)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            camera.syncAuthorizationAndStartPreview()
            scheduleDeniedAlert()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            camera.refreshAuthorizationAndStartIfNeeded()
        }
        .onChange(of: camera.authorizationStatus) { new in
            if new == .denied || new == .restricted { scheduleDeniedAlert() }
        }
        .alert("需要相機權限", isPresented: $showDeniedAlert) {
            Button("前往設定") { openSettings() }
            Button("關閉", role: .cancel) {}
        } message: {
            Text("設定 → 本 App → 開啟「相機」。")
        }
    }

    private func scheduleDeniedAlert() {
        let s = camera.authorizationStatus
        guard s == .denied || s == .restricted else { return }
        guard !Self.didPresentDeniedAlertThisSession else { return }
        Self.didPresentDeniedAlertThisSession = true
        showDeniedAlert = true
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    @ViewBuilder
    private func placeholder(title: String, subtitle: String, settings: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [CameraUITheme.pageWash, CameraUITheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(CameraUITheme.accent.opacity(0.85))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(CameraUITheme.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CameraUITheme.textSecondary)
                    .padding(.horizontal, 28)
                if settings {
                    Button("前往設定") { openSettings() }
                        .font(.headline)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 12)
                        .background(CameraUITheme.accent)
                        .foregroundStyle(CameraUITheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private enum CameraUITheme {
    static let accent = Color(red: 0.941, green: 0.725, blue: 0.035)
    static let textPrimary = Color(red: 0.118, green: 0.137, blue: 0.161)
    static let textSecondary = Color(red: 0.439, green: 0.478, blue: 0.541)
    static let surface = Color.white
    static let pageWash = Color(red: 0.973, green: 0.976, blue: 0.980)
}

extension CameraSessionManager: @unchecked Sendable {}
