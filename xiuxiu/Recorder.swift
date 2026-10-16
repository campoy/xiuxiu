import AVFoundation

/// Records straight to 16 kHz mono 16-bit PCM WAV, so no conversion is needed before Whisper.
final class Recorder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
    private var recorder: AVAudioRecorder?

    func start() async throws {
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
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw XiuxiuError("Couldn't start recording.") }
        self.recorder = recorder
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func deleteRecording() {
        try? FileManager.default.removeItem(at: url)
    }
}
