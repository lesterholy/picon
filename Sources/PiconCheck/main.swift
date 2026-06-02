import Foundation
import PiconCore

let testAccessValue = "dummy-access-value"
let testSecretValue = "dummy-secret-value"

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("PiconCheck-\(UUID().uuidString)", isDirectory: true)
defer {
    try? FileManager.default.removeItem(at: root)
}

let payload = ImagePayload(
    data: Data([0x89, 0x50, 0x4e, 0x47]),
    originalFileName: "Pont BL.png",
    fileExtension: "png",
    contentHash: "abcdef1234567890",
    createdAt: Date(timeIntervalSince1970: 1_704_153_845)
)
let profileA = StorageProfile(
    id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
    name: "A",
    provider: .qiniu,
    publicBaseURL: "https://a.example.com"
)
let profileB = StorageProfile(
    id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
    name: "B",
    provider: .s3,
    publicBaseURL: "https://b.example.com"
)
let multiSettings = AppSettings(profiles: [profileA, profileB], defaultProfileID: profileB.id)

guard multiSettings.defaultProfile.id == profileB.id else {
    fatalError("Default storage profile was not resolved")
}

let localProfile = StorageProfile(
    id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
    name: "Local",
    provider: .local,
    localUploadDirectory: root.path
)
let localSettings = AppSettings(profiles: [localProfile], defaultProfileID: localProfile.id)

guard localSettings.defaultProfile.provider == .local else {
    fatalError("Local default profile was not resolved")
}

let objectKey = ObjectKeyTemplate.render(
    "ob/{yyyy}/{MM}/{dd}/{slug}-{hash}.{ext}",
    context: ObjectKeyContext(
        originalFileName: payload.originalFileName,
        fileExtension: payload.fileExtension,
        date: payload.createdAt,
        uuid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        contentHash: payload.contentHash
    )
)

guard objectKey == "ob/2024/01/02/pont-bl-abcdef123456.png" else {
    fatalError("Unexpected object key: \(objectKey)")
}

let provider = LocalUploadProvider(rootDirectory: root, publicBaseURL: "https://images.example.com")
let result = try provider.upload(payload: payload, objectKey: objectKey)

guard FileManager.default.fileExists(atPath: root.appendingPathComponent(objectKey).path) else {
    fatalError("Uploaded file was not written")
}

guard result.markdown.hasPrefix("![](file://") else {
    fatalError("Unexpected markdown: \(result.markdown)")
}

let hostedMarkdown = MarkdownFormatter.image(
    url: ObjectKeyTemplate.publicURL(baseURL: "https://images.example.com", objectKey: objectKey)
)

guard hostedMarkdown == "![](https://images.example.com/ob/2024/01/02/pont-bl-abcdef123456.png)" else {
    fatalError("Unexpected hosted markdown: \(hostedMarkdown)")
}

let batchObjectKey = ObjectKeyTemplate.render(
    "ob/{relativePath}-{hash}.{ext}",
    context: ObjectKeyContext(
        originalFileName: "cover.png",
        relativePath: "posts/a/cover.png",
        fileExtension: "png",
        contentHash: "abcdef1234567890",
        index: 12
    )
)

guard batchObjectKey == "ob/posts/a/cover-abcdef123456.png" else {
    fatalError("Unexpected batch object key: \(batchObjectKey)")
}

let prefixedBatchTemplate = ObjectKeyTemplate.batchTemplate(from: "blog/{uuid}.{ext}")
guard prefixedBatchTemplate == "blog/{relativePath}-{hash}.{ext}" else {
    fatalError("Unexpected prefixed batch template: \(prefixedBatchTemplate)")
}

let qiniu = QiniuUploadProvider(
    bucket: "bucket",
    uploadURL: URL(string: "https://upload.qiniup.com")!,
    publicBaseURL: "https://images.example.com",
    credentials: QiniuCredentials(accessKey: testAccessValue, secretKey: testSecretValue)
)
let token = qiniu.uploadToken(objectKey: objectKey, deadline: 1_704_157_445)

guard token.split(separator: ":").count == 3 else {
    fatalError("Unexpected Qiniu upload token format: \(token)")
}

let s3 = S3UploadProvider(
    bucket: "bucket",
    region: "auto",
    endpoint: URL(string: "https://example.r2.cloudflarestorage.com")!,
    usePathStyle: true,
    publicBaseURL: "https://images.example.com",
    credentials: S3Credentials(accessKey: testAccessValue, secretKey: testSecretValue)
)
let request = try s3.signedPutRequest(
    payload: payload,
    objectKey: objectKey,
    now: Date(timeIntervalSince1970: 1_704_157_445)
)

guard request.url?.absoluteString == "https://example.r2.cloudflarestorage.com/bucket/ob/2024/01/02/pont-bl-abcdef123456.png" else {
    fatalError("Unexpected S3 request URL: \(request.url?.absoluteString ?? "nil")")
}

guard request.value(forHTTPHeaderField: "Authorization")?.contains("AWS4-HMAC-SHA256") == true else {
    fatalError("Missing S3 authorization header")
}

let tiffPayload = ImagePayload(
    data: Data([0x49, 0x49, 0x2a, 0x00]),
    originalFileName: "scan.tif",
    fileExtension: "tif",
    contentHash: "abcdef1234567890"
)
let tiffRequest = try s3.signedPutRequest(payload: tiffPayload, objectKey: "ob/scan.tif")
guard tiffRequest.value(forHTTPHeaderField: "Content-Type") == "image/tiff" else {
    fatalError("Unexpected TIFF content type: \(tiffRequest.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
}

let cos = TencentCOSUploadProvider(
    bucket: "examplebucket-1234567890",
    region: "ap-shanghai",
    publicBaseURL: "https://images.example.com",
    credentials: TencentCOSCredentials(secretID: "dummy-secret-id", secretKey: testSecretValue)
)
let cosRequest = try cos.signedPutRequest(
    payload: payload,
    objectKey: objectKey,
    now: Date(timeIntervalSince1970: 1_704_157_445)
)

guard cosRequest.url?.absoluteString == "https://examplebucket-1234567890.cos.ap-shanghai.myqcloud.com/ob/2024/01/02/pont-bl-abcdef123456.png" else {
    fatalError("Unexpected COS request URL: \(cosRequest.url?.absoluteString ?? "nil")")
}

guard cosRequest.value(forHTTPHeaderField: "Authorization")?.contains("q-sign-algorithm=sha1") == true else {
    fatalError("Missing COS authorization header")
}

let cosTiffRequest = try cos.signedPutRequest(payload: tiffPayload, objectKey: "ob/scan.tif")
guard cosTiffRequest.value(forHTTPHeaderField: "Content-Type") == "image/tiff" else {
    fatalError("Unexpected COS TIFF content type: \(cosTiffRequest.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
}

print("PiconCheck OK")
print(hostedMarkdown)
