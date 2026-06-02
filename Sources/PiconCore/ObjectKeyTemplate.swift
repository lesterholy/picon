import Foundation

public struct ObjectKeyContext: Equatable, Sendable {
    public var originalFileName: String?
    public var relativePath: String?
    public var fileExtension: String
    public var date: Date
    public var uuid: UUID
    public var contentHash: String
    public var index: Int?

    public init(
        originalFileName: String?,
        relativePath: String? = nil,
        fileExtension: String,
        date: Date = Date(),
        uuid: UUID = UUID(),
        contentHash: String,
        index: Int? = nil
    ) {
        self.originalFileName = originalFileName
        self.relativePath = relativePath
        self.fileExtension = fileExtension
        self.date = date
        self.uuid = uuid
        self.contentHash = contentHash
        self.index = index
    }
}

public enum ObjectKeyTemplate {
    public static func batchTemplate(from template: String) -> String {
        let resolvedTemplate = template.isEmpty ? "ob/{uuid}.{ext}" : template
        if resolvedTemplate.contains("{relativePath}") {
            return resolvedTemplate
        }

        let parts = resolvedTemplate
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let directory = parts.dropLast().joined(separator: "/")
        let batchLeaf = "{relativePath}-{hash}.{ext}"
        return directory.isEmpty ? batchLeaf : "\(directory)/\(batchLeaf)"
    }

    public static func render(_ template: String, context: ObjectKeyContext) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: context.date)
        let baseName = filenameStem(context.originalFileName)
        let relativeStem = relativePathStem(context.relativePath)
        let relativeDir = relativeDirectory(context.relativePath)
        let ext = sanitizeExtension(context.fileExtension)

        var output = template.isEmpty ? "ob/{uuid}.{ext}" : template
        let replacements: [String: String] = [
            "{uuid}": context.uuid.uuidString.lowercased(),
            "{yyyy}": String(format: "%04d", components.year ?? 1970),
            "{MM}": String(format: "%02d", components.month ?? 1),
            "{dd}": String(format: "%02d", components.day ?? 1),
            "{HH}": String(format: "%02d", components.hour ?? 0),
            "{mm}": String(format: "%02d", components.minute ?? 0),
            "{ss}": String(format: "%02d", components.second ?? 0),
            "{filename}": sanitizePathSegment(baseName),
            "{slug}": slugify(baseName),
            "{relativePath}": sanitizeRelativePath(relativeStem),
            "{relativeDir}": sanitizeRelativePath(relativeDir),
            "{hash}": String(context.contentHash.prefix(12)),
            "{index}": String(format: "%04d", context.index ?? 1),
            "{ext}": ext
        ]

        for (token, value) in replacements {
            output = output.replacingOccurrences(of: token, with: value)
        }

        output = output
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { sanitizePathSegment(String($0), preservingDot: true) }
            .joined(separator: "/")

        if !output.lowercased().hasSuffix(".\(ext)") {
            output += ".\(ext)"
        }

        return output.isEmpty ? "ob/\(context.uuid.uuidString.lowercased()).\(ext)" : output
    }

    public static func publicURL(baseURL: String, objectKey: String) -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedKey = objectKey
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        return "\(trimmedBase)/\(encodedKey)"
    }

    private static func filenameStem(_ originalFileName: String?) -> String {
        guard let originalFileName, !originalFileName.isEmpty else {
            return "image"
        }

        let url = URL(fileURLWithPath: originalFileName)
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "image" : stem
    }

    private static func relativePathStem(_ relativePath: String?) -> String {
        guard let relativePath, !relativePath.isEmpty else {
            return "image"
        }

        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = parts.last else {
            return "image"
        }
        let stem = URL(fileURLWithPath: last).deletingPathExtension().lastPathComponent
        return (parts.dropLast() + [stem]).joined(separator: "/")
    }

    private static func relativeDirectory(_ relativePath: String?) -> String {
        guard let relativePath, !relativePath.isEmpty else {
            return ""
        }

        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return parts.dropLast().joined(separator: "/")
    }

    private static func sanitizeExtension(_ fileExtension: String) -> String {
        let cleaned = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        return cleaned.isEmpty ? "png" : cleaned
    }

    private static func sanitizePathSegment(_ value: String, preservingDot: Bool = false) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_\(preservingDot ? "." : "")"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }

        let cleaned = String(scalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        return cleaned.isEmpty ? "image" : cleaned
    }

    private static func slugify(_ value: String) -> String {
        sanitizePathSegment(value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased())
    }

    private static func sanitizeRelativePath(_ value: String) -> String {
        value
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { sanitizePathSegment(String($0), preservingDot: true) }
            .joined(separator: "/")
    }
}
