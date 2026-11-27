import AVFoundation
import CoreImage
import UIKit

enum EditorError: LocalizedError {
    case noVideoTrack
    case cannotCreateTrack
    case exportUnavailable(String)
    case exportFailed(String)
    case photosDenied

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "Die Datei enthält keine Videospur."
        case .cannotCreateTrack: return "Die Komposition konnte nicht erstellt werden."
        case .exportUnavailable(let name): return "„\(name)“ ist für dieses Projekt auf diesem Gerät nicht verfügbar."
        case .exportFailed(let message): return "Export fehlgeschlagen: \(message)"
        case .photosDenied: return "Kein Zugriff auf die Fotomediathek. Bitte in den Einstellungen erlauben."
        }
    }
}

struct BuiltComposition {
    let asset: AVMutableComposition
    let videoComposition: AVVideoComposition?
    let audioMix: AVAudioMix?
}

private struct Segment {
    let range: CMTimeRange
    let orientation: CGImagePropertyOrientation
    let filter: FilterPreset
    let adjust: Adjustments
}

private struct TextLayer {
    let range: CMTimeRange
    let image: CIImage
}

/// Turns the editor state into an AVFoundation composition.
/// - passthrough: only cuts the original samples together (no re-encoding, bit-exact quality).
/// - otherwise: adds a Core Image video composition (orientation, canvas, filters, text) and an audio mix.
enum CompositionBuilder {
    static let timescale: CMTimeScale = 600

    static func cmTime(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    static func build(state: EditorState, passthrough: Bool) async throws -> BuiltComposition {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw EditorError.cannotCreateTrack }

        let clipAudio = AVMutableAudioMixInputParameters(track: audioTrack)
        var segments: [Segment] = []
        var cursor = CMTime.zero
        var hasAudio = false

        for clip in state.clips {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: clip.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }

            let wanted = CMTimeRange(start: cmTime(clip.start), end: cmTime(clip.end))
            let videoRange = try await sourceVideo.load(.timeRange)
            let range = wanted.intersection(videoRange)
            guard range.duration > .zero else { continue }
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)

