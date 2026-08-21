import SwiftUI
import Foundation
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Photos
import UIKit

// MARK: - Camera Controller (built-in iPad camera + external UVC capture card / DSLR)

@MainActor
final class CameraController: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var devices: [AVCaptureDevice] = []
    @Published var activeDevice: AVCaptureDevice?
    @Published var latestFrame: CIImage?
    @Published var capturedCIImage: CIImage?
    @Published var isRunning = false
    @Published var message: String?

    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var captureRequested = false
    private let queue = DispatchQueue(label: "lenslab.camera")

    override init() {
        super.init()
    }

    func discoverDevices() {
        var all: [AVCaptureDevice] = []

        // External / capture card (iPadOS 17+)
        let external = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices
        all.append(contentsOf: external)

        // Built-in cameras
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        all.append(contentsOf: builtIn)

        devices = all
        if activeDevice == nil { activeDevice = devices.first }
    }

    func select(_ device: AVCaptureDevice) {
        activeDevice = device
        restart()
    }

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            discoverDevices()
            queue.async { [weak self] in self?.configure() }
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                Task { @MainActor in
                    if granted {
                        self.discoverDevices()
                        self.queue.async { [weak self] in self?.configure() }
                    } else {
                        self.message = "Chưa cấp quyền Camera.\nVào Cài đặt → Quyền riêng tư → Camera."
                    }
                }
            }
        } else {
            message = "Camera bị từ chối.\nVào Cài đặt iPad → Quyền riêng tư → Camera."
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func restart() {
        queue.async { [weak self] in self?.configure() }
    }

    private func configure() {
        if activeDevice == nil {
            Task { @MainActor in discoverDevices() }
        }
        let device = activeDevice
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)

        session.beginConfiguration()
        session.sessionPreset = .high

        if let oldInput = input {
            session.removeInput(oldInput)
            self.input = nil
        }

        if let device = device,
           let newInput = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Set delegate on a serial queue for frame capture
        let delegate = FrameDelegate { [weak self] ci in
            guard let self else { return }
            Task { @MainActor in
                self.latestFrame = ci
                if self.captureRequested {
                    self.captureRequested = false
                    self.capturedCIImage = ci
                }
            }
        }
        videoOutput.setSampleBufferDelegate(delegate, queue: queue)
        // Keep delegate alive
        objc_setAssociatedObject(videoOutput, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
            Task { @MainActor in self.isRunning = true }
        }
    }

    func capture() {
        captureRequested = true
    }
}

// Separate delegate class to avoid Sendable issues
final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let handler: @Sendable (CIImage) -> Void

    init(handler: @escaping @Sendable (CIImage) -> Void) {
        self.handler = handler
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pb)
        handler(ci)
    }
}

// MARK: - Live preview

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

// MARK: - LUT presets

enum LUTPreset: String, CaseIterable, Identifiable {
    case none = "Không"
    case warm = "Ấm"
    case cool = "Mát"
    case fuji = "Fuji"
    case vivid = "Vivid"
    case bw = "Đen trắng"
    var id: String { rawValue }
}

// MARK: - Image processing (Core Image + Vision)

enum ImageProcessor {
    static let context = CIContext()

    struct Adjustments {
        var exposure: Double = 0
        var contrast: Double = 1.0
        var saturation: Double = 1.0
        var warmth: Double = 0
        var vibrance: Double = 0
        var highlights: Double = 0
        var shadows: Double = 0
        var skinSmooth: Double = 0
        var backgroundBlur: Double = 0
        var removeBackground: Bool = false
        var lut: LUTPreset = .none
        var lutIntensity: Double = 0.8
    }

    static func render(_ input: CIImage, adj: Adjustments, drawFaces: Bool = true) -> UIImage {
        var image = input

        image = applyAdjustments(image, adj: adj)
        image = applyLUT(image, adj: adj)
        if adj.removeBackground {
            image = applyBackgroundRemove(image)
        } else if adj.backgroundBlur > 0.001 {
            image = applyBackgroundBlur(image, amount: Float(adj.backgroundBlur))
        }
        let boxes = detectFaces(image)
        image = applySkinSmooth(image, boxes: boxes, amount: Float(adj.skinSmooth))

        guard let cg = context.createCGImage(image, from: image.extent) else {
            return UIImage()
        }
        let ui = UIImage(cgImage: cg)
        return drawFaces ? draw(boxes, on: ui) : ui
    }

