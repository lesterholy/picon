import AppKit
import Combine
import Foundation
import PiconCore

struct ImageEntry: Identifiable, Equatable {
    var id: UUID { record.id }
    var record: ImageRecord
    var image: NSImage
    var payload: ImagePayload?
}

enum BatchStatus: String, Equatable {
    case idle
    case ready
    case uploading
    case completed
    case failed
}

struct BatchUploadItem: Identifiable, Equatable {
    var id = UUID()
    var fileURL: URL
    var relativePath: String
    var objectKey: String
    var status: UploadStatus = .pending
    var markdown: String?
    var errorMessage: String?
}

struct BatchUpload: Identifiable, Equatable {
    var id = UUID()
    var folderURL: URL
    var profileName: String
    var status: BatchStatus = .ready
    var items: [BatchUploadItem]

    var uploadedCount: Int { items.filter { $0.status == .uploaded }.count }
    var failedCount: Int { items.filter { $0.status == .failed }.count }
    var pendingCount: Int { items.filter { $0.status == .pending }.count }
    var totalCount: Int { items.count }
    var markdownOutput: String {
        items.compactMap(\.markdown).joined(separator: "\n")
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var pending: [ImageEntry] = []
    @Published private(set) var uploaded: [ImageEntry] = []
    @Published private(set) var batch: BatchUpload?
    @Published private(set) var lastMessage: String = "Copy an image, then click it here to upload."
    @Published var settings: AppSettings {
        didSet {
            saveSettings()
            refreshPendingObjectKeys()
        }
    }

    let applicationSupportDirectory: URL
    let uploadDirectory: URL

    private let historyStore: HistoryStore
    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private let uploadQueue = DispatchQueue(label: "Picon.UploadQueue", qos: .userInitiated)
    private var knownHashes = Set<String>()
    private let batchConcurrency = 3

    init(fileManager: FileManager = .default) {
        let supportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        applicationSupportDirectory = supportBase.appendingPathComponent("Picon", isDirectory: true)
        uploadDirectory = applicationSupportDirectory.appendingPathComponent("uploads", isDirectory: true)
        historyStore = HistoryStore(fileURL: applicationSupportDirectory.appendingPathComponent("history.json"))
        settings = Self.loadSettings(defaults: defaults)

        loadHistory()
    }

    func addClipboardImage(_ clipboardImage: ClipboardImage) {
        guard !knownHashes.contains(clipboardImage.payload.contentHash) else {
            lastMessage = "Image already exists in Picon."
            return
        }

        let thumbnailURL = thumbnailURL(for: UUID())
        let objectKey = objectKey(for: clipboardImage.payload)
        let record = ImageRecord(
            id: UUID(),
            originalFileName: clipboardImage.payload.originalFileName,
            objectKey: objectKey,
            status: .pending,
            contentHash: clipboardImage.payload.contentHash,
            thumbnailPath: thumbnailURL.path
        )

        saveThumbnail(clipboardImage.image, to: thumbnailURL)
        knownHashes.insert(clipboardImage.payload.contentHash)
        pending.insert(ImageEntry(record: record, image: clipboardImage.image, payload: clipboardImage.payload), at: 0)
        lastMessage = "Ready: click the pending image to upload."
    }

    func uploadPending(id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else {
            return
        }

        var entry = pending[index]
        guard let payload = entry.payload else {
            entry.record.status = .failed
            entry.record.errorMessage = "Missing image data."
            pending[index] = entry
            return
        }

        entry.record.status = .uploading
        entry.record.errorMessage = nil
        pending[index] = entry
        lastMessage = "Uploading \(entry.record.objectKey)..."

        let objectKey = entry.record.objectKey
        let profile = settings.defaultProfile
        let uploadRoot = resolvedUploadDirectory(profile: profile)
        let qiniuCredentials = keychain.loadQiniuCredentials(profileID: profile.id)
        let s3Credentials = keychain.loadS3Credentials(profileID: profile.id)
        let tencentCOSCredentials = keychain.loadTencentCOSCredentials(profileID: profile.id)

        uploadQueue.async { [weak self] in
            guard let self else {
                return
            }

            Task {
                do {
                    let result: UploadResult
                    switch profile.provider {
                    case .local:
                        let provider = LocalUploadProvider(rootDirectory: uploadRoot, publicBaseURL: profile.publicBaseURL)
                        result = try provider.upload(payload: payload, objectKey: objectKey)
                    case .qiniu:
                        let provider = try QiniuUploadProvider.make(
                            profile: profile,
                            credentials: qiniuCredentials
                        )
                        result = try await provider.upload(payload: payload, objectKey: objectKey)
                    case .s3:
                        let provider = try S3UploadProvider.make(
                            profile: profile,
                            credentials: s3Credentials
                        )
                        result = try await provider.upload(payload: payload, objectKey: objectKey)
                    case .tencentCOS:
                        let provider = try TencentCOSUploadProvider.make(
                            profile: profile,
                            credentials: tencentCOSCredentials
                        )
                        result = try await provider.upload(payload: payload, objectKey: objectKey)
                    }

                    Task { @MainActor in
                        self.completeUpload(id: id, result: result)
                    }
                } catch {
                    let message = String(describing: error)
                    Task { @MainActor in
                        self.failUpload(id: id, message: message)
                    }
                }
            }
        }
    }

    func copyMarkdown(id: UUID) {
        guard let entry = uploaded.first(where: { $0.id == id }), let markdown = entry.record.markdown else {
            return
        }

        copyToPasteboard(markdown)
        lastMessage = "Copied \(markdown)"
    }

    func removePending(id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else {
            return
        }

        knownHashes.remove(pending[index].record.contentHash)
        pending.remove(at: index)
        lastMessage = "Removed pending image."
    }

    func revealUploadDirectory() {
        try? FileManager.default.createDirectory(at: resolvedUploadDirectory(profile: settings.defaultProfile), withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([resolvedUploadDirectory(profile: settings.defaultProfile)])
    }

    func chooseFolderForBatchUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        prepareBatchUpload(folderURL: folderURL)
    }

    func prepareBatchUpload(folderURL: URL) {
        let profile = settings.defaultProfile

        do {
            let fileURLs = try scanImageFiles(in: folderURL)
            let items = try fileURLs.enumerated().map { index, fileURL in
                let relativePath = relativePath(for: fileURL, base: folderURL)
                let data = try Data(contentsOf: fileURL)
                let ext = normalizedImageExtension(fileURL.pathExtension)
                let objectKey = ObjectKeyTemplate.render(
                    batchNamingTemplate(for: profile),
                    context: ObjectKeyContext(
                        originalFileName: fileURL.lastPathComponent,
                        relativePath: relativePath,
                        fileExtension: ext,
                        contentHash: Hashing.fnv1a64Hex(data),
                        index: index + 1
                    )
                )
                return BatchUploadItem(fileURL: fileURL, relativePath: relativePath, objectKey: objectKey)
            }

            batch = BatchUpload(folderURL: folderURL, profileName: profile.name, items: items)
            lastMessage = items.isEmpty ? "No images found in selected folder." : "Ready to upload \(items.count) images with \(profile.name)."
        } catch {
            batch = nil
            lastMessage = "Folder scan failed: \(error)"
        }
    }

    func startBatchUpload() {
        guard var currentBatch = batch, currentBatch.status != .uploading else {
            return
        }

        currentBatch.status = .uploading
        batch = currentBatch
        lastMessage = "Batch upload started."
        runBatchUpload(itemIDs: currentBatch.items.filter { $0.status == .pending || $0.status == .failed }.map(\.id))
    }

    func retryFailedBatchItems() {
        guard let currentBatch = batch else {
            return
        }

        let failedIDs = currentBatch.items.filter { $0.status == .failed }.map(\.id)
        guard !failedIDs.isEmpty else {
            return
        }

        updateBatchStatus(.uploading)
        runBatchUpload(itemIDs: failedIDs)
    }

    func copyBatchMarkdown() {
        guard let markdown = batch?.markdownOutput, !markdown.isEmpty else {
            lastMessage = "No batch Markdown links to copy."
            return
        }

        copyToPasteboard(markdown)
        lastMessage = "Copied \(batch?.uploadedCount ?? 0) Markdown links."
    }

    func clearBatch() {
        batch = nil
        lastMessage = "Cleared batch upload."
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        var copy = settings
        update(&copy)
        settings = copy
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            updateSettings { $0.launchAtLogin = enabled }
            lastMessage = enabled ? "Launch at login enabled." : "Launch at login disabled."
        } catch {
            updateSettings { $0.launchAtLogin = LaunchAtLoginManager.isEnabled() }
            lastMessage = "Launch at login failed: \(error)"
        }
    }

