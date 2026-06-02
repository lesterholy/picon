import Foundation
import Security
import PiconCore

final class KeychainStore {
    private let service = "com.picon.image-host"

    func loadQiniuCredentials(profileID: UUID) -> QiniuCredentials? {
        guard let accessKey = read(account: account(profileID: profileID, key: "qiniu.accessKey")) ?? read(account: "qiniu.accessKey"),
              let secretKey = read(account: account(profileID: profileID, key: "qiniu.secretKey")) ?? read(account: "qiniu.secretKey") else {
            return nil
        }

        return QiniuCredentials(accessKey: accessKey, secretKey: secretKey)
    }

    func saveQiniuCredentials(profileID: UUID, accessKey: String, secretKey: String) {
        save(account: account(profileID: profileID, key: "qiniu.accessKey"), value: accessKey)
        save(account: account(profileID: profileID, key: "qiniu.secretKey"), value: secretKey)
    }

    func loadS3Credentials(profileID: UUID) -> S3Credentials? {
        guard let accessKey = read(account: account(profileID: profileID, key: "s3.accessKey")) ?? read(account: "s3.accessKey"),
              let secretKey = read(account: account(profileID: profileID, key: "s3.secretKey")) ?? read(account: "s3.secretKey") else {
            return nil
        }

        return S3Credentials(accessKey: accessKey, secretKey: secretKey)
    }

    func saveS3Credentials(profileID: UUID, accessKey: String, secretKey: String) {
        save(account: account(profileID: profileID, key: "s3.accessKey"), value: accessKey)
        save(account: account(profileID: profileID, key: "s3.secretKey"), value: secretKey)
    }

    func loadTencentCOSCredentials(profileID: UUID) -> TencentCOSCredentials? {
        guard let secretID = read(account: account(profileID: profileID, key: "tencentCOS.secretID")) ?? read(account: "tencentCOS.secretID"),
              let secretKey = read(account: account(profileID: profileID, key: "tencentCOS.secretKey")) ?? read(account: "tencentCOS.secretKey") else {
            return nil
        }

        return TencentCOSCredentials(secretID: secretID, secretKey: secretKey)
    }

    func saveTencentCOSCredentials(profileID: UUID, secretID: String, secretKey: String) {
        save(account: account(profileID: profileID, key: "tencentCOS.secretID"), value: secretID)
        save(account: account(profileID: profileID, key: "tencentCOS.secretKey"), value: secretKey)
    }

    func copyCredentials(provider: ProviderKind, from sourceID: UUID, to destinationID: UUID) {
        switch provider {
        case .local:
            return
        case .qiniu:
            guard let credentials = loadQiniuCredentials(profileID: sourceID) else {
                return
            }
            saveQiniuCredentials(profileID: destinationID, accessKey: credentials.accessKey, secretKey: credentials.secretKey)
        case .s3:
            guard let credentials = loadS3Credentials(profileID: sourceID) else {
                return
            }
            saveS3Credentials(profileID: destinationID, accessKey: credentials.accessKey, secretKey: credentials.secretKey)
        case .tencentCOS:
            guard let credentials = loadTencentCOSCredentials(profileID: sourceID) else {
                return
            }
            saveTencentCOSCredentials(profileID: destinationID, secretID: credentials.secretID, secretKey: credentials.secretKey)
        }
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func save(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func account(profileID: UUID, key: String) -> String {
        "profile.\(profileID.uuidString.lowercased()).\(key)"
    }
}
