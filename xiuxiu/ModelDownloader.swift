import Foundation

/// Downloads the model file with progress reporting. The file only appears at
/// `destination` once fully downloaded, so a half-finished download is never mistaken for a model.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: @MainActor (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastPercent = -1

    private init(destination: URL, onProgress: @escaping @MainActor (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func download(from url: URL, to destination: URL, onProgress: @escaping @MainActor (Double) -> Void) async throws {
        let downloader = ModelDownloader(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let percent = Int(fraction * 100)
        guard percent != lastPercent else { return } // don't flood the main thread
        lastPercent = percent
        Task { @MainActor in onProgress(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw XiuxiuError("Model download failed (HTTP \(status)).") }
            // The temp file is deleted when this method returns, so move it now.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true // don't put 550 MB in iCloud backups
            var dest = destination
            try dest.setResourceValues(values)
            finish(nil)
        } catch {
            finish(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error) // no-op if didFinishDownloadingTo already finished
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
}
