import AVFoundation
import SwiftUI

struct PairingQrScannerSheet: View {
    let onScannedCode: (String) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    var body: some View {
        ZStack {
            PairingQrCaptureView(onScannedCode: onScannedCode, onFailure: onFailure)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: POSSpacing.sm) {
                    VStack(alignment: .leading, spacing: POSSpacing.xxs) {
                        Text("QR scannen")
                            .font(POSTypography.titleMedium)
                            .foregroundStyle(POSColor.slate050)
                        Text("Richte die Kamera auf den Pairing-QR der Hauptkasse.")
                            .font(POSTypography.labelLarge)
                            .foregroundStyle(POSColor.slate300)
                    }
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(POSColor.slate050)
                            .padding(POSSpacing.sm)
                            .background(POSColor.slate800.opacity(0.9))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, POSSpacing.lg)
                .padding(.vertical, POSSpacing.md)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(POSColor.slate700.opacity(0.55))
                        .frame(height: 1),
                    alignment: .bottom
                )

                Spacer()
            }
        }
    }
}

private struct PairingQrCaptureView: UIViewControllerRepresentable {
    let onScannedCode: (String) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> PairingQrCaptureViewController {
        let controller = PairingQrCaptureViewController()
        context.coordinator.attach(to: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: PairingQrCaptureViewController, context: Context) {
        context.coordinator.updatePreviewFrameIfNeeded()
    }

    static func dismantleUIViewController(_ uiViewController: PairingQrCaptureViewController, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let parent: PairingQrCaptureView
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "kassensystem.qr.capture.session", qos: .userInitiated)
        private weak var controller: PairingQrCaptureViewController?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didConfigureSession = false
        private var didEmitResult = false
        private var didEmitFailure = false

        init(parent: PairingQrCaptureView) {
            self.parent = parent
        }

        func attach(to controller: PairingQrCaptureViewController) {
            self.controller = controller
            controller.onLayout = { [weak self] in
                self?.updatePreviewFrameIfNeeded()
            }
            configureSessionIfNeeded()
        }

        func updatePreviewFrameIfNeeded() {
            guard let bounds = controller?.view.bounds else { return }
            previewLayer?.frame = bounds
        }

        func stopSession() {
            sessionQueue.async { [session] in
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }

        private func configureSessionIfNeeded() {
            guard !didConfigureSession else {
                startSessionIfNeeded()
                return
            }
            didConfigureSession = true

            let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
            switch authStatus {
            case .authorized:
                setupCapturePipeline()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        if granted {
                            self.setupCapturePipeline()
                        } else {
                            self.reportFailure("Kamera-Zugriff abgelehnt. Bitte in den iOS-Einstellungen erlauben.")
                        }
                    }
                }
            case .denied, .restricted:
                reportFailure("Kein Kamera-Zugriff. Bitte in Einstellungen > Datenschutz > Kamera erlauben.")
            @unknown default:
                reportFailure("Kamera auf diesem Gerät aktuell nicht verfügbar.")
            }
        }

        private func setupCapturePipeline() {
            guard let controller else {
                reportFailure("Scanner konnte nicht initialisiert werden.")
                return
            }
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                reportFailure("Keine Kamera verfügbar (Simulator ohne Kamera).")
                return
            }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .high

            do {
                let input = try AVCaptureDeviceInput(device: videoDevice)
                guard session.canAddInput(input) else {
                    reportFailure("Kamera-Eingang konnte nicht hinzugefügt werden.")
                    return
                }
                session.addInput(input)
            } catch {
                reportFailure("Kamera konnte nicht gestartet werden: \(error.localizedDescription)")
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadataOutput) else {
                reportFailure("QR-Erkennung konnte nicht initialisiert werden.")
                return
            }
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = controller.view.bounds
            controller.view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer

            startSessionIfNeeded()
        }

        private func startSessionIfNeeded() {
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didEmitResult else { return }
            guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
                  object.type == .qr,
                  let scannedCode = object.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !scannedCode.isEmpty else {
                return
            }

            didEmitResult = true
            stopSession()
            parent.onScannedCode(scannedCode)
        }

        private func reportFailure(_ message: String) {
            guard !didEmitFailure else { return }
            didEmitFailure = true
            stopSession()
            parent.onFailure(message)
        }
    }
}

private final class PairingQrCaptureViewController: UIViewController {
    var onLayout: (() -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }
}
