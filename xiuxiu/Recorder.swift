import AVFoundation

/// Records straight to 16 kHz mono 16-bit PCM WAV, so no conversion is needed before Whisper.
final class Recorder {
    private var recorder: AVAudioRecorder?
    private var url: URL?

    /// True between `start()` being called and the recorder actually running, so a second
    /// tap during the permission prompt cannot open a second recorder over the first.
    private var starting = false

    /// Each recording gets its own file. A fixed path would be truncated by the next
    /// recording while the previous one was still queued for, or inside, transcription.
    func start() async throws -> URL {
        guard !starting, recorder == nil else { throw XiuxiuError("Already recording.") }
        starting = true
        defer { starting = false }

        guard await AVAudioApplication.requestRecordPermission() else {
            throw XiuxiuError("Microphone access is off. Enable it in Settings → Privacy & Security → Microphone.")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).wav")
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw XiuxiuError("Couldn't start recording.") }
        self.recorder = recorder
        self.url = url
        return url
    }

    /// Returns the file just finished, or nil if nothing was recording.
    func stop() -> URL? {
        guard let recorder, let url else { return nil }
        recorder.stop()
        self.recorder = nil
        self.url = nil
        // Only the recording needs the session; transcription reads files and does not.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    /// Deletes one recording by name. Never deletes "the current recording", which by the
    /// time a transcription finishes may well be a later clip that is still being recorded.
    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
