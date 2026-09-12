import SwiftUI
import UIKit
import AVFoundation
import Vision
import ImageIO
import CoreVideo

final class PreviewContainerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    deinit {
        if let session = previewLayer?.session, session.isRunning {
            session.stopRunning()
        }
    }
}

final class CameraScannerCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onBarcode: (String) -> Void
    private let queue = DispatchQueue(label: "scan.queue", qos: .userInitiated)
    private var session: AVCaptureSession?

    init(onBarcode: @escaping (String) -> Void) {
        self.onBarcode = onBarcode
    }

    func start(in view: PreviewContainerView) {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        self.session = session
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.previewLayer = layer
        view.layer.addSublayer(layer)

        queue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let orientation = Self.imageOrientation(from: UIDevice.current.orientation)
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        try? handler.perform([request])
        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { continue }
            onBarcode(payload)
        }
    }

    private static func imageOrientation(
        from deviceOrientation: UIDeviceOrientation
    ) -> CGImagePropertyOrientation {
        switch deviceOrientation {
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }
}

struct CameraScannerView: UIViewRepresentable {
    var onBarcode: (String) -> Void

    func makeCoordinator() -> CameraScannerCoordinator {
        CameraScannerCoordinator(onBarcode: onBarcode)
    }

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView(frame: .zero)
        context.coordinator.start(in: view)
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}
}