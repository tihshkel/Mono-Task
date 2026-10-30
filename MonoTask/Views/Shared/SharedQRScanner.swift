import SwiftUI
@preconcurrency import AVFoundation

/// Session configuration, start and stop all run on this one queue; callbacks carry strings to the main actor.
private final class SharedCaptureSession: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.monotask.qr-camera", qos: .userInitiated)
    private var configured = false
    @MainActor var onCode: ((String) -> Void)?
    @MainActor var onError: ((String) -> Void)?
    @MainActor private var lastCode: String?

    func start() {
        queue.async { [self] in
            do {
                if !configured {
                    #if os(iOS)
                    let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    #else
                    let camera = AVCaptureDevice.default(for: .video)
                    #endif
                    guard let camera else { throw CameraError.unavailable }
                    let input = try AVCaptureDeviceInput(device: camera)
                    let output = AVCaptureMetadataOutput()
                    session.beginConfiguration()
                    defer { session.commitConfiguration() }
                    guard session.canAddInput(input), session.canAddOutput(output) else {
                        throw CameraError.unavailable
                    }
                    session.addInput(input)
                    session.addOutput(output)
                    guard output.availableMetadataObjectTypes.contains(.qr) else {
                        session.removeInput(input)
                        session.removeOutput(output)
                        throw CameraError.unavailable
                    }
                    output.setMetadataObjectsDelegate(self, queue: .main)
                    output.metadataObjectTypes = [.qr]
                    configured = true
                }
                if !session.isRunning { session.startRunning() }
            } catch {
                Task { @MainActor [weak self] in
                    self?.onError?("Камера недоступна. Вставьте приглашение или выберите изображение с QR-кодом.")
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in if session.isRunning { session.stopRunning() } }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection
    ) {
        guard let value = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, value != lastCode else { return }
            lastCode = value
            onCode?(value)
        }
    }

    private enum CameraError: Error { case unavailable }
}

@MainActor
private final class SharedScannerModel: ObservableObject {
    @Published var message: String?
    @Published var denied = false
    @Published var ready = false
    let capture = SharedCaptureSession()

    func start() async {
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if permission == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            granted = permission == .authorized
        }
        guard !Task.isCancelled else { return }
        guard granted else {
            denied = true
            message = "Разрешите доступ к камере в настройках или введите код вручную."
            return
        }
        denied = false
        message = nil
        ready = true
        capture.onError = { [weak self] value in
            self?.ready = false; self?.message = value
        }
        capture.start()
    }
}

struct SharedQRScannerView: View {
    var onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = SharedScannerModel()
    @State private var accepted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("Один скан — и вы вместе").font(.system(size: 25, weight: .semibold)).tracking(-0.7)
                    Text("Наведите камеру на QR-код приглашения MonoTask.")
                        .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                ZStack {
                    Theme.Colors.darkestHour
                    if model.ready { SharedCameraPreview(capture: model.capture) }
                    if let message = model.message, !model.ready {
                        VStack(spacing: 16) {
                            Image(systemName: model.denied ? "camera.badge.ellipsis" : "camera")
                                .font(.system(size: 36)).foregroundStyle(Theme.Colors.sunGlare)
                            Text(message).font(Theme.Typography.callout).multilineTextAlignment(.center)
                                .foregroundStyle(Theme.Colors.cloudDancer).padding(.horizontal, 28)
                            if model.denied {
                                Button("Открыть настройки") { openSettings() }
                                    .foregroundStyle(Theme.Colors.sunGlare).buttonStyle(.plain)
                            }
                        }
                    } else {
                        ScannerCorners().stroke(
                            Theme.Colors.sunGlare, style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 210, height: 210)
                    }
                }
                .frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 28))
                .accessibilityIdentifier("shared-qr-camera")
                if let message = model.message, model.ready {
                    Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.priority)
                        .multilineTextAlignment(.center)
                }
                Button("Ввести код вручную") { dismiss() }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.Colors.accent)
                Text("Камера распознаёт только приглашения. Снимки не сохраняются.")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(Theme.Colors.background)
            .navigationTitle("Сканировать QR-код")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .foregroundStyle(Theme.Colors.textPrimary).tint(Theme.Colors.accent)
        .task {
            model.capture.onCode = { value in
                guard !accepted else { return }
                guard let code = SharedInvite.parseCode(value) else {
                    model.message = "Это не приглашение MonoTask. Попробуйте другой QR-код."
                    return
                }
                accepted = true
                model.capture.stop()
                Haptics.success()
                onFound(code)
                dismiss()
            }
            await model.start()
        }
        .onDisappear { model.capture.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !accepted { Task { await model.start() } } else { model.capture.stop() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 610)
        #endif
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            openURL(url)
        }
        #endif
    }
}

private struct ScannerCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 30
        for (x, y, dx, dy) in [
            (rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
            (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        return path
    }
}

#if os(iOS)
private struct SharedCameraPreview: UIViewRepresentable {
    let capture: SharedCaptureSession
    func makeUIView(context: Context) -> CameraSurface {
        let view = CameraSurface()
        view.preview.session = capture.session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: CameraSurface, context: Context) {}
    final class CameraSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
#else
private struct SharedCameraPreview: NSViewRepresentable {
    let capture: SharedCaptureSession
    func makeNSView(context: Context) -> CameraSurface { CameraSurface(session: capture.session) }
    func updateNSView(_ view: CameraSurface, context: Context) {}
    final class CameraSurface: NSView {
        private let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
#endif
