import AppKit

extension NSImage {
    func pngData(maxPixelSize: CGFloat? = nil) -> Data? {
        let targetSize: NSSize
        if let maxPixelSize {
            let ratio = min(maxPixelSize / max(size.width, 1), maxPixelSize / max(size.height, 1), 1)
            targetSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        } else {
            targetSize = size
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int(targetSize.width), 1),
            pixelsHigh: max(Int(targetSize.height), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
