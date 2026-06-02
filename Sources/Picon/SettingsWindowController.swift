import AppKit
import SwiftUI
import PiconCore

final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let createdWindow = NSWindow(contentViewController: controller)
            createdWindow.title = "Picon Settings"
            createdWindow.setContentSize(NSSize(width: 780, height: 620))
            createdWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            createdWindow.isReleasedWhenClosed = false
            window = createdWindow
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedProfileID: UUID?
    @State private var qiniuAccessKey = ""
    @State private var qiniuSecretKey = ""
    @State private var s3AccessKey = ""
    @State private var s3SecretKey = ""
    @State private var tencentCOSSecretID = ""
    @State private var tencentCOSSecretKey = ""
    @State private var testResult = ""

    private var selectedProfile: StorageProfile? {
        let id = selectedProfileID ?? model.settings.defaultProfileID
        return model.settings.profiles.first { $0.id == id } ?? model.settings.profiles.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 780, minHeight: 620)
        .onAppear {
            selectedProfileID = model.settings.defaultProfileID
            clearCredentialFields()
        }
        .onChange(of: selectedProfileID) { _ in
            clearCredentialFields()
            testResult = ""
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage")
                .font(.headline)
                .padding(.top, 18)
                .padding(.horizontal, 14)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.settings.profiles) { profile in
                        let isSelected = profile.id == selectedProfile?.id
                        let isDefault = profile.id == model.settings.defaultProfileID
                        ProfileSidebarRow(profile: profile, isSelected: isSelected, isDefault: isDefault) {
                            selectedProfileID = profile.id
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Divider()

            Menu {
                Button("Qiniu") { addProfile(.qiniu) }
                Button("S3 Compatible") { addProfile(.s3) }
                Button("Tencent COS") { addProfile(.tencentCOS) }
                Button("Local Folder") { addProfile(.local) }
            } label: {
                Label("Add Storage", systemImage: "plus")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let profile = selectedProfile {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Profile")
                            .font(.title2)
                            .bold()
                        Spacer()
                        Button("Duplicate") {
                            if let duplicatedID = model.duplicateProfile(id: profile.id) {
                                selectedProfileID = duplicatedID
                                clearCredentialFields()
                            }
                        }
                        Button("Set Default") {
                            model.setDefaultProfile(id: profile.id)
                        }
                        .disabled(profile.id == model.settings.defaultProfileID)
                        Button("Delete") {
                            model.deleteProfile(id: profile.id)
                            selectedProfileID = model.settings.defaultProfileID
                        }
                        .disabled(model.settings.profiles.count <= 1)
                    }

                    formRow(label: "Startup") {
                        Toggle(
                            "Launch Picon at login",
                            isOn: Binding(
                                get: { model.settings.launchAtLogin },
                                set: { enabled in model.setLaunchAtLogin(enabled) }
                            )
                        )
                        Text("Uses a user LaunchAgent for this local app bundle.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    formRow(label: "Name") {
                        TextField(
                            "Profile name",
                            text: binding(profile.id, \.name)
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    formRow(label: "Provider") {
                        Text(profile.provider.displayName)
                            .foregroundColor(.secondary)
                        providerHelpText(profile)
                    }

                    formRow(label: "Public URL Prefix") {
                        TextField(
                            "https://images.example.com",
                            text: binding(profile.id, \.publicBaseURL)
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    formRow(label: "Naming Template") {
                        TextField(
                            "ob/{uuid}.{ext}",
                            text: binding(profile.id, \.namingTemplate)
                        )
                        .textFieldStyle(.roundedBorder)
                        Text("Tokens: {uuid}, {yyyy}, {MM}, {dd}, {HH}, {mm}, {ss}, {filename}, {slug}, {hash}, {ext}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Use a prefix here for bucket folders, for example `blog/{uuid}.{ext}` or `avatar/{uuid}.{ext}`.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    providerSettings(profile)

                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.callout)
                            .foregroundColor(testResult.hasPrefix("Test passed") ? .green : .red)
                    }
                }
                .padding(24)
            }
        } else {
            Text("No storage profile selected.")
                .foregroundColor(.secondary)
                .padding(24)
        }
    }

    @ViewBuilder
    private func providerSettings(_ profile: StorageProfile) -> some View {
        switch profile.provider {
        case .local:
            localSettings(profile)
        case .qiniu:
            qiniuSettings(profile)
        case .s3:
            s3Settings(profile)
        case .tencentCOS:
            tencentCOSSettings(profile)
        }
    }

    private func localSettings(_ profile: StorageProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            formRow(label: "Upload Folder") {
                TextField(
                    "~/Pictures/Picon",
                    text: Binding(
                        get: { selectedProfile?.localUploadDirectory ?? "" },
                        set: { value in model.updateProfile(id: profile.id) { $0.localUploadDirectory = value.isEmpty ? nil : value } }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
            Button("Reveal Default Folder") {
                model.revealUploadDirectory()
            }
            testButton(profile)
        }
    }

    private func qiniuSettings(_ profile: StorageProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            formRow(label: "Qiniu Bucket") {
                TextField("my-qiniu-bucket", text: binding(profile.id, \.qiniuBucket))
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "Upload URL") {
                TextField("https://upload.qiniup.com", text: binding(profile.id, \.qiniuUploadURL))
                    .textFieldStyle(.roundedBorder)
                Text("Use the upload endpoint for this bucket's region.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            formRow(label: "Access Key") {
                TextField("Leave blank unless changing saved key", text: $qiniuAccessKey)
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "Secret Key") {
                SecureField("Leave blank unless changing saved key", text: $qiniuSecretKey)
                    .textFieldStyle(.roundedBorder)
            }
            credentialButton("Save Qiniu Credentials") {
                model.saveQiniuCredentials(profileID: profile.id, accessKey: qiniuAccessKey, secretKey: qiniuSecretKey)
            }
            testButton(profile)
        }
    }

    private func s3Settings(_ profile: StorageProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            formRow(label: "S3 Bucket") {
                TextField("bucket-name", text: binding(profile.id, \.s3Bucket))
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "Region") {
                TextField("auto", text: binding(profile.id, \.s3Region))
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "Endpoint") {
                TextField("https://<account>.r2.cloudflarestorage.com", text: binding(profile.id, \.s3Endpoint))
                    .textFieldStyle(.roundedBorder)
                Text("Do not add folder names to the endpoint. For R2 folders, put the prefix in Naming Template, e.g. `blog/{uuid}.{ext}`.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            formRow(label: "Path Style") {
                Toggle(
                    "Use path-style URLs for S3-compatible services",
                    isOn: Binding(
                        get: { selectedProfile?.s3UsePathStyle ?? true },
                        set: { value in model.updateProfile(id: profile.id) { $0.s3UsePathStyle = value } }
                    )
                )
            }
            formRow(label: "Access Key") {
                TextField("Leave blank unless changing saved key", text: $s3AccessKey)
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "Secret Key") {
                SecureField("Leave blank unless changing saved key", text: $s3SecretKey)
                    .textFieldStyle(.roundedBorder)
            }
            credentialButton("Save S3 Credentials") {
                model.saveS3Credentials(profileID: profile.id, accessKey: s3AccessKey, secretKey: s3SecretKey)
            }
            testButton(profile)
        }
    }

    private func tencentCOSSettings(_ profile: StorageProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            formRow(label: "COS Bucket") {
                TextField("examplebucket-1234567890", text: binding(profile.id, \.tencentCOSBucket))
                    .textFieldStyle(.roundedBorder)
                Text("Use the full bucket name with APPID.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            formRow(label: "Region") {
                TextField("ap-shanghai", text: binding(profile.id, \.tencentCOSRegion))
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "SecretId") {
                TextField("Leave blank unless changing saved SecretId", text: $tencentCOSSecretID)
                    .textFieldStyle(.roundedBorder)
            }
            formRow(label: "SecretKey") {
                SecureField("Leave blank unless changing saved SecretKey", text: $tencentCOSSecretKey)
                    .textFieldStyle(.roundedBorder)
            }
            credentialButton("Save Tencent COS Credentials") {
                model.saveTencentCOSCredentials(
                    profileID: profile.id,
                    secretID: tencentCOSSecretID,
                    secretKey: tencentCOSSecretKey
                )
            }
            testButton(profile)
        }
    }

    private func providerHelpText(_ profile: StorageProfile) -> some View {
        Group {
            switch profile.provider {
            case .local:
                Text("Local Folder only saves to this Mac and copies a file:// link.")
            case .qiniu:
                Text("Qiniu uploads to this profile's bucket and uses its Public URL Prefix.")
            case .s3:
                Text("S3 Compatible supports AWS S3, Cloudflare R2, and MinIO.")
            case .tencentCOS:
                Text("Tencent COS uses the COS XML API with SecretId/SecretKey.")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func credentialButton(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
                .frame(width: 144)
            Button(title, action: action)
        }
    }

    private func testButton(_ profile: StorageProfile) -> some View {
        HStack {
            Spacer()
                .frame(width: 144)
            Button("Test Configuration") {
                testResult = model.testProfile(id: profile.id)
            }
        }
    }

    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .frame(width: 130, alignment: .trailing)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func binding(_ profileID: UUID, _ keyPath: WritableKeyPath<StorageProfile, String>) -> Binding<String> {
        Binding(
            get: { selectedProfile?[keyPath: keyPath] ?? "" },
            set: { value in model.updateProfile(id: profileID) { $0[keyPath: keyPath] = value } }
        )
    }

    private func addProfile(_ kind: ProviderKind) {
        model.addProfile(kind: kind)
        selectedProfileID = model.settings.defaultProfileID
        clearCredentialFields()
    }

    private func clearCredentialFields() {
        qiniuAccessKey = ""
        qiniuSecretKey = ""
        s3AccessKey = ""
        s3SecretKey = ""
        tencentCOSSecretID = ""
        tencentCOSSecretKey = ""
    }
}

private struct ProfileSidebarRow: View {
    let profile: StorageProfile
    let isSelected: Bool
    let isDefault: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(profile.provider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isDefault {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.medium)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
