import CryptoKit
import Foundation

public enum QiniuUploadError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingBucket
    case missingCredentials
    case invalidUploadURL
    case invalidResponse(statusCode: Int, body: String)
    case missingHTTPResponse

    public var description: String {
        switch self {
        case .missingBucket:
            return "Qiniu bucket is missing."
        case .missingCredentials:
            return "Qiniu access key or secret key is missing."
        case .invalidUploadURL:
            return "Qiniu upload URL is invalid."
        case .invalidResponse(let statusCode, let body):
            return "Qiniu upload failed with HTTP \(statusCode): \(body)"
        case .missingHTTPResponse:
            return "Qiniu upload did not return an HTTP response."
        }
    }
}

public struct QiniuCredentials: Equatable, Sendable {
    public var accessKey: String
    public var secretKey: String

    public init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
}

public struct QiniuUploadProvider {
    public var bucket: String
    public var uploadURL: URL
    public var publicBaseURL: String
    public var credentials: QiniuCredentials
    public var urlSession: URLSession

    public init(
        bucket: String,
        uploadURL: URL,
        publicBaseURL: String,
        credentials: QiniuCredentials,
        urlSession: URLSession = .shared
    ) {
        self.bucket = bucket
        self.uploadURL = uploadURL
        self.publicBaseURL = publicBaseURL
        self.credentials = credentials
        self.urlSession = urlSession
    }

    public static func make(
        profile: StorageProfile,
        credentials: QiniuCredentials?,
        urlSession: URLSession = .shared
    ) throws -> QiniuUploadProvider {
        guard !profile.qiniuBucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QiniuUploadError.missingBucket
        }

        guard let credentials,
              !credentials.accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QiniuUploadError.missingCredentials
        }

        guard let uploadURL = URL(string: profile.qiniuUploadURL), uploadURL.scheme != nil else {
            throw QiniuUploadError.invalidUploadURL
        }

        return QiniuUploadProvider(
            bucket: profile.qiniuBucket,
            uploadURL: uploadURL,
            publicBaseURL: profile.publicBaseURL,
            credentials: credentials,
            urlSession: urlSession
        )
    }

    public func upload(payload: ImagePayload, objectKey: String) async throws -> UploadResult {
        let token = uploadToken(objectKey: objectKey)
        let requestBody = MultipartFormData()
        requestBody.addField(name: "key", value: objectKey)
        requestBody.addField(name: "token", value: token)
        requestBody.addFile(name: "file", filename: filename(for: objectKey), contentType: contentType(for: payload.fileExtension), data: payload.data)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(requestBody.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody.data

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QiniuUploadError.missingHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw QiniuUploadError.invalidResponse(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        let publicURL = ObjectKeyTemplate.publicURL(baseURL: publicBaseURL, objectKey: objectKey)
        return UploadResult(
            objectKey: objectKey,
            publicURL: publicURL,
            markdown: MarkdownFormatter.image(url: publicURL),
            localFilePath: nil
        )
    }

    public func uploadToken(objectKey: String, deadline: Int = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)) -> String {
        let policy = #"{"scope":"\#(bucket):\#(objectKey)","deadline":\#(deadline)}"#
        let encodedPolicy = Base64URL.encode(Data(policy.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(encodedPolicy.utf8),
            using: SymmetricKey(data: Data(credentials.secretKey.utf8))
        )
        let encodedSignature = Base64URL.encode(Data(signature))
        return "\(credentials.accessKey):\(encodedSignature):\(encodedPolicy)"
    }

    private func filename(for objectKey: String) -> String {
        URL(fileURLWithPath: objectKey).lastPathComponent
    }

    private func contentType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        case "tif", "tiff":
            return "image/tiff"
        default:
            return "image/png"
        }
    }
}

private final class MultipartFormData {
    let boundary = "PiconBoundary-\(UUID().uuidString)"
    private(set) var data = Data()

    func addField(name: String, value: String) {
        appendBoundary()
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    func addFile(name: String, filename: String, contentType: String, data fileData: Data) {
        appendBoundary()
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
    }

    private func appendBoundary() {
        append("--\(boundary)\r\n")
    }

    private func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}
