import CryptoKit
import Foundation

public enum S3UploadError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingBucket
    case missingEndpoint
    case missingCredentials
    case invalidEndpoint
    case invalidRequestURL
    case invalidResponse(statusCode: Int, body: String)
    case missingHTTPResponse

    public var description: String {
        switch self {
        case .missingBucket:
            return "S3 bucket is missing."
        case .missingEndpoint:
            return "S3 endpoint is missing."
        case .missingCredentials:
            return "S3 access key or secret key is missing."
        case .invalidEndpoint:
            return "S3 endpoint is invalid."
        case .invalidRequestURL:
            return "S3 request URL could not be built."
        case .invalidResponse(let statusCode, let body):
            return "S3 upload failed with HTTP \(statusCode): \(body)"
        case .missingHTTPResponse:
            return "S3 upload did not return an HTTP response."
        }
    }
}

public struct S3Credentials: Equatable, Sendable {
    public var accessKey: String
    public var secretKey: String

    public init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }
}

public struct S3UploadProvider {
    public var bucket: String
    public var region: String
    public var endpoint: URL
    public var usePathStyle: Bool
    public var publicBaseURL: String
    public var credentials: S3Credentials
    public var urlSession: URLSession

    public init(
        bucket: String,
        region: String,
        endpoint: URL,
        usePathStyle: Bool,
        publicBaseURL: String,
        credentials: S3Credentials,
        urlSession: URLSession = .shared
    ) {
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.usePathStyle = usePathStyle
        self.publicBaseURL = publicBaseURL
        self.credentials = credentials
        self.urlSession = urlSession
    }

    public static func make(
        profile: StorageProfile,
        credentials: S3Credentials?,
        urlSession: URLSession = .shared
    ) throws -> S3UploadProvider {
        guard !profile.s3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw S3UploadError.missingBucket
        }

        guard !profile.s3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw S3UploadError.missingEndpoint
        }

        guard let credentials,
              !credentials.accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw S3UploadError.missingCredentials
        }

        guard let endpoint = URL(string: profile.s3Endpoint), endpoint.scheme != nil, endpoint.host != nil else {
            throw S3UploadError.invalidEndpoint
        }

        return S3UploadProvider(
            bucket: profile.s3Bucket,
            region: profile.s3Region.isEmpty ? "auto" : profile.s3Region,
            endpoint: endpoint,
            usePathStyle: profile.s3UsePathStyle,
            publicBaseURL: profile.publicBaseURL,
            credentials: credentials,
            urlSession: urlSession
        )
    }

    public func upload(payload: ImagePayload, objectKey: String, now: Date = Date()) async throws -> UploadResult {
        var request = try signedPutRequest(payload: payload, objectKey: objectKey, now: now)
        request.httpBody = payload.data

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3UploadError.missingHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw S3UploadError.invalidResponse(
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

    public func signedPutRequest(payload: ImagePayload, objectKey: String, now: Date = Date()) throws -> URLRequest {
        let url = try requestURL(objectKey: objectKey)
        let timestamp = SigV4Timestamp(date: now)
        let payloadHash = SHA256Hash.hex(payload.data)
        let contentType = contentType(for: payload.fileExtension)
        let host = url.host ?? ""

        let headers = [
            "content-type": contentType,
            "host": host,
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": timestamp.long
        ]

        let canonicalURI = canonicalURI(for: url.path)
        let signedHeaders = headers.keys.sorted().joined(separator: ";")
        let canonicalHeaders = headers.keys.sorted().map { "\($0):\(headers[$0]!)\n" }.joined()
        let canonicalRequest = [
            "PUT",
            canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")
        let canonicalRequestHash = SHA256Hash.hex(Data(canonicalRequest.utf8))
        let credentialScope = "\(timestamp.short)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            timestamp.long,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")
        let signature = Self.hexHMAC(key: signingKey(date: timestamp.short), message: stringToSign)
        let authorization = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(timestamp.long, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private func requestURL(objectKey: String) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              let host = components.host else {
            throw S3UploadError.invalidEndpoint
        }

        let cleanKey = objectKey
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")

        if usePathStyle {
            components.path = "/\(bucket)/\(cleanKey)"
        } else {
            components.host = "\(bucket).\(host)"
            components.path = "/\(cleanKey)"
        }

        guard let url = components.url else {
            throw S3UploadError.invalidRequestURL
        }

        return url
    }

    private func canonicalURI(for path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    private func signingKey(date: String) -> SymmetricKey {
        let kDate = Self.hmac(key: Data("AWS4\(credentials.secretKey)".utf8), message: date)
        let kRegion = Self.hmac(key: kDate, message: region)
        let kService = Self.hmac(key: kRegion, message: "s3")
        let kSigning = Self.hmac(key: kService, message: "aws4_request")
        return SymmetricKey(data: kSigning)
    }

    private static func hmac(key: Data, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    private static func hexHMAC(key: SymmetricKey, message: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()
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

private struct SigV4Timestamp {
    let short: String
    let long: String

    init(date: Date) {
        let shortFormatter = DateFormatter()
        shortFormatter.calendar = Calendar(identifier: .gregorian)
        shortFormatter.locale = Locale(identifier: "en_US_POSIX")
        shortFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        shortFormatter.dateFormat = "yyyyMMdd"

        let longFormatter = DateFormatter()
        longFormatter.calendar = Calendar(identifier: .gregorian)
        longFormatter.locale = Locale(identifier: "en_US_POSIX")
        longFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        longFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        short = shortFormatter.string(from: date)
        long = longFormatter.string(from: date)
    }
}
