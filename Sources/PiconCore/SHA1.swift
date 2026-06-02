import CryptoKit
import Foundation

enum SHA1Hash {
    static func hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum HMACSHA1 {
    static func hex(key: Data, message: String) -> String {
        HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: key)
        )
        .map { String(format: "%02x", $0) }
        .joined()
    }
}
