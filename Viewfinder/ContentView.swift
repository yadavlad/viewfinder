import SwiftUI
import AVFoundation

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
                        WhiteningView(photo: photo) {
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

/// Turns the captured photo white, outside-in toward the crosshair, over 10 s.
private struct WhiteningView: View {
    let photo: UIImage
    let onTap: () -> Void
    @State private var progress: CGFloat = 0

    // Hole scale at progress 0; the hole's fully-clear radius is 0.5 * scale * farthest-corner
    // distance, so 2.2 clears every corner.
    private let blurStartScale: CGFloat = 2.2
    // The white hole is larger than the blur hole, so white trails behind the blur.
    private let whiteStartScale: CGFloat = 2.9

    var body: some View {
        GeometryReader { geometry in
            let center = crosshairCenter(in: geometry.size)
            let radius = max(
                hypot(center.x, center.y),
                hypot(geometry.size.width - center.x, center.y),
                hypot(center.x, geometry.size.height - center.y),
                hypot(geometry.size.width - center.x, geometry.size.height - center.y)
            )

            ZStack {
                photoLayer

                photoLayer
                    .blur(radius: 40, opaque: true)
                    .mask {
                        holeMask(center: center, radius: radius, scale: blurStartScale * (1 - progress))
                    }

                Color.white
                    .mask {
                        holeMask(center: center, radius: radius, scale: whiteStartScale * (1 - progress))
                    }

                CrosshairIcon()
                    .position(center)
                    .opacity(1 - progress)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Return to camera")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(.easeInOut(duration: 10)) {
                progress = 1
            }
        }
    }

    private var photoLayer: some View {
        Color.clear
            .overlay {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }

    /// Opaque everywhere except a soft-edged circular hole centered on `center`.
    /// The hole is fully clear out to 0.5 * scale * radius and fades out by scale * radius.
    private func holeMask(center: CGPoint, radius: CGFloat, scale: CGFloat) -> some View {
        ZStack {
            Color.black
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .scaleEffect(scale)
                .position(center)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
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
