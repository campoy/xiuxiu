import UIKit

/// One-tap hand-off to Day One (com.bloombuilt.dayone-ios), which is the actual destination
/// for these transcripts. `dayone2://post?entry=...` opens a new entry with the text already
/// in it, which is one step rather than the share sheet's two.
enum DayOne {
    private static let probe = URL(string: "dayone2://")!

    /// Requires `dayone2` in LSApplicationQueriesSchemes, or this always answers false.
    static var isInstalled: Bool { UIApplication.shared.canOpenURL(probe) }

    static func entryURL(_ text: String) -> URL? {
        var components = URLComponents()
        components.scheme = "dayone2"
        components.host = "post"
        components.queryItems = [URLQueryItem(name: "entry", value: text)]
        return components.url
    }

    /// Custom-scheme URLs carry the whole entry in the query string, and a long enough one
    /// is rejected rather than truncated. Instead of guessing where that limit sits, this
    /// reports the failure so the caller can fall back to the share sheet, which has no limit.
    static func post(_ text: String) async -> Bool {
        guard let url = entryURL(text) else { return false }
        return await UIApplication.shared.open(url)
    }
}
