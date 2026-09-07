import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image decoding, normalization and thumbnails on top of ImageIO. Everything here is
/// pure CoreGraphics and safe to call off the main thread, which is where captures are
/// processed so a 4K screenshot never stalls the UI.
enum ImageCodec {
    /// A pasteboard image turned into what the store keeps.
    struct Processed {
        let png: Data
        let hash: String
        let width: Int
        let height: Int
        let thumbnail: Data?
    }

    /// Long edge of list/preview thumbnails, in pixels.
    static let thumbnailMaxPixels = 512

    /// Decodes, re-encodes to PNG, hashes and thumbnails `raw` (PNG or TIFF from the
    /// pasteboard). Returns nil when the data is not an image or the PNG exceeds `maxBytes`.
    static func process(_ raw: Data, maxBytes: Int) -> Processed? {
        guard let image = decode(raw),
              let png = pngData(image),
              png.count <= maxBytes else { return nil }
        return Processed(png: png,
                         hash: pixelHash(image),
                         width: image.width,
                         height: image.height,
                         thumbnail: thumbnail(of: image))
    }

    /// First frame, fully decoded so drawing it later does no work on the caller's thread.
    static func decode(_ data: Data) -> CGImage? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }

    static func pngData(_ image: CGImage) -> Data? {
        encode(image, type: .png, properties: nil)
    }

    /// Identity of the picture itself. Two encodings of the same pixels (PNG vs TIFF, or a
    /// PNG re-encoded by Clippet) hash the same; the encoded bytes would not.
    static func pixelHash(_ image: CGImage) -> String {
        let width = image.width, height = image.height
        var hasher = SHA256()
        hasher.update(data: Data("\(width)x\(height)".utf8))
        if let pixels = canonicalPixels(image) {
            pixels.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Thumbnail no larger than `thumbnailMaxPixels` on the long edge: JPEG when every pixel
    /// is opaque, PNG when there is real transparency so window shadows don't turn black.
    /// (Screenshots declare an alpha channel even when fully opaque, so the pixels decide.)
    static func thumbnail(of image: CGImage) -> Data? {
        let longEdge = max(image.width, image.height)
        let scale = min(1, Double(thumbnailMaxPixels) / Double(max(longEdge, 1)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        if hasTranslucentPixels(context) {
            return encode(scaled, type: .png, properties: nil)
        }
        return encode(scaled, type: .jpeg,
                      properties: [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    }

    private static func hasTranslucentPixels(_ context: CGContext) -> Bool {
        guard let base = context.data else { return true }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        for row in 0..<context.height {
            let rowStart = row * bytesPerRow
            for column in 0..<context.width where bytes[rowStart + column * 4 + 3] != 255 {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    /// RGBA8 sRGB premultiplied, tightly packed: the same picture yields the same bytes
    /// whatever container or pixel layout it arrived in.
    private static func canonicalPixels(_ image: CGImage) -> Data? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var buffer = Data(count: bytesPerRow * height)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? buffer : nil
    }

    private static func encode(_ image: CGImage, type: UTType, properties: CFDictionary?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
