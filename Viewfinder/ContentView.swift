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
    /// A chosen instance, with the Vision objects needed to render its mask.
    private struct Pick {
        let observation: VNInstanceMaskObservation
        let handler: VNImageRequestHandler
        let label: Int
    }

    /// Returns a 50% red overlay (same pixel size as the upright photo) covering the picked
    /// foreground instance, or nil if nothing was picked or Vision fails.
    ///
    /// Pick rule (see `pick(in:ovalCenter:ovalRadii:)`) uses an oval centered on `crosshair`
    /// with horizontal radius 10% and vertical radius 25% of the screen width. It first runs on
    /// the full photo; if that picks nothing, or the pick touches a screen edge, it runs once
    /// more on the oval's bounding rectangle and prefers that result when it finds one.
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

        // The oval in photo pixels.
        let ovalCenter = CGPoint(x: px, y: py)
        let ovalRadii = CGSize(width: viewSize.width * 0.10 / scale, height: viewSize.width * 0.25 / scale)

        // Pass 1: the full photo.
        var chosen: (pick: Pick, origin: CGPoint)?
        let fullPick = pick(in: cgImage, ovalCenter: ovalCenter, ovalRadii: ovalRadii)
        if let fullPick {
            chosen = (fullPick, .zero)
        }

        // Pass 2: only if pass 1 picked nothing or its pick touches a screen edge.
        let needsCrop = fullPick.map {
            touchesScreenEdge($0, imageSize: pixelSize, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), viewSize: viewSize)
        } ?? true
        if needsCrop {
            let imageRect = CGRect(origin: .zero, size: pixelSize)
            let cropRect = CGRect(
                x: px - ovalRadii.width, y: py - ovalRadii.height,
                width: ovalRadii.width * 2, height: ovalRadii.height * 2
            ).integral.intersection(imageRect)
            if !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1,
               let crop = cgImage.cropping(to: cropRect),
               let cropPick = pick(
                   in: crop,
                   ovalCenter: CGPoint(x: px - cropRect.minX, y: py - cropRect.minY),
                   ovalRadii: ovalRadii
               ) {
                chosen = (cropPick, cropRect.origin)
            }
        }

        guard let (picked, origin) = chosen,
              let mask = try? picked.observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: picked.label), from: picked.handler
              )
        else { return nil }

        // Red where the whole instance is (not just inside the oval), clear elsewhere.
        let maskImage = CIImage(cvPixelBuffer: mask)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5)).cropped(to: maskImage.extent)
        filter.backgroundImage = CIImage(color: .clear).cropped(to: maskImage.extent)
        filter.maskImage = maskImage
        guard let output = filter.outputImage,
              let result = CIContext().createCGImage(output, from: maskImage.extent)
        else { return nil }

        // Place the tint at its position in a photo-sized canvas (a crop pick isn't at the origin).
        let canvasFormat = UIGraphicsImageRendererFormat()
        canvasFormat.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: canvasFormat).image { _ in
            UIImage(cgImage: result).draw(at: origin)
        }
    }

    /// Runs Vision's foreground instance mask on `image` and applies the pick rule: the instance
    /// at `ovalCenter`; if that point is background, the instance with the most pixels inside the
    /// oval (`ovalRadii`, in `image` pixels); if none is inside the oval, nil.
    private static func pick(in image: CGImage, ovalCenter: CGPoint, ovalRadii: CGSize) -> Pick? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first
        else { return nil }

        // The label map (0 = background) may have a different resolution than the image.
        let labels = observation.instanceMask
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let labelsWidth = CVPixelBufferGetWidth(labels)
        let labelsHeight = CVPixelBufferGetHeight(labels)
        let rowBytes = CVPixelBufferGetBytesPerRow(labels)
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        func label(x: Int, y: Int) -> Int {
            Int(base.load(fromByteOffset: y * rowBytes + x, as: UInt8.self))
        }

        // 1. The instance under the center point.
        if ovalCenter.x >= 0, ovalCenter.y >= 0, ovalCenter.x < imageWidth, ovalCenter.y < imageHeight {
            let centerLabel = label(
                x: min(Int(ovalCenter.x / imageWidth * CGFloat(labelsWidth)), labelsWidth - 1),
                y: min(Int(ovalCenter.y / imageHeight * CGFloat(labelsHeight)), labelsHeight - 1)
            )
            if centerLabel != 0 {
                return Pick(observation: observation, handler: handler, label: centerLabel)
            }
        }

        // 2. The instance with the most label-map pixels whose centers are inside the oval.
        let x0 = max(0, Int(floor((ovalCenter.x - ovalRadii.width) / imageWidth * CGFloat(labelsWidth))))
        let x1 = min(labelsWidth - 1, Int(ceil((ovalCenter.x + ovalRadii.width) / imageWidth * CGFloat(labelsWidth))))
        let y0 = max(0, Int(floor((ovalCenter.y - ovalRadii.height) / imageHeight * CGFloat(labelsHeight))))
        let y1 = min(labelsHeight - 1, Int(ceil((ovalCenter.y + ovalRadii.height) / imageHeight * CGFloat(labelsHeight))))
        guard x0 <= x1, y0 <= y1 else { return nil }

        var counts = [Int](repeating: 0, count: 256)
        for y in y0...y1 {
            let dy = ((CGFloat(y) + 0.5) / CGFloat(labelsHeight) * imageHeight - ovalCenter.y) / ovalRadii.height
            for x in x0...x1 {
                let l = label(x: x, y: y)
                guard l != 0 else { continue }
                let dx = ((CGFloat(x) + 0.5) / CGFloat(labelsWidth) * imageWidth - ovalCenter.x) / ovalRadii.width
                if dx * dx + dy * dy <= 1 {
                    counts[l] += 1
                }
            }
        }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else { return nil }
        return Pick(observation: observation, handler: handler, label: best)
    }

    /// True if any label-map pixel of the pick reaches one of the 4 screen edges. The photo is
    /// shown scaledToFill (`scale`, `offset` map photo pixels to screen points), so the screen
    /// edges are not the photo's edges.
    private static func touchesScreenEdge(
        _ pick: Pick, imageSize: CGSize, scale: CGFloat, offset: CGPoint, viewSize: CGSize
    ) -> Bool {
        let labels = pick.observation.instanceMask
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return false }
        let labelsWidth = CVPixelBufferGetWidth(labels)
        let labelsHeight = CVPixelBufferGetHeight(labels)
        let rowBytes = CVPixelBufferGetBytesPerRow(labels)

        // Label-map pixel size in screen points.
        let stepX = imageSize.width / CGFloat(labelsWidth) * scale
        let stepY = imageSize.height / CGFloat(labelsHeight) * scale
        let epsilon: CGFloat = 1e-6

        for y in 0..<labelsHeight {
            let minY = offset.y + CGFloat(y) * stepY
            let maxY = minY + stepY
            guard maxY > epsilon, minY < viewSize.height - epsilon else { continue }
            for x in 0..<labelsWidth {
                guard Int(base.load(fromByteOffset: y * rowBytes + x, as: UInt8.self)) == pick.label else { continue }
                let minX = offset.x + CGFloat(x) * stepX
                let maxX = minX + stepX
                guard maxX > epsilon, minX < viewSize.width - epsilon else { continue }
                if minX <= epsilon || maxX >= viewSize.width - epsilon
                    || minY <= epsilon || maxY >= viewSize.height - epsilon {
                    return true
                }
            }
        }
        return false
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
