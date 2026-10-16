import SwiftUI

@MainActor @Observable
final class AppModel {
    enum State: Equatable {
        case downloading(Double)
        case loading
        case ready
        case recording
        case transcribing
        case failed(String)
    }

    var state: State = .loading {
        // Keep the screen awake while busy: auto-lock would stop a recording or a download.
        didSet {
            switch state {
            case .ready, .failed: UIApplication.shared.isIdleTimerDisabled = false
            default: UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }
    private var whisper: Whisper?
    private let recorder = Recorder()

    /// Downloads the model on first launch, then loads it once.
    func prepare() async {
        guard whisper == nil else { return }
        let path = URL.documentsDirectory.appendingPathComponent(modelFileName)
        do {
            if !FileManager.default.fileExists(atPath: path.path) {
                state = .downloading(0)
                try await ModelDownloader.download(from: modelURL, to: path) { [weak self] p in
                    self?.state = .downloading(p)
                }
            }
            state = .loading
            whisper = try await Task.detached { try Whisper(modelPath: path.path) }.value
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func startRecording() async {
        do {
            try await recorder.start()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Returns the transcribed text, or nil if there was nothing to save.
    func stopAndTranscribe() async -> String? {
        recorder.stop()
        guard let whisper else { return nil }
        state = .transcribing
        do {
            let text = try await whisper.transcribe(fileAt: recorder.url)
            recorder.deleteRecording() // only on success, so a failure doesn't lose the audio
            state = .ready
            return text.isEmpty ? nil : text
        } catch {
            state = .failed(error.localizedDescription)
            return nil
        }
    }

    func retry() async {
        state = .loading
        if whisper == nil { await prepare() } else { state = .ready }
    }
}
