import SwiftUI
import AVFoundation
import Vision
import CoreImage.CIFilterBuiltins

struct ContentView: View {
    @State private var isAuthorized = false
    @State private var isDenied = false
    @State private var camera = Camera()
    @State private var photo: UIImage?
    @State private var isCapturing = false

    var body: some View {
        Group {
            if isAuthorized {
                ZStack {
                    if let photo {
                        DebugMaskView(photo: photo) {
                            self.photo = nil
                        }
                    } else {
                        CameraPreview(camera: camera)
                            .ignoresSafeArea()

                        GeometryReader { geometry in
                            CrosshairIcon()
                                .position(crosshairCenter(in: geometry.size))
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                        VStack {
                            Spacer()
                            Button {
                                isCapturing = true
                                Task {
                                    photo = await camera.capture()
                                    isCapturing = false
                                }
                            } label: {
                                ShutterButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(isCapturing)
                            .accessibilityLabel("Take photo")
                            .padding(.bottom, 24)
                        }
                    }
                }
            } else if isDenied {
                Text("Camera access denied")
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .task {
            await requestAccessIfNeeded()
        }
    }

    private func requestAccessIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            isDenied = !granted
        default:
            isDenied = true
        }
    }
}

/// Crosshair position, shared by the crosshair and the whitening center.
/// `size` must come from a full-screen (ignoresSafeArea) geometry.
private func crosshairCenter(in size: CGSize) -> CGPoint {
    CGPoint(x: size.width / 2, y: size.height / 2 - size.height * 0.05)
}

/// Debug screen: shows the photo with the foreground instance under the crosshair tinted red.
private struct DebugMaskView: View {
    let photo: UIImage
    let onTap: () -> Void
    @State private var tint: UIImage?
    @State private var isProcessing = true

    var body: some View {
        GeometryReader { geometry in
            let center = crosshairCenter(in: geometry.size)

            ZStack {
                filled(photo)

                if let tint {
                    filled(tint)
                }

                CrosshairIcon()
                    .position(center)
                    .accessibilityHidden(true)

                if isProcessing {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.75)
                }
            }
            .task {
                let size = geometry.size
                tint = await Task.detached {
                    InstanceTinter.tint(photo: photo, viewSize: size, crosshair: center)
                }.value
                isProcessing = false
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Return to camera")
        .accessibilityAddTraits(.isButton)
    }

    /// Same scaledToFill + clip layout for the photo and the tint, so they stay aligned.
    private func filled(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }
}

private enum InstanceTinter {
    /// Returns a 50% red overlay (same pixel size and aspect as the upright photo) covering the
    /// foreground instance under `crosshair`, or nil if that point is background or Vision fails.
    /// `viewSize` is the full-screen size the photo is shown in with scaledToFill.
    static func tint(photo: UIImage, viewSize: CGSize, crosshair: CGPoint) -> UIImage? {
        // Bake the orientation flag into the pixels so Vision and the view agree on "up".
        let pixelSize = CGSize(width: photo.size.width * photo.scale, height: photo.size.height * photo.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        guard let cgImage = upright.cgImage else { return nil }

        // Crosshair in photo pixels, undoing the scaledToFill scale and center crop.
        let scale = max(viewSize.width / pixelSize.width, viewSize.height / pixelSize.height)
        let offsetX = (viewSize.width - pixelSize.width * scale) / 2
        let offsetY = (viewSize.height - pixelSize.height * scale) / 2
        let px = (crosshair.x - offsetX) / scale
        let py = (crosshair.y - offsetY) / scale
        guard px >= 0, py >= 0, px < pixelSize.width, py < pixelSize.height else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first
        else { return nil }

        // The label map may have a different resolution than the photo; sample it normalized.
        let labels = observation.instanceMask
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let lx = min(Int(px / pixelSize.width * CGFloat(CVPixelBufferGetWidth(labels))), CVPixelBufferGetWidth(labels) - 1)
        let ly = min(Int(py / pixelSize.height * CGFloat(CVPixelBufferGetHeight(labels))), CVPixelBufferGetHeight(labels) - 1)
        let label = Int(base.load(fromByteOffset: ly * CVPixelBufferGetBytesPerRow(labels) + lx, as: UInt8.self))
        guard label != 0 else { return nil }

        guard let mask = try? observation.generateScaledMaskForImage(forInstances: IndexSet(integer: label), from: handler) else {
            return nil
        }
        let maskImage = CIImage(cvPixelBuffer: mask)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5)).cropped(to: maskImage.extent)
        filter.backgroundImage = CIImage(color: .clear).cropped(to: maskImage.extent)
        filter.maskImage = maskImage
        guard let output = filter.outputImage,
              let result = CIContext().createCGImage(output, from: maskImage.extent)
        else { return nil }
        return UIImage(cgImage: result)
    }
}

private struct ShutterButton: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white, lineWidth: 4)
                .frame(width: 72, height: 72)
            Circle()
                .fill(.white)
                .frame(width: 60, height: 60)
        }
    }
}

private struct CrosshairIcon: View {
    var body: some View {
        ZStack {
            Capsule()
                .frame(width: 9, height: 40)
                .offset(y: -26)
            Capsule()
                .frame(width: 9, height: 40)
                .offset(y: 26)
            Capsule()
                .frame(width: 37, height: 9)
                .offset(x: -25, y: -0.5)
            Capsule()
                .frame(width: 37, height: 9)
                .offset(x: 25, y: -0.5)
        }
        .foregroundStyle(.white)
        .frame(width: 87, height: 92)
    }
}

#Preview {
    ContentView()
}