    // MARK: adjustments

    static func applyAdjustments(_ image: CIImage, adj: Adjustments) -> CIImage {
        var out = image

        let exp = CIFilter.exposureAdjust()
        exp.inputImage = out
        exp.ev = Float(adj.exposure)
        out = exp.outputImage ?? out

        let color = CIFilter.colorControls()
        color.inputImage = out
        color.saturation = Float(adj.saturation)
        color.contrast = Float(adj.contrast)
        out = color.outputImage ?? out

        if adj.warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = out
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 + CGFloat(adj.warmth), y: 0)
            out = temp.outputImage ?? out
        }

        if adj.vibrance != 0 {
            let vib = CIFilter.vibrance()
            vib.inputImage = out
            vib.amount = Float(adj.vibrance)
            out = vib.outputImage ?? out
        }

        if adj.highlights != 0 || adj.shadows != 0 {
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = out
            hs.highlightAmount = Float(adj.highlights)
            hs.shadowAmount = Float(adj.shadows)
            out = hs.outputImage ?? out
        }

        return out
    }

    // MARK: LUT

    static func applyLUT(_ image: CIImage, adj: Adjustments) -> CIImage {
        guard adj.lut != .none else { return image }
        let cube = CIFilter.colorCube()
        cube.inputImage = image
        cube.cubeDimension = 33
        cube.cubeData = lutCube(adj.lut)

        guard let lutOut = cube.outputImage else { return image }
        if adj.lutIntensity >= 0.999 { return lutOut }

        let mix = CIFilter.mix()
        mix.inputImage = lutOut
        mix.backgroundImage = image
        mix.amount = Float(adj.lutIntensity)
        return mix.outputImage ?? image
    }

    static func lutCube(_ preset: LUTPreset, dimension: Int = 33) -> Data {
        var data = Data(capacity: dimension * dimension * dimension * 4 * 4)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let fr = Float(r) / Float(dimension - 1)
                    let fg = Float(g) / Float(dimension - 1)
                    let fb = Float(b) / Float(dimension - 1)
                    let (R, G, B) = applyPreset(preset, r: fr, g: fg, b: fb)
                    appendFloat(&data, R)
                    appendFloat(&data, G)
                    appendFloat(&data, B)
                    appendFloat(&data, 1)
                }
            }
        }
        return data
    }

    static func applyPreset(_ preset: LUTPreset, r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        func clamp(_ v: Float) -> Float { max(0, min(1, v)) }
        switch preset {
        case .none:
            return (r, g, b)
        case .warm:
            return (clamp(r * 1.08), clamp(g * 1.02), clamp(b * 0.90))
        case .cool:
            return (clamp(r * 0.92), clamp(g * 1.02), clamp(b * 1.10))
        case .fuji:
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            let rr = clamp(luma + (r - luma) * 1.06 + 0.02)
            let gg = clamp(luma + (g - luma) * 1.04)
            let bb = clamp(luma + (b - luma) * 1.10)
            return (rr, gg, bb)
        case .vivid:
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            return (clamp(luma + (r - luma) * 1.25),
                    clamp(luma + (g - luma) * 1.25),
                    clamp(luma + (b - luma) * 1.25))
        case .bw:
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            return (luma, luma, luma)
        }
    }

    static func appendFloat(_ data: inout Data, _ value: Float) {
        var v = value
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    // MARK: face detection

    static func detectFaces(_ image: CIImage) -> [CGRect] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).map { $0.boundingBox }
    }

    // MARK: person segmentation (on-device Core ML via Vision)

    static func personMask(_ image: CIImage) -> CIImage? {
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first, let buffer = result.pixelBuffer else { return nil }
            var mask = CIImage(cvPixelBuffer: buffer)
            let sx = image.extent.width / mask.extent.width
            let sy = image.extent.height / mask.extent.height
            if sx != 1 || sy != 1 {
                mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            }
            return mask
        } catch {
            return nil
        }
    }

    static func applyBackgroundBlur(_ image: CIImage, amount: Float) -> CIImage {
        guard let mask = personMask(image) else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = max(2, amount * 24)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = blur.outputImage
        blend.maskImage = mask
        return blend.outputImage ?? image
    }

    static func applyBackgroundRemove(_ image: CIImage) -> CIImage {
        guard let mask = personMask(image) else { return image }
        let clear = CIImage(color: CIColor.clear).cropped(to: image.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = clear
        blend.maskImage = mask
        return blend.outputImage ?? image
    }

    // MARK: skin smoothing (masked gaussian blur on face region)

    static func applySkinSmooth(_ image: CIImage, boxes: [CGRect], amount: Float) -> CIImage {
        guard !boxes.isEmpty, amount > 0.001 else { return image }
        let size = image.extent.size

        guard let mask = makeFaceMask(size: size, boxes: boxes) else { return image }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = max(1.5, amount * 8)

        let softMask = CIFilter.gaussianBlur()
        softMask.inputImage = mask
        softMask.radius = max(3, amount * 12)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blur.outputImage
        blend.backgroundImage = image
        blend.maskImage = softMask.outputImage
        return blend.outputImage ?? image
    }

    static func makeFaceMask(size: CGSize, boxes: [CGRect]) -> CIImage? {
        let width = Int(size.width), height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for box in boxes {
            let cx = box.midX * size.width
            let cy = box.midY * size.height
            let rx = box.width * size.width * 0.35
            let ry = box.height * size.height * 0.45
            ctx.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }

    // MARK: face boxes overlay

    static func draw(_ boxes: [CGRect], on image: UIImage) -> UIImage {
        guard !boxes.isEmpty else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)
            ctx.cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
            ctx.cgContext.setLineWidth(max(4, image.size.width * 0.004))
            for box in boxes {
                let x = box.origin.x * image.size.width
                let y = (1 - box.origin.y - box.size.height) * image.size.height
                let w = box.size.width * image.size.width
                let h = box.size.height * image.size.height
                ctx.cgContext.stroke(CGRect(x: x, y: y, width: w, height: h))
            }
        }
    }
}