    func addProfile(kind: ProviderKind) {
        var profile = StorageProfile(name: defaultProfileName(for: kind), provider: kind)
        if kind == .local {
            profile.name = "Local Folder"
        }
        updateSettings {
            $0.profiles.append(profile)
            $0.defaultProfileID = profile.id
        }
    }

    func deleteProfile(id: UUID) {
        updateSettings {
            guard $0.profiles.count > 1 else {
                return
            }
            $0.profiles.removeAll { $0.id == id }
            $0.normalize()
        }
    }

    func duplicateProfile(id: UUID) -> UUID? {
        guard let source = settings.profiles.first(where: { $0.id == id }) else {
            return nil
        }

        var duplicate = source
        duplicate.id = UUID()
        duplicate.name = duplicateName(for: source.name)

        updateSettings {
            $0.profiles.append(duplicate)
            $0.defaultProfileID = duplicate.id
        }

        keychain.copyCredentials(provider: source.provider, from: source.id, to: duplicate.id)
        lastMessage = "Duplicated storage profile."
        return duplicate.id
    }

    func updateProfile(id: UUID, _ update: (inout StorageProfile) -> Void) {
        updateSettings {
            guard let index = $0.profiles.firstIndex(where: { $0.id == id }) else {
                return
            }
            update(&$0.profiles[index])
        }
    }

