import AppKit
import Foundation
import PiconCore

struct ClipboardImage: Equatable {
    var image: NSImage
    var payload: ImagePayload
}

final class ClipboardMonitor {
    private let onImage: (ClipboardImage) -> Void
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(onImage: @escaping (ClipboardImage) -> Void) {
        self.onImage = onImage
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer!, forMode: .common)
        scan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        guard let clipboardImage = Self.readImage(from: pasteboard) else {
            return
        }

        onImage(clipboardImage)
    }

    private static func readImage(from pasteboard: NSPasteboard) -> ClipboardImage? {
        if let fileImage = readFileImage(from: pasteboard) {
            return fileImage
        }

        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData) {
            return makeClipboardImage(image: image, data: pngData, originalFileName: "clipboard.png", fileExtension: "png")
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = image.pngData() {
            return makeClipboardImage(image: image, data: pngData, originalFileName: "clipboard.png", fileExtension: "png")
        }

        return nil
    }

    private static func readFileImage(from pasteboard: NSPasteboard) -> ClipboardImage? {
        guard let items = pasteboard.pasteboardItems else {
            return nil
        }

        for item in items {
            guard let string = item.string(forType: .fileURL),
                  let url = URL(string: string),
                  isImageFile(url),
                  let image = NSImage(contentsOf: url),
                  let data = normalizedImageData(image: image, sourceURL: url) else {
                continue
            }

            return makeClipboardImage(
                image: image,
                data: data,
                originalFileName: url.lastPathComponent,
                fileExtension: normalizedExtension(url.pathExtension)
            )
        }

        return nil
    }

    private static func normalizedImageData(image: NSImage, sourceURL: URL) -> Data? {
        let ext = normalizedExtension(sourceURL.pathExtension)
        if ext == "png" || ext == "jpg" || ext == "gif" || ext == "webp" || ext == "heic" || ext == "tif" || ext == "tiff" {
            return try? Data(contentsOf: sourceURL)
        }

        return image.pngData()
    }

    private static func makeClipboardImage(
        image: NSImage,
        data: Data,
        originalFileName: String?,
        fileExtension: String
    ) -> ClipboardImage {
        let payload = ImagePayload(
            data: data,
            originalFileName: originalFileName,
            fileExtension: normalizedExtension(fileExtension),
            contentHash: Hashing.fnv1a64Hex(data)
        )
        return ClipboardImage(image: image, payload: payload)
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let supported = ["png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "heic"]
        return supported.contains(normalizedExtension(url.pathExtension))
    }

    private static func normalizedExtension(_ value: String) -> String {
        let normalized = value.lowercased()
        return normalized == "jpeg" ? "jpg" : (normalized.isEmpty ? "png" : normalized)
    }
}