// MARK: - AI Cloud settings

final class AISettings: ObservableObject {
    @Published var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: "aiToken") }
    }
    @Published var modelVersion: String {
        didSet { UserDefaults.standard.set(modelVersion, forKey: "aiVersion") }
    }
    @Published var endpoint: String {
        didSet { UserDefaults.standard.set(endpoint, forKey: "aiEndpoint") }
    }

    init() {
        apiToken = UserDefaults.standard.string(forKey: "aiToken") ?? ""
        modelVersion = UserDefaults.standard.string(forKey: "aiVersion") ?? ""
        endpoint = UserDefaults.standard.string(forKey: "aiEndpoint") ?? "https://api.replicate.com/v1/predictions"
    }
}

// MARK: - AI Cloud client (Replicate-compatible)

enum AICloudError: LocalizedError {
    case noConfig, invalidImage, badResponse, failed, timeout, noOutput
    var errorDescription: String? {
        switch self {
        case .noConfig: return "Chưa nhập API token / model version trong Cài đặt AI."
        case .invalidImage: return "Không tạo được dữ liệu ảnh."
        case .badResponse: return "Phản hồi API không hợp lệ."
        case .failed: return "Model AI trả về lỗi."
        case .timeout: return "AI xử lý quá lâu (timeout)."
        case .noOutput: return "AI không trả về ảnh kết quả."
        }
    }
}