    func setDefaultProfile(id: UUID) {
        updateSettings { $0.defaultProfileID = id }
        lastMessage = "Default storage profile updated."
    }

    func loadQiniuCredentials(profileID: UUID) -> QiniuCredentials? {
        keychain.loadQiniuCredentials(profileID: profileID)
    }

    func saveQiniuCredentials(profileID: UUID, accessKey: String, secretKey: String) {
        let current = keychain.loadQiniuCredentials(profileID: profileID)
        let resolvedAccessKey = accessKey.isEmpty ? current?.accessKey ?? "" : accessKey
        let resolvedSecretKey = secretKey.isEmpty ? current?.secretKey ?? "" : secretKey
        keychain.saveQiniuCredentials(profileID: profileID, accessKey: resolvedAccessKey, secretKey: resolvedSecretKey)
        lastMessage = "Saved Qiniu credentials in Keychain."
    }

    func loadS3Credentials(profileID: UUID) -> S3Credentials? {
        keychain.loadS3Credentials(profileID: profileID)
    }

    func saveS3Credentials(profileID: UUID, accessKey: String, secretKey: String) {
        let current = keychain.loadS3Credentials(profileID: profileID)
        let resolvedAccessKey = accessKey.isEmpty ? current?.accessKey ?? "" : accessKey
        let resolvedSecretKey = secretKey.isEmpty ? current?.secretKey ?? "" : secretKey
        keychain.saveS3Credentials(profileID: profileID, accessKey: resolvedAccessKey, secretKey: resolvedSecretKey)
        lastMessage = "Saved S3 credentials in Keychain."
    }

    func loadTencentCOSCredentials(profileID: UUID) -> TencentCOSCredentials? {
        keychain.loadTencentCOSCredentials(profileID: profileID)
    }

    func saveTencentCOSCredentials(profileID: UUID, secretID: String, secretKey: String) {
        let current = keychain.loadTencentCOSCredentials(profileID: profileID)
        let resolvedSecretID = secretID.isEmpty ? current?.secretID ?? "" : secretID
        let resolvedSecretKey = secretKey.isEmpty ? current?.secretKey ?? "" : secretKey
        keychain.saveTencentCOSCredentials(profileID: profileID, secretID: resolvedSecretID, secretKey: resolvedSecretKey)
        lastMessage = "Saved Tencent COS credentials in Keychain."
    }

