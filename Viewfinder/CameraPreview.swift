import SwiftUI
import AVFoundation

final class CameraPreviewUIView: UIView {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer

    override init(frame: CGRect) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        configureSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.beginConfiguration()
        session.addInput(input)
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
}

struct CameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.stopSession()
    }
}
