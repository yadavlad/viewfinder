import SwiftUI
import AVFoundation

final class Camera: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    override init() {
        super.init()
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput)
        else { return }

        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()

        Task.detached { [session] in
            session.startRunning()
        }
    }

    func stopSession() {
        Task.detached { [session] in
            session.stopRunning()
        }
    }

    func capture() async -> UIImage? {
        await withCheckedContinuation { continuation in
            photoContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }
}

extension Camera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}

final class CameraPreviewUIView: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(camera: Camera) {
        previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: Camera

    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView(camera: camera)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
