import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Equatable, Sendable {
    case local
    case qiniu
    case s3
    case tencentCOS

    public var displayName: String {
        switch self {
        case .local:
            return "Local Folder"
        case .qiniu:
            return "Qiniu"
        case .s3:
            return "S3 Compatible"
        case .tencentCOS:
            return "Tencent COS"
        }
    }
}

public enum UploadStatus: String, Codable, Equatable, Sendable {
    case pending
    case uploading
    case uploaded
    case failed
}

public struct StorageProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: ProviderKind
    public var publicBaseURL: String
    public var namingTemplate: String
    public var localUploadDirectory: String?
    public var qiniuBucket: String
    public var qiniuUploadURL: String
    public var s3Bucket: String
    public var s3Region: String
    public var s3Endpoint: String
    public var s3UsePathStyle: Bool
    public var tencentCOSBucket: String
    public var tencentCOSRegion: String

    public init(
        id: UUID = UUID(),
        name: String,
        provider: ProviderKind = .qiniu,
        publicBaseURL: String = "https://images.example.com",
        namingTemplate: String = "ob/{uuid}.{ext}",
        localUploadDirectory: String? = nil,
        qiniuBucket: String = "",
        qiniuUploadURL: String = "https://upload.qiniup.com",
        s3Bucket: String = "",
        s3Region: String = "auto",
        s3Endpoint: String = "",
        s3UsePathStyle: Bool = true,
        tencentCOSBucket: String = "",
        tencentCOSRegion: String = "ap-shanghai"
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.publicBaseURL = publicBaseURL
        self.namingTemplate = namingTemplate
        self.localUploadDirectory = localUploadDirectory
        self.qiniuBucket = qiniuBucket
        self.qiniuUploadURL = qiniuUploadURL
        self.s3Bucket = s3Bucket
        self.s3Region = s3Region
        self.s3Endpoint = s3Endpoint
        self.s3UsePathStyle = s3UsePathStyle
        self.tencentCOSBucket = tencentCOSBucket
        self.tencentCOSRegion = tencentCOSRegion
    }

    public static func defaultQiniu() -> StorageProfile {
        StorageProfile(name: "Qiniu", provider: .qiniu)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var profiles: [StorageProfile]
    public var defaultProfileID: UUID
    public var launchAtLogin: Bool

    public init(
        profiles: [StorageProfile] = [StorageProfile.defaultQiniu()],
        defaultProfileID: UUID? = nil,
        launchAtLogin: Bool = false
    ) {
        let resolvedProfiles = profiles.isEmpty ? [StorageProfile.defaultQiniu()] : profiles
        self.profiles = resolvedProfiles
        self.defaultProfileID = defaultProfileID ?? resolvedProfiles[0].id
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppSettings()

    public var defaultProfile: StorageProfile {
        profiles.first(where: { $0.id == defaultProfileID }) ?? profiles[0]
    }

    public mutating func normalize() {
        if profiles.isEmpty {
            profiles = [StorageProfile.defaultQiniu()]
        }
        if !profiles.contains(where: { $0.id == defaultProfileID }) {
            defaultProfileID = profiles[0].id
        }
    }
}

public struct ImagePayload: Equatable, Sendable {
    public var data: Data
    public var originalFileName: String?
    public var fileExtension: String
    public var contentHash: String
    public var createdAt: Date

    public init(
        data: Data,
        originalFileName: String?,
        fileExtension: String,
        contentHash: String,
        createdAt: Date = Date()
    ) {
        self.data = data
        self.originalFileName = originalFileName
        self.fileExtension = fileExtension
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
}

public struct ImageRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var originalFileName: String?
    public var objectKey: String
    public var publicURL: String?
    public var markdown: String?
    public var status: UploadStatus
    public var contentHash: String
    public var thumbnailPath: String?
    public var localFilePath: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var uploadedAt: Date?

    public init(
        id: UUID = UUID(),
        originalFileName: String?,
        objectKey: String,
        publicURL: String? = nil,
        markdown: String? = nil,
        status: UploadStatus,
        contentHash: String,
        thumbnailPath: String? = nil,
        localFilePath: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        uploadedAt: Date? = nil
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.objectKey = objectKey
        self.publicURL = publicURL
        self.markdown = markdown
        self.status = status
        self.contentHash = contentHash
        self.thumbnailPath = thumbnailPath
        self.localFilePath = localFilePath
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.uploadedAt = uploadedAt
    }
}

public struct UploadResult: Equatable, Sendable {
    public var objectKey: String
    public var publicURL: String
    public var markdown: String
    public var localFilePath: String?

    public init(objectKey: String, publicURL: String, markdown: String, localFilePath: String?) {
        self.objectKey = objectKey
        self.publicURL = publicURL
        self.markdown = markdown
        self.localFilePath = localFilePath
    }
}
