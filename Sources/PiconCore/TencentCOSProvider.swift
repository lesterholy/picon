import Foundation

public enum TencentCOSUploadError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingBucket
    case missingRegion
    case missingCredentials
    case invalidRequestURL
    case invalidResponse(statusCode: Int, body: String)
    case missingHTTPResponse

    public var description: String {
        switch self {
        case .missingBucket:
            return "Tencent COS bucket is missing. Use the full name with APPID, for example examplebucket-1234567890."
        case .missingRegion:
            return "Tencent COS region is missing."
        case .missingCredentials:
            return "Tencent COS SecretId or SecretKey is missing."
        case .invalidRequestURL:
            return "Tencent COS request URL could not be built."
        case .invalidResponse(let statusCode, let body):
            return "Tencent COS upload failed with HTTP \(statusCode): \(body)"
        case .missingHTTPResponse:
            return "Tencent COS upload did not return an HTTP response."
        }
    }
}

public struct TencentCOSCredentials: Equatable, Sendable {
    public var secretID: String
    public var secretKey: String

    public init(secretID: String, secretKey: String) {
        self.secretID = secretID
        self.secretKey = secretKey
    }
}

public struct TencentCOSUploadProvider {
    public var bucket: String
    public var region: String
    public var publicBaseURL: String
    public var credentials: TencentCOSCredentials
    public var urlSession: URLSession

    public init(
        bucket: String,
        region: String,
        publicBaseURL: String,
        credentials: TencentCOSCredentials,
        urlSession: URLSession = .shared
    ) {
        self.bucket = bucket
        self.region = region
        self.publicBaseURL = publicBaseURL
        self.credentials = credentials
        self.urlSession = urlSession
    }

    public static func make(
        profile: StorageProfile,
        credentials: TencentCOSCredentials?,
        urlSession: URLSession = .shared
    ) throws -> TencentCOSUploadProvider {
        guard !profile.tencentCOSBucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TencentCOSUploadError.missingBucket
        }

        guard !profile.tencentCOSRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TencentCOSUploadError.missingRegion
        }

        guard let credentials,
              !credentials.secretID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TencentCOSUploadError.missingCredentials
        }

        return TencentCOSUploadProvider(
            bucket: profile.tencentCOSBucket,
            region: profile.tencentCOSRegion,
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
            throw TencentCOSUploadError.missingHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TencentCOSUploadError.invalidResponse(
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
        let host = "\(bucket).cos.\(region).myqcloud.com"
        let date = Self.rfc1123Date(now)
        let contentType = contentType(for: payload.fileExtension)
        let contentLength = String(payload.data.count)

        let headers = [
            "content-length": contentLength,
            "content-type": contentType,
            "date": date,
            "host": host
        ]
        let authorization = authorization(
            method: "put",
            path: url.path,
            headers: headers,
            now: now
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentLength, forHTTPHeaderField: "Content-Length")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(date, forHTTPHeaderField: "Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    public func authorization(method: String, path: String, headers: [String: String], now: Date = Date()) -> String {
        let start = Int(now.timeIntervalSince1970)
        let keyTime = "\(start);\(start + 3600)"
        let signKey = HMACSHA1.hex(key: Data(credentials.secretKey.utf8), message: keyTime)
        let sortedHeaderKeys = headers.keys.map { $0.lowercased() }.sorted()
        let headerList = sortedHeaderKeys.joined(separator: ";")
        let httpHeaders = sortedHeaderKeys.map { key in
            "\(Self.urlEncode(key))=\(Self.urlEncode(headers[key] ?? ""))"
        }.joined(separator: "&")
        let httpString = "\(method.lowercased())\n\(path)\n\n\(httpHeaders)\n"
        let stringToSign = "sha1\n\(keyTime)\n\(SHA1Hash.hex(Data(httpString.utf8)))\n"
        let signature = HMACSHA1.hex(key: Data(signKey.utf8), message: stringToSign)

        return [
            "q-sign-algorithm=sha1",
            "q-ak=\(credentials.secretID)",
            "q-sign-time=\(keyTime)",
            "q-key-time=\(keyTime)",
            "q-header-list=\(headerList)",
            "q-url-param-list=",
            "q-signature=\(signature)"
        ].joined(separator: "&")
    }

    private func requestURL(objectKey: String) throws -> URL {
        let host = "\(bucket).cos.\(region).myqcloud.com"
        let cleanKey = objectKey
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
        let encodedKey = cleanKey
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")

        guard let url = URL(string: "https://\(host)/\(encodedKey)") else {
            throw TencentCOSUploadError.invalidRequestURL
        }

        return url
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

    private static func rfc1123Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
