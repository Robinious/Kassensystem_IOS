import Foundation

enum IdempotencyKeyFactory {
    static func next(scope: String, platformPrefix: String) -> String {
        let normalizedScope = scope
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let finalScope = normalizedScope.isEmpty ? "cmd" : normalizedScope
        return "\(platformPrefix)-\(finalScope)-\(UUID().uuidString.lowercased())"
    }
}
