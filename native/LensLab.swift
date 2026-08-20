import SwiftUI
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import UIKit

// MARK: - Camera Controller (built-in iPad camera + external UVC capture card / DSLR)

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var session = AVCaptureSession()
    @Published var devices: [AVCaptureDevice] = []
    @Published var activeDevice: AVCaptureDevice?
    @Published var capturedCIImage: CIImage?
    @Published var isRunning = false
    @Published var message: String?

    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private let queue = DispatchQueue(label: "lenslab.camera")

    override init() {
        super.init()
        discoverDevices()
    }

    func discoverDevices() {
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        ).devices

        // UVC / capture card (HDMI -> USB-C) appears as an external device on iPadOS
        let external = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices

        devices = external + builtIn
        if activeDevice == nil { activeDevice = devices.first }
    }

    func select(_ device: AVCaptureDevice) {
        activeDevice = device
        restart()
    }

    func start() {
        queue.async { self.configure() }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func restart() {
        queue.async { self.configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let input = input {
            session.removeInput(input)
            self.input = nil
        }

        if let device = activeDevice,
           let newInput = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
        }

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func capture() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.message = "Chụp lỗi: \(error?.localizedDescription ?? "không rõ")"
            }
            return
        }
        let ci = CIImage(data: data)
        DispatchQueue.main.async { self.capturedCIImage = ci }
    }
}

// MARK: - Live preview (UIViewRepresentable)

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
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

// MARK: - Image processing (Core Image + Vision)

enum ImageProcessor {
    static let context = CIContext()

    static func render(_ input: CIImage,
                       exposure: Double,
                       saturation: Double,
                       warmth: Double,
                       contrast: Double = 1.04,
                       drawFaces: Bool = true) -> UIImage {
        var image = input

        let exp = CIFilter.exposureAdjust()
        exp.inputImage = image
        exp.ev = Float(exposure)
        image = exp.outputImage ?? image

        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = Float(saturation)
        color.contrast = Float(contrast)
        image = color.outputImage ?? image

        if warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = image
            temp.neutral = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: 6500 + CGFloat(warmth), y: 0)
            image = temp.outputImage ?? image
        }

        let boxes = drawFaces ? detectFaces(image) : []

        let cg = context.createCGImage(image, from: image.extent)
        let ui = cg.map { UIImage(cgImage: $0) } ?? UIImage()
        return draw(boxes, on: ui)
    }

    static func detectFaces(_ image: CIImage) -> [CGRect] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).map { $0.boundingBox }
    }

    static func draw(_ boxes: [CGRect], on image: UIImage) -> UIImage {
        guard !boxes.isEmpty else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(at: .zero)
            ctx.cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
            ctx.cgContext.setLineWidth(max(4, image.size.width * 0.004))
            for box in boxes {
                // Vision uses bottom-left origin; flip to top-left for UIKit
                let x = box.origin.x * image.size.width
                let y = (1 - box.origin.y - box.size.height) * image.size.height
                let w = box.size.width * image.size.width
                let h = box.size.height * image.size.height
                ctx.cgContext.stroke(CGRect(x: x, y: y, width: w, height: h))
            }
        }
    }
}

// MARK: - App entry

@main
struct LensLabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Main screen

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @State private var showResult = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let ci = camera.capturedCIImage, showResult {
                ResultView(source: ci) {
                    showResult = false
                    camera.capturedCIImage = nil
                }
            } else {
                liveView
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var liveView: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    devicePicker
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                Spacer()

                shutter
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 16)
        }
    }

    private var devicePicker: some View {
        Menu {
            ForEach(camera.devices, id: \.uniqueID) { device in
                Button(deviceLabel(device)) { camera.select(device) }
            }
        } label: {
            Label(camera.activeDevice.map(deviceLabel) ?? "Chọn camera",
                  systemImage: "camera.fill")
                .font(.subheadline)
                .foregroundStyle(.white)
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
        Button {
            camera.capture()
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(.white).frame(width: 62, height: 62)
            }
        }
    }
}

// MARK: - Result / edit screen

struct ResultView: View {
    let source: CIImage
    var onBack: () -> Void

    @State private var exposure: Double = 0
    @State private var saturation: Double = 1.0
    @State private var warmth: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .padding()
                }
                Spacer()
                Button("Lưu ảnh") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)

            Image(uiImage: ImageProcessor.render(source,
                                                 exposure: exposure,
                                                 saturation: saturation,
                                                 warmth: warmth))
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity)

            VStack(spacing: 8) {
                slider("Phơi sáng", value: $exposure, range: -3...3, step: 0.1)
                slider("Bão hoà", value: $saturation, range: 0...2, step: 0.05)
                slider("Ấm áp", value: $warmth, range: -2000...2000, step: 100)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            Slider(value: value, in: range, step: step)
        }
    }

    private func save() {
        let img = ImageProcessor.render(source,
                                        exposure: exposure,
                                        saturation: saturation,
                                        warmth: warmth,
                                        drawFaces: false)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            }
        }
    }
}
