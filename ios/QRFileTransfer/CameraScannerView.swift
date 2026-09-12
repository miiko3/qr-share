import SwiftUI
import UIKit
import AVFoundation
import Vision

final class PreviewContainerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

final class CameraScannerCoordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onBarcode: (String) -> Void
    private let queue = DispatchQueue(label: "scan.queue", qos: .userInitiated)

    init(onBarcode: @escaping (String) -> Void) {
        self.onBarcode = onBarcode
    }

    func start(in view: PreviewContainerView) {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.previewLayer = layer
        view.layer.addSublayer(layer)

        session.startRunning()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { continue }
            onBarcode(payload)
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