enum AICloudClient {
    static func retouch(image: UIImage, settings: AISettings) async throws -> UIImage {
        guard !settings.apiToken.isEmpty, !settings.modelVersion.isEmpty else {
            throw AICloudError.noConfig
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.92) else {
            throw AICloudError.invalidImage
        }
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        let body: [String: Any] = [
            "version": settings.modelVersion,
            "input": ["image": dataURL]
        ]

        var request = URLRequest(url: URL(string: settings.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw AICloudError.badResponse
        }

        // Poll for completion
        for _ in 0..<90 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let pollURL = URL(string: settings.endpoint + "/" + id)!
            var pollReq = URLRequest(url: pollURL)
            pollReq.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
            let (pollData, _) = try await URLSession.shared.data(for: pollReq)
            guard let pollJson = try JSONSerialization.jsonObject(with: pollData) as? [String: Any],
                  let status = pollJson["status"] as? String else { continue }

            if status == "succeeded" {
                if let out = pollJson["output"] as? String, let url = URL(string: out) {
                    let (imgData, _) = try await URLSession.shared.data(from: url)
                    if let img = UIImage(data: imgData) { return img }
                }
                throw AICloudError.noOutput
            }
            if status == "failed" || status == "canceled" {
                throw AICloudError.failed
            }
        }
        throw AICloudError.timeout
    }
}

// MARK: - Photo Library helper

enum PhotoLibraryHelper {
    static func save(image: UIImage, isPNG: Bool = false) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            if isPNG, let png = image.pngData() {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("lenslab-\(Int(Date().timeIntervalSince1970)).png")
                try? png.write(to: url)
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            } else {
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }
        }
    }
}

// MARK: - App entry

