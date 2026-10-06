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
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                    } else {
                        CameraPreview(camera: camera)
                            .ignoresSafeArea()
                    }

                    GeometryReader { geometry in
                        CrosshairIcon()
                            .position(
                                x: geometry.size.width / 2,
                                y: geometry.size.height / 2 - geometry.size.height * 0.05
                            )
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                    if photo != nil {
                        VStack {
                            HStack {
                                Button {
                                    photo = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .accessibilityLabel("Close")
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding()
                    } else {
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
