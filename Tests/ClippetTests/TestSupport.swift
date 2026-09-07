import AppKit
import XCTest
@testable import Clippet

/// A scratch directory per test, removed on teardown.
final class TempDir {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clippet-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func path(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func fileSize(_ path: String) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
}

/// A gradient PNG of the given size; `seed` shifts the colours so images differ. `alpha`
/// controls whether the image carries transparency.
func makePNG(width: Int, height: Int, seed: UInt8 = 0x40, alpha: UInt8 = 255) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let count = rep.bytesPerRow * height
    let base = rep.bitmapData!
    for i in 0..<count {
        base[i] = i % 4 == 3 ? alpha : seed &+ UInt8(truncatingIfNeeded: i)
    }
    return rep.representation(using: .png, properties: [:])!
}

func tiffData(fromPNG png: Data) -> Data {
    NSBitmapImageRep(data: png)!.tiffRepresentation!
}

func textCapture(_ text: String, source: String? = "com.example.app", at date: Date = Date()) -> PasteboardCapture {
    .text(text, source: source, at: date)
}

func imageCapture(_ png: Data, source: String? = "com.example.app", at date: Date = Date()) -> PasteboardCapture {
    .image(ImageCodec.process(png, maxBytes: .max)!, source: source, at: date)
}