            var audioInserted = false
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let sourceAudioRange = try await sourceAudio.load(.timeRange)
                let audioRange = range.intersection(sourceAudioRange)
                if audioRange.duration > .zero {
                    let offset = audioRange.start - range.start
                    try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: cursor + offset)
                    audioInserted = true
                    hasAudio = true
                }
            }

            var placed = range.duration
            if abs(clip.speed - 1) > 0.001 {
                let scaled = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / clip.speed)
                let inserted = CMTimeRange(start: cursor, duration: range.duration)
                videoTrack.scaleTimeRange(inserted, toDuration: scaled)
                if audioInserted { audioTrack.scaleTimeRange(inserted, toDuration: scaled) }
                placed = scaled
            }

            clipAudio.setVolume(clip.isMuted ? 0 : clip.volume, at: cursor)
            segments.append(Segment(
                range: CMTimeRange(start: cursor, duration: placed),
                orientation: orientation(for: clip.transform),
                filter: clip.filter,
                adjust: clip.adjust
            ))
            cursor = cursor + placed
        }

        guard !segments.isEmpty else { throw EditorError.noVideoTrack }
        if !hasAudio { composition.removeTrack(audioTrack) }

        if passthrough {
            // Original samples + original orientation flag. Nothing gets decoded or re-encoded.
            videoTrack.preferredTransform = state.clips.first?.transform ?? .identity
            return BuiltComposition(asset: composition, videoComposition: nil, audioMix: nil)
        }

        var mixInputs: [AVAudioMixInputParameters] = hasAudio ? [clipAudio] : []
        if let music = state.music,
           let musicInput = try await addMusic(music, to: composition, length: cursor) {
            mixInputs.append(musicInput)
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixInputs

        let videoComposition = makeVideoComposition(for: composition, state: state, segments: segments)
        return BuiltComposition(asset: composition, videoComposition: videoComposition, audioMix: audioMix)
    }

    // MARK: Music

    private static func addMusic(_ music: MusicTrack, to composition: AVMutableComposition, length: CMTime) async throws -> AVAudioMixInputParameters? {
        let asset = AVURLAsset(url: music.url)
        guard
            let source = try await asset.loadTracks(withMediaType: .audio).first,
            let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let full = try await source.load(.timeRange)
        var at = CMTime.zero
        var first = true
        while at < length {
            let segmentStart = first ? full.start + cmTime(music.offset) : full.start
            let available = full.end - segmentStart
            guard available > .zero else { break }
            let segmentLength = CMTimeMinimum(available, length - at)
            try track.insertTimeRange(CMTimeRange(start: segmentStart, duration: segmentLength), of: source, at: at)
            at = at + segmentLength
            first = false
            if !music.loop { break }
        }

        let params = AVMutableAudioMixInputParameters(track: track)
        params.setVolume(music.volume, at: .zero)
        if music.fadeOut, at.seconds > 1 {
            let fade = cmTime(min(2, at.seconds / 2))
            params.setVolumeRamp(fromStartVolume: music.volume, toEndVolume: 0, timeRange: CMTimeRange(start: at - fade, duration: fade))
        }
        return params
    }

    // MARK: Video composition

    private static func makeVideoComposition(for composition: AVMutableComposition, state: EditorState, segments: [Segment]) -> AVMutableVideoComposition {
        let renderSize = state.renderSize
        let renderRect = CGRect(origin: .zero, size: renderSize)
        let background = CIImage(color: .black).cropped(to: renderRect)

        let texts: [TextLayer] = state.texts.compactMap { overlay in
            guard !overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let image = TextRenderer.image(for: overlay, renderSize: renderSize) else { return nil }
            return TextLayer(range: CMTimeRange(start: cmTime(overlay.start), duration: cmTime(overlay.duration)), image: image)
        }

        let videoComposition = AVMutableVideoComposition(asset: composition, applyingCIFiltersWithHandler: { request in
            let time = request.compositionTime
            guard let segment = segments.first(where: { $0.range.containsTime(time) }) ?? segments.last else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            // 1. Upright orientation (composition track has an identity transform, so we rotate here).
            var image = request.sourceImage.oriented(segment.orientation)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

            // 2. Fit into the canvas – skipped when sizes already match (no resampling = no quality loss).
            let w = image.extent.width, h = image.extent.height
            if w > 0, h > 0, abs(w - renderSize.width) > 0.5 || abs(h - renderSize.height) > 0.5 {
                let scale = min(renderSize.width / w, renderSize.height / h)
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                image = image.transformed(by: CGAffineTransform(
                    translationX: (renderSize.width - w * scale) / 2,
                    y: (renderSize.height - h * scale) / 2
                ))
            }

            // 3. Look
            if segment.filter != .none || !segment.adjust.isNeutral {
                image = FrameLook.apply(filter: segment.filter, adjust: segment.adjust, to: image)
            }

            // 4. Canvas + text
            image = image.composited(over: background)
            for layer in texts where layer.range.containsTime(time) {
                image = layer.image.composited(over: image)
            }
            request.finish(with: image.cropped(to: renderRect), context: nil)
        })

        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration(for: state.frameRate)
        if state.isHDR {
            // Keep HDR (HLG / BT.2020) instead of tone-mapping to SDR.
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }
        return videoComposition
    }

    static func frameDuration(for fps: Float) -> CMTime {
        let ntsc: [(Float, CMTime)] = [
            (23.976, CMTime(value: 1001, timescale: 24000)),
            (29.97, CMTime(value: 1001, timescale: 30000)),
            (59.94, CMTime(value: 1001, timescale: 60000))
        ]
        for (rate, duration) in ntsc where abs(fps - rate) < 0.01 { return duration }
        return CMTime(value: 1, timescale: max(1, CMTimeScale(fps.rounded())))
    }

    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): return .right   // iPhone hochkant
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
