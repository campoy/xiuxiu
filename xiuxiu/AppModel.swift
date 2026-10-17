import SwiftUI

@MainActor @Observable
final class AppModel {
    /// Only the model's lifecycle. Recording and transcribing are deliberately *not* in here:
    /// they overlap, so a single state would have to pick one to represent and hide the other.
    enum State: Equatable {
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    var state: State = .loading { didSet { updateIdleTimer() } }

    /// One at a time: the mic is a single resource.
    private(set) var isRecording = false { didSet { updateIdleTimer() } }

    /// One clip waiting on, or inside, transcription.
    struct TranscriptionJob: Identifiable, Equatable {
        let id = UUID()
        let startedAt: Date
        /// 0...1, from whisper's own progress callback. Measured, not estimated.
        var progress: Double = 0
    }

    /// Outstanding transcriptions, oldest first. The Whisper actor runs them one at a time,
    /// so everything after the first is queued rather than running.
    private(set) var jobs: [TranscriptionJob] = [] { didSet { updateIdleTimer() } }

    /// A failed transcription, which is not fatal -- the model is still loaded and the next
    /// recording can go ahead. Kept apart from `.failed`, which means the model itself is unusable.
    var lastError: String?

    private var whisper: Whisper?
    private let recorder = Recorder()

    /// The record button only needs the model; a transcription in flight does not block it.
    var canRecord: Bool { state == .ready }

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
        lastError = nil
        do {
            _ = try await recorder.start()
            isRecording = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stops the current recording and transcribes it. The caller can start the next recording
    /// as soon as this returns from `stop()`; the transcription continues in this task.
    /// Returns the transcribed text, or nil if there was nothing to save.
    func stopAndTranscribe() async -> String? {
        guard let url = recorder.stop() else { return nil }
        isRecording = false
        guard let whisper else { return nil }

        return await run(whisper, on: url)
    }

    /// Transcribes an audio file handed over by another app, so a Voice Memo or a voice note
    /// becomes an entry exactly like something recorded here. The file is converted to 16 kHz
    /// mono on the way in; see `Whisper.readSamples`.
    func transcribeShared(_ url: URL) async -> String? {
        // A share can land before the model has finished loading. prepare() returns immediately
        // once it has, so this just waits for the first launch rather than dropping the file.
        await prepare()
        guard let whisper else {
            lastError = "The model isn't loaded yet. Try sharing it again in a moment."
            return nil
        }

        // Files from other apps are security-scoped and the original may be gone by the time
        // transcription finishes, so take a copy first and work from that.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: url, to: local)
        } catch {
            lastError = error.localizedDescription
            return nil
        }

        return await run(whisper, on: local)
    }

    /// The shared tail of both paths: show a job, transcribe, bin the audio on success only.
    private func run(_ whisper: Whisper, on url: URL) async -> String? {
        let job = TranscriptionJob(startedAt: .now)
        jobs.append(job)
        defer { jobs.removeAll { $0.id == job.id } }
        do {
            // The callback arrives on whisper's thread, so hop back to update the UI.
            let text = try await whisper.transcribe(fileAt: url) { [weak self] percent in
                Task { @MainActor in self?.setProgress(job.id, Double(percent) / 100) }
            }
            Recorder.delete(url) // only on success, so a failure doesn't lose the audio
            return text.isEmpty ? nil : text
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func setProgress(_ id: UUID, _ progress: Double) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return } // already finished
        jobs[i].progress = progress
    }

    func retry() async {
        lastError = nil
        if whisper == nil {
            state = .loading
            await prepare()
        } else {
            state = .ready
        }
    }

    /// Auto-lock would stop a recording or a download, and sleeping mid-transcription
    /// just makes it take longer. Stay awake while any of that is outstanding.
    private func updateIdleTimer() {
        let busy: Bool
        switch state {
        case .downloading, .loading: busy = true
        case .ready, .failed: busy = isRecording || !jobs.isEmpty
        }
        UIApplication.shared.isIdleTimerDisabled = busy
    }
}
