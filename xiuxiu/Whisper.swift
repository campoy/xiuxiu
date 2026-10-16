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

    func transcribe(fileAt url: URL) throws -> String {
        let samples = try readSamples(url)
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.translate = false
        params.no_timestamps = true
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false

        let status = language.withCString { lang in
            initialPrompt.withCString { prompt in
                params.language = lang
                params.initial_prompt = prompt
                return samples.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
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

    /// Reads a 16 kHz mono file as Float samples in [-1, 1], which is what Whisper wants.
    private func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1 else {
            throw XiuxiuError("Unexpected audio format: \(file.processingFormat)")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw XiuxiuError("Couldn't allocate audio buffer.")
        }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

struct XiuxiuError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
