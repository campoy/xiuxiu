import Foundation

/// Where the share extension leaves audio for the app to transcribe.
///
/// The extension deliberately does not transcribe anything itself: an app extension is given a
/// small fraction of an app's memory, and the model alone wants about a gigabyte. So it acts as
/// a courier -- copy the file into the shared container, wake the app, get out of the way.
///
/// Compiled into both targets, which is why it lives outside either one.
enum Inbox {
    static let appGroup = "group.cat.campoy.xiuxiu"

    /// The URL the app is opened with once a file has been dropped off.
    static let wakeURL = URL(string: "xiuxiu://import")!

    static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    /// Oldest first, so sharing several things keeps them in the order they arrived.
    static func pending() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        return files.sorted { left, right in
            let l = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let r = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return l < r
        }
    }

    /// What a share actually offered, written only when nothing usable came out of it.
    /// Without this, an app whose audio xiuxiu cannot read is indistinguishable from a tap
    /// that did nothing, and there is no way to see which types were on the table.
    static var diagnosticURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("last-share.txt")
    }

    static func destination(forExtension ext: String) -> URL? {
        directory?.appendingPathComponent("\(UUID().uuidString).\(ext.isEmpty ? "m4a" : ext)")
    }
}
