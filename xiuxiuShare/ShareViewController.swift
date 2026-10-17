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
        for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
            for provider in item.attachments ?? [] {
                guard provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) else { continue }
                if await copyToInbox(provider) { delivered = true }
            }
        }
        if delivered { wakeApp() }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func copyToInbox(_ provider: NSItemProvider) async -> Bool {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
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
