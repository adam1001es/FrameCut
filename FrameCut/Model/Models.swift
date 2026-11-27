import SwiftUI
import AVFoundation

// MARK: - Look

struct Adjustments: Equatable {
    var exposure: Double = 0      // -2 ... 2 EV
    var brightness: Double = 0    // -0.3 ... 0.3
    var contrast: Double = 1      // 0.5 ... 1.5
    var saturation: Double = 1    // 0 ... 2
    var warmth: Double = 0        // -1 ... 1
    var sharpness: Double = 0     // 0 ... 1
    var vignette: Double = 0      // 0 ... 1.5

    var isNeutral: Bool { self == Adjustments() }
}

enum FilterPreset: String, CaseIterable, Identifiable {
    case none, vivid, warm, cool, fade, chrome, instant, process, transfer, mono, noir, tonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Original"
        case .vivid: return "Lebendig"
        case .warm: return "Warm"
        case .cool: return "Kühl"
        case .fade: return "Fade"
        case .chrome: return "Chrome"
        case .instant: return "Instant"
        case .process: return "Process"
        case .transfer: return "Vintage"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .tonal: return "Tonal"
        }
    }
}

enum CanvasAspect: String, CaseIterable, Identifiable {
    case original, portrait, landscape, square, social

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .portrait: return "9:16"
        case .landscape: return "16:9"
        case .square: return "1:1"
        case .social: return "4:5"
        }
    }

    var subtitle: String {
        switch self {
        case .original: return "Wie das Video"
        case .portrait: return "TikTok · Reels · Shorts"
        case .landscape: return "YouTube"
        case .square: return "Quadrat"
        case .social: return "Instagram-Feed"
        }
    }

    /// width / height
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .portrait: return 9.0 / 16.0
        case .landscape: return 16.0 / 9.0
        case .square: return 1
        case .social: return 4.0 / 5.0
        }
    }
}

// MARK: - Clip

struct Clip: Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var assetDuration: Double
    var start: Double
    var end: Double
    var naturalSize: CGSize
    var transform: CGAffineTransform
    var hasAudio: Bool
    var isHDR: Bool
    var frameRate: Float
    var codec: FourCharCode

    var speed: Double = 1
    var volume: Float = 1
    var isMuted = false
    var filter: FilterPreset = .none
    var adjust = Adjustments()

    var sourceDuration: Double { end - start }
    var duration: Double { sourceDuration / speed }

    var orientedSize: CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    var hasLookChanges: Bool { filter != .none || !adjust.isNeutral }

    static func load(url: URL) async throws -> Clip {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw EditorError.noVideoTrack
        }
        let (size, transform, fps) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let (formats, range) = try await video.load(.formatDescriptions, .timeRange)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let hdr = try await asset.loadTracks(withMediaCharacteristic: .containsHDRVideo)
        let codec = formats.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
        let start = max(0, range.start.seconds)
        let end = min(duration.seconds, range.end.seconds)

        return Clip(
            url: url,
            assetDuration: end,
            start: start,
            end: end,
            naturalSize: size,
            transform: transform,
            hasAudio: !audio.isEmpty,
            isHDR: !hdr.isEmpty,
            frameRate: fps > 0 ? fps : 30,
            codec: codec
        )
    }
}

// MARK: - Text & Music

struct TextOverlay: Identifiable, Equatable {
    var id = UUID()
    var text: String = "Dein Text"
    var start: Double
    var duration: Double = 3
    var x: Double = 0.5            // 0 = links, 1 = rechts (Mitte des Textes)
    var y: Double = 0.8            // 0 = oben, 1 = unten
    var size: Double = 0.06        // Anteil an der Bildhöhe
    var color: Color = .white
    var bold = true
    var background = false

    var end: Double { start + duration }
}

struct MusicTrack: Equatable {
    var url: URL
    var name: String
    var duration: Double
    var volume: Float = 0.8
    var offset: Double = 0
    var loop = true
    var fadeOut = true
}

// MARK: - Project state

struct EditorState: Equatable {
    var clips: [Clip] = []
    var texts: [TextOverlay] = []
    var music: MusicTrack?
    var canvas: CanvasAspect = .original

    var totalDuration: Double { clips.reduce(0) { $0 + $1.duration } }

    var isHDR: Bool { clips.contains { $0.isHDR } }

    var frameRate: Float { clips.map(\.frameRate).max() ?? 30 }

    var renderSize: CGSize {
        let base = clips.first?.orientedSize ?? CGSize(width: 1080, height: 1920)
        func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded() * 2) }
        guard let ratio = canvas.ratio else {
            return CGSize(width: even(base.width), height: even(base.height))
        }
        let long = max(base.width, base.height)
        if ratio >= 1 {
            return CGSize(width: even(long), height: even(long / ratio))
        }
        return CGSize(width: even(long * ratio), height: even(long))
    }

    func startTime(ofClip id: UUID) -> Double? {
        var t = 0.0
        for clip in clips {
            if clip.id == id { return t }
            t += clip.duration
        }
        return nil
    }

    /// Clip at a timeline position and the offset inside that clip (timeline seconds).
    func clipLocation(at time: Double) -> (index: Int, offset: Double)? {
        var t = 0.0
        for (i, clip) in clips.enumerated() {
            if time < t + clip.duration { return (i, max(0, time - t)) }
            t += clip.duration
        }
        guard let last = clips.indices.last else { return nil }
        return (last, clips[last].duration)
    }

    /// Why a 1:1 passthrough export is not possible (nil = possible).
    var losslessBlocker: String? {
        guard let first = clips.first else { return "Keine Clips im Projekt." }
        if !texts.isEmpty { return "Texte müssen ins Bild gerendert werden." }
        if music != nil { return "Musik muss neu abgemischt werden." }
        if canvas != .original { return "Ein geändertes Format braucht Neuberechnung." }
        if clips.contains(where: { abs($0.speed - 1) > 0.001 }) { return "Tempo-Änderungen brauchen Neuberechnung." }
        if clips.contains(where: { $0.hasLookChanges }) { return "Filter/Anpassungen brauchen Neuberechnung." }
        if clips.contains(where: { $0.isMuted || $0.volume != 1 }) { return "Lautstärke-Änderungen brauchen Neuberechnung." }
        let sameFormat = clips.allSatisfy {
            $0.naturalSize == first.naturalSize && $0.transform == first.transform && $0.codec == first.codec
        }
        if !sameFormat { return "Clips haben unterschiedliche Formate oder Ausrichtungen." }
        return nil
    }
}

// MARK: - Formatting

extension Double {
    var timecode: String {
        guard isFinite else { return "00:00.00" }
        let total = Swift.max(0, self)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        let hundredths = Int((total - total.rounded(.down)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    var shortTime: String {
        let s = Int(Swift.max(0, self).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension CGSize {
    var resolutionLabel: String {
        let w = Int(width), h = Int(height)
        let long = Swift.max(w, h)
        let tag: String
        switch long {
        case 3840...: tag = "4K"
        case 2560...: tag = "1440p"
        case 1920...: tag = "1080p"
        case 1280...: tag = "720p"
        default: tag = "SD"
        }
        return "\(w)×\(h) · \(tag)"
    }
}
