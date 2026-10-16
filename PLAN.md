# xiuxiu — design plan

Handoff for a Claude Code session running on the Mac (which has Xcode, unlike the
cloud session that wrote v1). The v1 code compiles clean for the simulator as written; what
is left is running it against real audio and getting it onto the phone.

## Goal

Personal iOS voice journal, sideloaded with a free Apple account. Record, stop, transcribe
on-device with Whisper, and get properly punctuated text to copy into a journal. Apple dictation
has no punctuation, and fixing that is the point of the app. Optimize for simplicity, not polish.

## Decisions (already made, don't relitigate)

| Topic | Decision |
|---|---|
| Device | iPhone 16 Pro (8 GB RAM), iOS 26. Deployment target iOS 17. |
| UI | SwiftUI, single target, no third-party deps besides whisper.cpp |
| whisper.cpp | Prebuilt **v1.9.2** XCFramework, vendored at `Packages/WhisperFramework/whisper.xcframework` and wired up with a local SwiftPM `binaryTarget` path, so a clone builds offline. v1.9.3–v1.9.5 ship no XCFramework. |
| Model | `ggml-large-v3-turbo-q5_0.bin` (~550 MB), downloaded from Hugging Face on first launch into Documents, excluded from backup, loaded **once** |
| Acceleration | Metal on (default). Core ML off for v1. Revisit only if transcription is slow. |
| Transcription | Batch only (no streaming), greedy decoding, off the main thread (Swift actor) |
| Audio | `AVAudioRecorder` → 16 kHz mono 16-bit WAV, read back as Float via `AVAudioFile` |
| Language | `language = "auto"` constant. Entries mix Spanish and English within one recording. |
| Prompt | Punctuated Spanish/English `initialPrompt` to encourage punctuation and code-switching |
| Typical length | Under 5 minutes; foreground only (no background audio mode) |
| Storage | SwiftData `Entry(date, text)`. Auto-save after transcription; edits auto-save. |
| Audio retention | Delete the recording after a successful transcription |
| Project file | XcodeGen (`project.yml`); the `.xcodeproj` is generated and gitignored |
| Bundle ID | `cat.campoy.xiuxiu` |
| Out of scope | Settings screens, abstractions, App Store, streaming |

## Steps

### 1. Build it (Mac session)
- [x] `brew install xcodegen` (if missing), then `xcodegen` in the repo root.
- [x] `xcodebuild -project xiuxiu.xcodeproj -scheme xiuxiu -destination 'generic/platform=iOS Simulator' build`
      and fix compile errors until it's clean. None of the expected trouble spots needed a
      fix: the `whisper.h` C interop, the `@MainActor @Observable` concurrency, and the SwiftPM
      `binaryTarget` all compiled as written, with no warnings.
- [x] Verify `curl -sIL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin`
      ends in a 200 with a ~550 MB `content-length`. Verified: 200, `content-length: 574041195`.

### 2. Smoke test in the Simulator
- [x] Optional, to save time: copy the model into the simulator app's Documents folder instead of downloading it.
- [ ] Record a short clip (Mac mic), check that the text appears, Copy works, and the entry shows up in History.
- [ ] Kill and relaunch: the model must not re-download, and entries persist. No re-download is
      confirmed; entry persistence is not, because no entry exists until somebody records one.

The simulator needs the CPU backend. Its Metal driver ships buffers to the host GPU over XPC, and
the model's 573 MB buffer trips an XPC shared-memory limit (`MTLSimDevice newBufferWithLength:` ->
`_xpc_api_misuse` -> SIGTRAP). A device has unified memory and never takes that path. Only the
iOS 17.0 runtime is installed, which matches the deployment target.

### 3. Get it on the iPhone (needs the human; see README)
- [ ] Apple ID in Xcode → Personal Team → put the Team ID in `DEVELOPMENT_TEAM` in `project.yml`.
- [ ] Trust the computer, turn on Developer Mode, ⌘R, then trust the developer profile on the phone.
- [ ] First launch: model download on Wi-Fi, then load.

### 4. Validate on device
- [ ] Record about 1, 3 and 5 minute entries mixing Spanish and English. Note transcription time and
      punctuation quality.
- [ ] Watch memory in the Xcode debug navigator during transcription (expect around 1 GB).
- [ ] Deny mic permission once, then confirm the error message is clear and re-enabling it works.

### 5. Iterate (only if step 4 shows a need)
- Slow → Core ML encoder or fewer/more threads. The vendored XCFramework already has Core ML
  compiled in and probes for `ggml-large-v3-turbo-encoder.mlmodelc` in Documents on every init,
  falling back silently when it is absent, so turning it on means shipping that file, not changing code.
- Language gets flattened to one → tune `initialPrompt`, or try forcing `"es"`/`"en"`.
- Inaccurate → beam search (`WHISPER_SAMPLING_BEAM_SEARCH`, beam 5).
- Need newer whisper.cpp → build an XCFramework with `./build-xcframework.sh` and replace the
  vendored `Packages/WhisperFramework/whisper.xcframework` with it.

## File map

```
project.yml                     XcodeGen spec
Packages/WhisperFramework/      vendored whisper.xcframework and its binaryTarget wrapper
xiuxiu/Config.swift             language, initialPrompt, model URL
xiuxiu/Whisper.swift            actor owning whisper_context; transcribe(fileAt:)
xiuxiu/Recorder.swift           mic permission + 16 kHz mono WAV recording
xiuxiu/ModelDownloader.swift    URLSession download with progress, atomic move into Documents
xiuxiu/AppModel.swift           state: downloading → loading → ready ⇄ recording → transcribing / failed
xiuxiu/ContentView.swift        record button, EntryEditor (edit + copy), HistoryView
xiuxiu/XiuxiuApp.swift          app entry + SwiftData Entry model
```
