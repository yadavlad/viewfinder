import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var isAuthorized = false
    @State private var isDenied = false

    var body: some View {
        Group {
            if isAuthorized {
                ZStack {
                    CameraPreview()
                        .ignoresSafeArea()
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