@main
struct LensLabApp: App {
    @StateObject private var aiSettings = AISettings()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(aiSettings)
        }
    }
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var showResult = false
    @State private var showSettings = false
    @State private var showPhotosPicker = false
    @State private var pickedImage: CIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let ci = camera.capturedCIImage, showResult {
                ResultView(source: ci) {
                    showResult = false
                    camera.capturedCIImage = nil
                }
            } else if let ci = pickedImage, showResult {
                ResultView(source: ci) {
                    showResult = false
                    pickedImage = nil
                }
            } else {
                liveView
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: camera.capturedCIImage) { _, newValue in
            if newValue != nil { showResult = true }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var liveView: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()

            VStack {
                HStack {
                    devicePicker.padding(8).background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill").font(.title3).padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
                Spacer()

                HStack(spacing: 40) {
                    // Photo library picker
                    Button {
                        showPhotosPicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .sheet(isPresented: $showPhotosPicker) {
                        PhotoPickerView { image in
                            if let ci = CIImage(image: image) {
                                pickedImage = ci
                                showResult = true
                            }
                            showPhotosPicker = false
                        }
                    }

                    shutter

                    // Refresh camera
                    Button {
                        camera.discoverDevices()
                        camera.restart()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 16)

            if let msg = camera.message {
                VStack {
                    Text(msg)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
            }
        }
    }

    private var devicePicker: some View {
        Menu {
            ForEach(camera.devices, id: \.uniqueID) { device in
                Button(deviceLabel(device)) { camera.select(device) }
            }
            Divider()
            Button("🔄 Tìm lại camera") {
                camera.discoverDevices()
                camera.restart()
            }
        } label: {
            Label(camera.activeDevice.map(deviceLabel) ?? "Chọn camera",
                  systemImage: "camera.fill").font(.subheadline).foregroundStyle(.white)
        }
    }

    private func deviceLabel(_ device: AVCaptureDevice) -> String {
        switch device.position {
        case .back: return "📷 Sau — \(device.localizedName)"
        case .front: return "🤳 Trước — \(device.localizedName)"
        default: return "🎥 \(device.localizedName) (Capture card)"
        }
    }

    private var shutter: some View {
        Button { camera.capture() } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(.white).frame(width: 62, height: 62)
            }
        }
    }
}

// MARK: - Photo picker (UIImagePickerController wrapper for compatibility)

struct PhotoPickerView: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                onPick(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Result / edit screen

struct ResultView: View {
    @EnvironmentObject private var aiSettings: AISettings
    let source: CIImage
    var onBack: () -> Void

    @State private var adj = ImageProcessor.Adjustments()
    @State private var isProcessingAI = false
    @State private var aiResult: UIImage?
    @State private var aiError: String?
    @State private var savedToast = false

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            if isLandscape {
                HStack(spacing: 0) {
                    imagePreview.frame(maxWidth: geo.size.width * 0.65)
                    controlsPanel
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    imagePreview.frame(maxHeight: geo.size.height * 0.45)
                    controlsPanel
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
        .overlay(alignment: .bottom) {
            if savedToast {
                Text("✅ Đã lưu ảnh vào Photos!")
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.title2).padding()
            }
            Spacer()
            Button("Lưu ảnh") { save() }.buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
    }

    private var imagePreview: some View {
        Image(uiImage: displayImage)
            .resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.title2)
                    }
                    Spacer()
                    Button("💾 Lưu ảnh") { save() }.buttonStyle(.borderedProminent)
                }

                Text("Điều chỉnh").font(.headline)
                slider("Phơi sáng", value: $adj.exposure, range: -3...3, step: 0.1)
                slider("Tương phản", value: $adj.contrast, range: 0.5...1.5, step: 0.02)
                slider("Bão hoà", value: $adj.saturation, range: 0...2, step: 0.05)
                slider("Ấm áp", value: $adj.warmth, range: -2000...2000, step: 100)
                slider("Vibrance", value: $adj.vibrance, range: -1...1, step: 0.05)
                slider("Highlights", value: $adj.highlights, range: -1...1, step: 0.05)
                slider("Shadows", value: $adj.shadows, range: -1...1, step: 0.05)

                Divider()
                Text("Làm đẹp").font(.headline)
                slider("Làm mịn da", value: $adj.skinSmooth, range: 0...1, step: 0.05)

                Divider()
                Text("Nền (AI on-device)").font(.headline)
                Toggle("Xoá nền (trong suốt)", isOn: $adj.removeBackground)
                if !adj.removeBackground {
                    slider("Làm mờ nền", value: $adj.backgroundBlur, range: 0...1, step: 0.05)
                }

                Divider()
                Text("LUT").font(.headline)
                Picker("LUT", selection: $adj.lut) {
                    ForEach(LUTPreset.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                slider("Cường độ LUT", value: $adj.lutIntensity, range: 0...1, step: 0.05)

                Divider()
                Text("AI Cloud").font(.headline)
                Button {
                    runAI()
                } label: {
                    if isProcessingAI {
                        HStack { Spacer(); ProgressView(); Text("AI đang xử lý…"); Spacer() }
                    } else {
                        Text("✨ Retouch bằng AI (Cloud)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessingAI)

                if aiResult != nil {
                    Button("Xoá kết quả AI") { aiResult = nil }.font(.caption)
                }
                if let aiError {
                    Text(aiError).font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var displayImage: UIImage {
        aiResult ?? ImageProcessor.render(source, adj: adj, drawFaces: false)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            Slider(value: value, in: range, step: step)
        }
    }

    private func runAI() {
        let base = aiResult ?? ImageProcessor.render(source, adj: adj, drawFaces: false)
        isProcessingAI = true
        aiError = nil
        Task {
            do {
                let result = try await AICloudClient.retouch(image: base, settings: aiSettings)
                aiResult = result
                isProcessingAI = false
            } catch {
                aiError = error.localizedDescription
                isProcessingAI = false
            }
        }
    }

    private func save() {
        let img = aiResult ?? ImageProcessor.render(source, adj: adj, drawFaces: false)
        PhotoLibraryHelper.save(image: img, isPNG: adj.removeBackground)
        withAnimation { savedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { savedToast = false }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var aiSettings: AISettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Cloud (Replicate)") {
                    TextField("API token", text: $aiSettings.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model version (dán từ Replicate)", text: $aiSettings.modelVersion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Endpoint", text: $aiSettings.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section(footer: Text("Lấy token và version model tại replicate.com. Model gợi ý: sczhou/codeformer (phục hồi/retouch khuôn mặt).")) {
                    EmptyView()
                }
            }
            .navigationTitle("Cài đặt AI")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
    }
}
