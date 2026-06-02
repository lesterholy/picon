import Foundation

public enum LocalUploadError: Error, Equatable {
    case invalidObjectKey
}

public struct LocalUploadProvider {
    public var rootDirectory: URL
    public var publicBaseURL: String

    public init(rootDirectory: URL, publicBaseURL: String) {
        self.rootDirectory = rootDirectory
        self.publicBaseURL = publicBaseURL
    }

    public func upload(payload: ImagePayload, objectKey requestedObjectKey: String) throws -> UploadResult {
        let objectKey = try availableObjectKey(for: requestedObjectKey)
        let destinationURL = rootDirectory.appendingPathComponent(objectKey, isDirectory: false)
        let destinationDirectory = destinationURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try payload.data.write(to: destinationURL, options: .atomic)

        let publicURL = destinationURL.absoluteString
        return UploadResult(
            objectKey: objectKey,
            publicURL: publicURL,
            markdown: MarkdownFormatter.image(url: publicURL),
            localFilePath: destinationURL.path
        )
    }

    private func availableObjectKey(for requestedObjectKey: String) throws -> String {
        let cleanKey = requestedObjectKey
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")

        guard !cleanKey.isEmpty, !cleanKey.contains("..") else {
            throw LocalUploadError.invalidObjectKey
        }

        var candidate = cleanKey
        var candidateURL = rootDirectory.appendingPathComponent(candidate, isDirectory: false)
        var counter = 1

        while FileManager.default.fileExists(atPath: candidateURL.path) {
            candidate = Self.appendCollisionSuffix(to: cleanKey, counter: counter)
            candidateURL = rootDirectory.appendingPathComponent(candidate, isDirectory: false)
            counter += 1
        }

        return candidate
    }

    private static func appendCollisionSuffix(to objectKey: String, counter: Int) -> String {
        let url = URL(fileURLWithPath: objectKey)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().path

        if ext.isEmpty {
            return "\(stem)-\(counter)"
        }

        return "\(stem)-\(counter).\(ext)"
    }
}
