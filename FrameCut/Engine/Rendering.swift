import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import SwiftUI
import AVFoundation

// MARK: - Filters & adjustments (Core Image, runs on the GPU per frame)

enum FrameLook {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func apply(filter: FilterPreset, adjust: Adjustments, to input: CIImage) -> CIImage {
        let extent = input.extent
        var img = input

        switch filter {
        case .none:
            break
        case .vivid:
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.saturation = 1.35
            f.contrast = 1.08
            f.brightness = 0
            img = f.outputImage ?? img
        case .warm: img = tint(img, r: 1.08, g: 1.0, b: 0.90)
        case .cool: img = tint(img, r: 0.92, g: 1.0, b: 1.08)
        case .fade: img = effect(CIFilter.photoEffectFade(), img)
        case .chrome: img = effect(CIFilter.photoEffectChrome(), img)
        case .instant: img = effect(CIFilter.photoEffectInstant(), img)
        case .process: img = effect(CIFilter.photoEffectProcess(), img)
        case .transfer: img = effect(CIFilter.photoEffectTransfer(), img)
        case .mono: img = effect(CIFilter.photoEffectMono(), img)
        case .noir: img = effect(CIFilter.photoEffectNoir(), img)
        case .tonal: img = effect(CIFilter.photoEffectTonal(), img)
        }

        if adjust.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = img
            f.ev = Float(adjust.exposure)
            img = f.outputImage ?? img
        }
        if adjust.brightness != 0 || adjust.contrast != 1 || adjust.saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.brightness = Float(adjust.brightness)
            f.contrast = Float(adjust.contrast)
            f.saturation = Float(adjust.saturation)
            img = f.outputImage ?? img
        }
        if adjust.warmth != 0 {
            img = tint(img, r: 1 + 0.12 * adjust.warmth, g: 1, b: 1 - 0.12 * adjust.warmth)
        }
        if adjust.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = img
            f.sharpness = Float(adjust.sharpness)
            f.radius = 1.5
            img = f.outputImage ?? img
        }
        if adjust.vignette > 0 {
            let f = CIFilter.vignetteEffect()
            f.inputImage = img
            f.center = CGPoint(x: extent.midX, y: extent.midY)
            f.radius = Float(hypot(extent.width, extent.height) / 2)
            f.intensity = Float(adjust.vignette)
            f.falloff = 0.6
            img = f.outputImage ?? img
        }
        return img.cropped(to: extent)
    }

    private static func effect(_ filter: CIFilter & CIPhotoEffect, _ image: CIImage) -> CIImage {
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private static func tint(_ image: CIImage, r: Double, g: Double, b: Double) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return f.outputImage ?? image
    }

    /// Small preview of a filter on a clip thumbnail (for the filter picker).
    static func preview(clip: Clip, filter: FilterPreset) async -> UIImage? {
        let time = clip.start + min(1, clip.sourceDuration / 2)
        guard let base = await Thumbnails.image(url: clip.url, time: time)?.cgImage else { return nil }
        let input = CIImage(cgImage: base)
        let output = apply(filter: filter, adjust: Adjustments(), to: input)
        guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Text, rendered at full output resolution

enum TextRenderer {
    static func image(for overlay: TextOverlay, renderSize: CGSize) -> CIImage? {
        let fontSize = max(8, overlay.size * renderSize.height)
        let font = UIFont.systemFont(ofSize: fontSize, weight: overlay.bold ? .heavy : .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(overlay.color),
            .paragraphStyle: paragraph
        ]
        if !overlay.background {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = fontSize * 0.15
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }

        let text = overlay.text as NSString
        let maxWidth = renderSize.width * 0.9
        let bounds = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral

        let padding = overlay.background ? fontSize * 0.35 : fontSize * 0.25
        let size = CGSize(width: bounds.width + padding * 2, height: bounds.height + padding * 2)
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if overlay.background {
                UIColor.black.withAlphaComponent(0.6).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: padding * 0.8).fill()
            }
            text.draw(
                with: CGRect(x: padding, y: padding, width: bounds.width, height: bounds.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        }
        guard let cg = rendered.cgImage else { return nil }

        // Core Image origin is bottom-left; overlay.y is measured from the top.
        let centerX = overlay.x * renderSize.width
        let centerY = (1 - overlay.y) * renderSize.height
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(
            translationX: centerX - size.width / 2,
            y: centerY - size.height / 2
        ))
    }
}

// MARK: - Thumbnails

enum Thumbnails {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(url: URL, time: Double) async -> UIImage? {
        let quantized = (time * 2).rounded() / 2
        let key = "\(url.lastPathComponent)-\(quantized)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let result = try? await generator.image(at: CMTime(seconds: quantized, preferredTimescale: 600)) else {
            return nil
        }
        let image = UIImage(cgImage: result.image)
        cache.setObject(image, forKey: key)
        return image
    }
}
