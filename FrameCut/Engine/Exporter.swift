import AVFoundation
import Photos
import UIKit

enum ExportQuality: String, CaseIterable, Identifiable {
    case lossless, prores, hevc, h264

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lossless: return "Verlustfrei (Original 1:1)"
        case .prores: return "Apple ProRes 422"
        case .hevc: return "HEVC – Höchste Qualität"
        case .h264: return "H.264 – Höchste Qualität"
        }
    }

    var subtitle: String {
        switch self {
        case .lossless: return "Keine Neukodierung. Exakt die Originaldaten, 100 % Qualität."
        case .prores: return "Studio-Codec, visuell verlustfrei. Sehr große Dateien."
        case .hevc: return "Volle Original-Auflösung, HDR bleibt erhalten."
        case .h264: return "Maximale Kompatibilität, volle Auflösung (SDR)."
        }
    }

    var preset: String {
        switch self {
        case .lossless: return AVAssetExportPresetPassthrough
        // String value of AVAssetExportPresetAppleProRes422LPCM; availability is checked at runtime.
        case .prores: return "AVAssetExportPresetAppleProRes422LPCM"
        case .hevc: return AVAssetExportPresetHEVCHighestQuality
        case .h264: return AVAssetExportPresetHighestQuality
        }
    }

    static var isProResAvailable: Bool {
        AVAssetExportSession.allExportPresets().contains(ExportQuality.prores.preset)
    }
}

@MainActor
final class Exporter: ObservableObject {
    enum Phase: Equatable {
        case idle
        case exporting
        case saving
        case done(url: URL, savedToPhotos: Bool, note: String?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Float = 0
    private var session: AVAssetExportSession?

    var isBusy: Bool { phase == .exporting || phase == .saving }

    func export(state: EditorState, quality: ExportQuality) async {
        phase = .exporting
        progress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        let url: URL
        do {
            let built = try await CompositionBuilder.build(state: state, passthrough: quality == .lossless)
            let compatible = await AVAssetExportSession.compatibility(ofExportPreset: quality.preset, with: built.asset, outputFileType: .mov)
            guard compatible, let session = AVAssetExportSession(asset: built.asset, presetName: quality.preset) else {
                throw EditorError.exportUnavailable(quality.title)
            }

            url = MediaStore.newExportURL()
            session.outputURL = url
            session.outputFileType = .mov
            if quality != .lossless {
                session.videoComposition = built.videoComposition
                session.audioMix = built.audioMix
                session.audioTimePitchAlgorithm = .spectral
            }
            self.session = session

            let poller = Task { [weak self] in
                while !Task.isCancelled {
                    self?.progress = session.progress
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            await session.export()
            poller.cancel()
            self.session = nil

            switch session.status {
            case .completed:
                progress = 1
            case .cancelled:
                phase = .idle
                return
            default:
                throw EditorError.exportFailed(session.error?.localizedDescription ?? "Unbekannter Fehler")
            }
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        phase = .saving
        do {
            try await PhotoSaver.save(url)
            phase = .done(url: url, savedToPhotos: true, note: nil)
        } catch {
            phase = .done(url: url, savedToPhotos: false, note: error.localizedDescription)
        }
    }

    func cancel() {
        session?.cancelExport()
    }

    func reset() {
        phase = .idle
        progress = 0
    }
}

enum PhotoSaver {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw EditorError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }
}
