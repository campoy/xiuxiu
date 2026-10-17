import UIKit
import UniformTypeIdentifiers

/// Copies shared audio into the App Group inbox and asks xiuxiu to pick it up.
///
/// No UI at all. A share sheet form would only be in the way for something with no options,
/// and the work itself has to happen in the app -- see `Inbox` for why.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        Task { await handOff() }
    }

    private func handOff() async {
        var delivered = false
        var offered: [String] = []

        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            for provider in item.attachments ?? [] {
                offered.append(provider.registeredTypeIdentifiers.joined(separator: ", "))
                guard let identifier = audioIdentifier(in: provider) else { continue }
                if await copyToInbox(provider, as: identifier) { delivered = true }
            }
        }

        if delivered {
            try? Inbox.diagnosticURL.map { try? FileManager.default.removeItem(at: $0) }
            wakeApp()
        } else {
            record(offered)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Prefer a concrete type the provider actually advertises. Asking for the abstract
    /// `public.audio` works for Voice Memos but not for every app: some register only a
    /// specific codec type, and some hand over a bare file URL with no audio type at all.
    private func audioIdentifier(in provider: NSItemProvider) -> String? {
        for identifier in provider.registeredTypeIdentifiers {
            if let type = UTType(identifier), type.conforms(to: .audio) { return identifier }
        }
        for fallback in [UTType.fileURL.identifier, UTType.data.identifier]
        where provider.hasItemConformingToTypeIdentifier(fallback) {
            return fallback
        }
        return nil
    }

    private func copyToInbox(_ provider: NSItemProvider, as identifier: String) async -> Bool {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                // The URL handed to this closure is deleted as soon as it returns, so the copy
                // has to happen here rather than being deferred.
                guard let url,
                      let destination = Inbox.destination(forExtension: url.pathExtension) else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func record(_ offered: [String]) {
        guard let url = Inbox.diagnosticURL else { return }
        let text = offered.isEmpty
            ? "The share carried no attachments at all."
            : "Nothing usable in this share. It offered:\n" + offered.joined(separator: "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Best effort only. If this fails the file still sits in the inbox and the app drains it
    /// the next time it is opened, so a share is never lost -- it just waits.
    private func wakeApp() {
        extensionContext?.open(Inbox.wakeURL) { [weak self] opened in
            guard !opened, let self else { return }
            // NSExtensionContext.open has historically refused to work from share extensions.
            // Walking the responder chain to UIApplication is the long-standing workaround; it
            // would not survive App Store review, which does not apply to a sideloaded app.
            let selector = NSSelectorFromString("openURL:")
            var responder: UIResponder? = self
            while let current = responder {
                if current.responds(to: selector) {
                    current.perform(selector, with: Inbox.wakeURL)
                    return
                }
                responder = current.next
            }
        }
    }
}
