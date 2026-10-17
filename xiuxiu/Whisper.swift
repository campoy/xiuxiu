import AVFoundation
import whisper

/// Owns the whisper.cpp context. Load once, keep for the app's lifetime.
/// Being an actor means transcription runs off the main thread.
actor Whisper {
    private let ctx: OpaquePointer

    /// Blocking: takes a few seconds for large-v3-turbo. Call from a background task.
    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        // Metal on device. The simulator's Metal driver ships buffers to the host GPU
        // over XPC, and the model's ~550 MB buffer trips an XPC shared-memory limit
        // (MTLSimDevice newBufferWithLength: -> _xpc_api_misuse -> SIGTRAP), so use the
        // CPU there. Slow, but it makes the simulator usable for smoke tests.
        #if targetEnvironment(simulator)
        params.use_gpu = false
        #else
        params.use_gpu = true // Metal
        #endif
        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw XiuxiuError("Couldn't load the Whisper model.")
        }
        self.ctx = ctx
    }

    deinit {
        whisper_free(ctx)
    }

    /// `onProgress` receives 0...100 and is called on whisper's own thread, not the main one.
    /// It is driven by whisper's progress callback, so the figure is measured, not estimated --
    /// but it advances per 30 s window of audio, so a short clip jumps rather than creeps.
    func transcribe(fileAt url: URL, onProgress: @escaping @Sendable (Int) -> Void = { _ in }) throws -> String {
        let samples = try readSamples(url)
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.translate = false
        params.no_timestamps = true
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false

        // A C function pointer cannot capture, so the closure travels through user_data.
        // Unretained: `bridge` is kept alive for the whole call by withExtendedLifetime below.
        let bridge = ProgressBridge(onProgress)
        params.progress_callback = { _, _, progress, userData in
            guard let userData else { return }
            Unmanaged<ProgressBridge>.fromOpaque(userData).takeUnretainedValue().report(Int(progress))
        }
        params.progress_callback_user_data = Unmanaged.passUnretained(bridge).toOpaque()

        let status = withExtendedLifetime(bridge) {
            language.withCString { lang in
                initialPrompt.withCString { prompt in
                    params.language = lang
                    params.initial_prompt = prompt
                    return samples.withUnsafeBufferPointer { buf in
                        whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                    }
                }
            }
        }
        guard status == 0 else { throw XiuxiuError("Transcription failed (\(status)).") }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            text += String(cString: whisper_full_get_segment_text(ctx, i))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads any audio file as 16 kHz mono Float samples in [-1, 1], which is what Whisper wants.
    /// Clips recorded here are already in that format and take the fast path. Clips shared in from
    /// other apps are not -- Voice Memos hands over 44.1 or 48 kHz m4a -- so they are decoded,
    /// downmixed and resampled here rather than rejected.
    ///
    /// Deliberately synchronous, and converted in chunks rather than by reading the whole file.
    /// Synchronous because `transcribe` is an actor method with no suspension points, so one
    /// transcription runs start to finish without another interleaving on the shared context;
    /// chunked because a five-minute 48 kHz stereo file is over 100 MB decoded, against a memory
    /// budget already mostly spent on the model.
    private func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let source = file.processingFormat

        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16_000, channels: 1, interleaved: false) else {
            throw XiuxiuError("Couldn't describe the 16 kHz mono format.")
        }

        if source.sampleRate == target.sampleRate, source.channelCount == 1 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source,
                                                frameCapacity: AVAudioFrameCount(file.length)) else {
                throw XiuxiuError("Couldn't allocate audio buffer.")
            }
            try file.read(into: buffer)
            guard let data = buffer.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw XiuxiuError("Can't convert \(source) to 16 kHz mono.")
        }

        let chunk: AVAudioFrameCount = 32_768
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk) else {
            throw XiuxiuError("Couldn't allocate audio buffer.")
        }

        let ratio = target.sampleRate / source.sampleRate
        let outCapacity = AVAudioFrameCount(Double(chunk) * ratio) + 1024

        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * ratio) + Int(outCapacity))

        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity) else {
                throw XiuxiuError("Couldn't allocate audio buffer.")
            }

            var readError: Error?
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                // Stop before reading past the end: AVAudioFile throws eofErr (OSStatus -39)
                // rather than returning zero frames, so EOF would otherwise look like failure.
                guard file.framePosition < file.length else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input, frameCount: chunk)
                } catch {
                    readError = error
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard input.frameLength > 0 else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return input
            }

            if let readError { throw readError }
            if let conversionError { throw conversionError }

            if output.frameLength > 0, let data = output.floatChannelData {
                // Resampling can overshoot: a real Day One recording came out with a peak of
                // 1.17, and Whisper is documented to want [-1, 1]. Clamping is cheaper than
                // normalising and does not change the level of anything already in range.
                let converted = UnsafeBufferPointer(start: data[0], count: Int(output.frameLength))
                samples.append(contentsOf: converted.lazy.map { min(max($0, -1), 1) })
            }
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }
}

/// Carries a Swift closure through whisper's `void *user_data`.
private final class ProgressBridge: @unchecked Sendable {
    private let onProgress: @Sendable (Int) -> Void
    private var last = -1

    init(_ onProgress: @escaping @Sendable (Int) -> Void) { self.onProgress = onProgress }

    /// Whisper can report the same percentage repeatedly; only pass on actual changes,
    /// so the UI is not woken for every no-op update.
    func report(_ progress: Int) {
        guard progress != last else { return }
        last = progress
        onProgress(progress)
    }
}

struct XiuxiuError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
