import Foundation

public enum MarkdownFormatter {
    public static func image(url: String) -> String {
        "![](\(url))"
    }
}