    func testProfile(id: UUID) -> String {
        guard let profile = settings.profiles.first(where: { $0.id == id }) else {
            return "Test failed: profile not found."
        }

        do {
            let payload = ImagePayload(
                data: Data([0x89, 0x50, 0x4e, 0x47]),
                originalFileName: "picon-test.png",
                fileExtension: "png",
                contentHash: "picon-test"
            )
            let objectKey = ObjectKeyTemplate.render(
                profile.namingTemplate,
                context: ObjectKeyContext(
                    originalFileName: payload.originalFileName,
                    fileExtension: payload.fileExtension,
                    contentHash: payload.contentHash
                )
            )

            switch profile.provider {
            case .local:
                let directory = resolvedUploadDirectory(profile: profile)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                return "Test passed: local folder is writable."
            case .qiniu:
                let provider = try QiniuUploadProvider.make(
                    profile: profile,
                    credentials: keychain.loadQiniuCredentials(profileID: profile.id)
                )
                _ = provider.uploadToken(objectKey: objectKey)
                return "Test passed: Qiniu configuration and upload token are valid."
            case .s3:
                let provider = try S3UploadProvider.make(
                    profile: profile,
                    credentials: keychain.loadS3Credentials(profileID: profile.id)
                )
                _ = try provider.signedPutRequest(payload: payload, objectKey: objectKey)
                return "Test passed: S3-compatible signed PUT request can be generated."
            case .tencentCOS:
                let provider = try TencentCOSUploadProvider.make(
                    profile: profile,
                    credentials: keychain.loadTencentCOSCredentials(profileID: profile.id)
                )
                _ = try provider.signedPutRequest(payload: payload, objectKey: objectKey)
                return "Test passed: Tencent COS authorization can be generated."
            }
        } catch {
            return "Test failed: \(error)"
        }
    }

    func scanPasteboardNow() {
        lastMessage = "Watching clipboard. Copy an image to add it."
    }

