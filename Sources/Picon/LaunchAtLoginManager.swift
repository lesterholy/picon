import Foundation

enum LaunchAtLoginError: Error, CustomStringConvertible {
    case appBundleNotFound
    case invalidHomeDirectory

    var description: String {
        switch self {
        case .appBundleNotFound:
            return "Picon.app bundle could not be found. Run from build/Picon.app before enabling launch at login."
        case .invalidHomeDirectory:
            return "Home directory could not be found."
        }
    }
}

struct LaunchAtLoginManager {
    static let label = "local.picon.imagehost.login"

    static var launchAgentURL: URL? {
        guard let home = FileManager.default.homeDirectoryForCurrentUser.path.removingPercentEncoding else {
            return nil
        }
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static func isEnabled() -> Bool {
        guard let launchAgentURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private static func enable() throws {
        guard let launchAgentURL else {
            throw LaunchAtLoginError.invalidHomeDirectory
        }

        let appURL = try currentAppBundleURL()
        let directory = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", appURL.path],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private static func disable() throws {
        guard let launchAgentURL else {
            throw LaunchAtLoginError.invalidHomeDirectory
        }

        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private static func currentAppBundleURL() throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
        }

        let candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/Picon.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw LaunchAtLoginError.appBundleNotFound
    }
}
