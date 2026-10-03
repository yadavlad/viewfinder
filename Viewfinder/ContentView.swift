import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var isAuthorized = false
    @State private var isDenied = false

    var body: some View {
        Group {
            if isAuthorized {
                CameraPreview()
                    .ignoresSafeArea()
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

#Preview {
    ContentView()
}