    private func runBatchUpload(itemIDs: [UUID]) {
        guard !itemIDs.isEmpty else {
            updateBatchCompletionState()
            return
        }

        let profile = settings.defaultProfile
        let uploadRoot = resolvedUploadDirectory(profile: profile)
        let qiniuCredentials = keychain.loadQiniuCredentials(profileID: profile.id)
        let s3Credentials = keychain.loadS3Credentials(profileID: profile.id)
        let tencentCOSCredentials = keychain.loadTencentCOSCredentials(profileID: profile.id)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let model = self else {
                return
            }
            let concurrency = await MainActor.run { model.batchConcurrency }
            await withTaskGroup(of: Void.self) { group in
                var iterator = itemIDs.makeIterator()

                for _ in 0..<concurrency {
                    guard let itemID = iterator.next() else {
                        break
                    }
                    group.addTask {
                        await model.uploadBatchItem(
                            itemID: itemID,
                            profile: profile,
                            uploadRoot: uploadRoot,
                            qiniuCredentials: qiniuCredentials,
                            s3Credentials: s3Credentials,
                            tencentCOSCredentials: tencentCOSCredentials
                        )
                    }
                }

                while await group.next() != nil {
                    guard let itemID = iterator.next() else {
                        continue
                    }
                    group.addTask {
                        await model.uploadBatchItem(
                            itemID: itemID,
                            profile: profile,
                            uploadRoot: uploadRoot,
                            qiniuCredentials: qiniuCredentials,
                            s3Credentials: s3Credentials,
                            tencentCOSCredentials: tencentCOSCredentials
                        )
                    }
                }
            }

            await MainActor.run {
                model.updateBatchCompletionState()
            }
        }
    }

    private func uploadBatchItem(
        itemID: UUID,
        profile: StorageProfile,
        uploadRoot: URL,
        qiniuCredentials: QiniuCredentials?,
        s3Credentials: S3Credentials?,
        tencentCOSCredentials: TencentCOSCredentials?
    ) async {
        guard let snapshot = await MainActor.run(body: { batchItemSnapshot(id: itemID) }) else {
            return
        }

        await MainActor.run {
            markBatchItem(itemID, status: .uploading, markdown: nil, errorMessage: nil)
        }

        do {
            let data = try Data(contentsOf: snapshot.fileURL)
            let payload = ImagePayload(
                data: data,
                originalFileName: snapshot.fileURL.lastPathComponent,
                fileExtension: normalizedImageExtension(snapshot.fileURL.pathExtension),
                contentHash: Hashing.fnv1a64Hex(data)
            )
            let result = try await upload(payload: payload, objectKey: snapshot.objectKey, profile: profile, uploadRoot: uploadRoot, qiniuCredentials: qiniuCredentials, s3Credentials: s3Credentials, tencentCOSCredentials: tencentCOSCredentials)
            await MainActor.run {
                markBatchItem(itemID, status: .uploaded, markdown: result.markdown, errorMessage: nil)
            }
        } catch {
            await MainActor.run {
                markBatchItem(itemID, status: .failed, markdown: nil, errorMessage: String(describing: error))
            }
        }
    }

    private func upload(
        payload: ImagePayload,
        objectKey: String,
        profile: StorageProfile,
        uploadRoot: URL,
        qiniuCredentials: QiniuCredentials?,
        s3Credentials: S3Credentials?,
        tencentCOSCredentials: TencentCOSCredentials?
    ) async throws -> UploadResult {
        switch profile.provider {
        case .local:
            let provider = LocalUploadProvider(rootDirectory: uploadRoot, publicBaseURL: profile.publicBaseURL)
            return try provider.upload(payload: payload, objectKey: objectKey)
        case .qiniu:
            let provider = try QiniuUploadProvider.make(profile: profile, credentials: qiniuCredentials)
            return try await provider.upload(payload: payload, objectKey: objectKey)
        case .s3:
            let provider = try S3UploadProvider.make(profile: profile, credentials: s3Credentials)
            return try await provider.upload(payload: payload, objectKey: objectKey)
        case .tencentCOS:
            let provider = try TencentCOSUploadProvider.make(profile: profile, credentials: tencentCOSCredentials)
            return try await provider.upload(payload: payload, objectKey: objectKey)
        }
    }

    private func batchItemSnapshot(id: UUID) -> BatchUploadItem? {
        batch?.items.first { $0.id == id }
    }

    private func markBatchItem(_ id: UUID, status: UploadStatus, markdown: String?, errorMessage: String?) {
        guard var currentBatch = batch, let index = currentBatch.items.firstIndex(where: { $0.id == id }) else {
            return
        }

        currentBatch.items[index].status = status
        currentBatch.items[index].markdown = markdown
        currentBatch.items[index].errorMessage = errorMessage
        batch = currentBatch
    }

    private func updateBatchStatus(_ status: BatchStatus) {
        guard var currentBatch = batch else {
            return
        }
        currentBatch.status = status
        batch = currentBatch
    }

    private func updateBatchCompletionState() {
        guard var currentBatch = batch else {
            return
        }

        currentBatch.status = currentBatch.failedCount > 0 ? .failed : .completed
        batch = currentBatch
        lastMessage = "Batch upload: \(currentBatch.uploadedCount)/\(currentBatch.totalCount) uploaded, \(currentBatch.failedCount) failed."
    }

    private func completeUpload(id: UUID, result: UploadResult) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else {
            return
        }

        var entry = pending.remove(at: index)
        entry.record.status = .uploaded
        entry.record.objectKey = result.objectKey
        entry.record.publicURL = result.publicURL
        entry.record.markdown = result.markdown
        entry.record.localFilePath = result.localFilePath
        entry.record.uploadedAt = Date()
        uploaded.insert(entry, at: 0)
        persistUploadedHistory()
        copyToPasteboard(result.markdown)
        lastMessage = "Uploaded and copied \(result.markdown)"
    }

    private func failUpload(id: UUID, message: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else {
            return
        }

        pending[index].record.status = .failed
        pending[index].record.errorMessage = message
        lastMessage = "Upload failed: \(message)"
    }

    private func objectKey(for payload: ImagePayload) -> String {
        ObjectKeyTemplate.render(
            settings.defaultProfile.namingTemplate,
            context: ObjectKeyContext(
                originalFileName: payload.originalFileName,
                fileExtension: payload.fileExtension,
                date: payload.createdAt,
                contentHash: payload.contentHash
            )
        )
    }

    private func batchNamingTemplate(for profile: StorageProfile) -> String {
        ObjectKeyTemplate.batchTemplate(from: profile.namingTemplate)
    }

    private func refreshPendingObjectKeys() {
        pending = pending.map { entry in
            var mutable = entry
            if let payload = mutable.payload {
                mutable.record.objectKey = objectKey(for: payload)
            }
            return mutable
        }
    }

    private func resolvedUploadDirectory(profile: StorageProfile) -> URL {
        if let path = profile.localUploadDirectory, !path.isEmpty {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
        }

        return uploadDirectory
    }

    private func scanImageFiles(in folderURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, isSupportedImage(url) else {
                continue
            }
            urls.append(url)
        }
        return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isSupportedImage(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "heic"].contains(normalizedImageExtension(url.pathExtension))
    }

    private func normalizedImageExtension(_ value: String) -> String {
        let normalized = value.lowercased()
        return normalized == "jpeg" ? "jpg" : (normalized.isEmpty ? "png" : normalized)
    }

    private func relativePath(for fileURL: URL, base folderURL: URL) -> String {
        let basePath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath) else {
            return fileURL.lastPathComponent
        }

        let relative = String(filePath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }

    private func thumbnailURL(for id: UUID) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent("\(id.uuidString.lowercased()).png", isDirectory: false)
    }

    private func saveThumbnail(_ image: NSImage, to url: URL) {
        guard let data = image.pngData(maxPixelSize: 320) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            lastMessage = "Could not save thumbnail: \(error)"
        }
    }

    private func loadHistory() {
        do {
            let records = try historyStore.load()
            uploaded = records.compactMap { record in
                let image = record.thumbnailPath.flatMap { NSImage(contentsOfFile: $0) } ?? NSImage()
                knownHashes.insert(record.contentHash)
                return ImageEntry(record: record, image: image, payload: nil)
            }
        } catch {
            lastMessage = "Could not load history: \(error)"
        }
    }

    private func persistUploadedHistory() {
        do {
            let records = uploaded.map(\.record)
            try historyStore.save(records)
        } catch {
            lastMessage = "Could not save history: \(error)"
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private static func loadSettings(defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: "Picon.Settings"),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            if let modernLegacy = loadModernLegacySettings(defaults: defaults) {
                return modernLegacy
            }
            if let legacy = loadLegacySettings(defaults: defaults) {
                return legacy
            }
            return .default
        }

        settings.normalize()
        settings.launchAtLogin = LaunchAtLoginManager.isEnabled()
        return settings
    }

    private static func loadModernLegacySettings(defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: "Picon.Settings"),
              let legacy = try? JSONDecoder().decode(ModernLegacySettings.self, from: data) else {
            return nil
        }

        var settings = AppSettings(
            profiles: legacy.profiles,
            defaultProfileID: legacy.defaultProfileID,
            launchAtLogin: LaunchAtLoginManager.isEnabled()
        )
        settings.normalize()
        return settings
    }

    private static func loadLegacySettings(defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: "Picon.Settings"),
              let legacy = try? JSONDecoder().decode(LegacyAppSettings.self, from: data) else {
            return nil
        }

        let profile = StorageProfile(
            name: legacy.provider.displayName,
            provider: legacy.provider,
            publicBaseURL: legacy.publicBaseURL,
            namingTemplate: legacy.namingTemplate,
            localUploadDirectory: legacy.localUploadDirectory,
            qiniuBucket: legacy.qiniuBucket,
            qiniuUploadURL: legacy.qiniuUploadURL,
            s3Bucket: legacy.s3Bucket,
            s3Region: legacy.s3Region,
            s3Endpoint: legacy.s3Endpoint,
            s3UsePathStyle: legacy.s3UsePathStyle,
            tencentCOSBucket: legacy.tencentCOSBucket,
            tencentCOSRegion: legacy.tencentCOSRegion
        )
        return AppSettings(profiles: [profile], defaultProfileID: profile.id, launchAtLogin: LaunchAtLoginManager.isEnabled())
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: "Picon.Settings")
    }

    private func defaultProfileName(for kind: ProviderKind) -> String {
        let existing = settings.profiles.filter { $0.provider == kind }.count
        return existing == 0 ? kind.displayName : "\(kind.displayName) \(existing + 1)"
    }

    private func duplicateName(for name: String) -> String {
        let base = "\(name) Copy"
        guard settings.profiles.contains(where: { $0.name == base }) else {
            return base
        }

        var index = 2
        while settings.profiles.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }
}

private struct ModernLegacySettings: Codable {
    var profiles: [StorageProfile]
    var defaultProfileID: UUID
}

private struct LegacyAppSettings: Codable {
    var provider: ProviderKind
    var publicBaseURL: String
    var namingTemplate: String
    var localUploadDirectory: String?
    var qiniuBucket: String
    var qiniuUploadURL: String
    var s3Bucket: String
    var s3Region: String
    var s3Endpoint: String
    var s3UsePathStyle: Bool
    var tencentCOSBucket: String
    var tencentCOSRegion: String
}
