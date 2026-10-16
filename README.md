# xiuxiu

Personal voice journal for iPhone (from *xiuxiueig*, "whisper" in Catalan). Tap to record,
tap to stop, and get punctuated text transcribed on-device by
[whisper.cpp](https://github.com/ggml-org/whisper.cpp) (large-v3-turbo, q5_0, Metal).
Entries are saved locally with SwiftData.

## Layout

```
AGENTS.md                          conventions for coding agents working in this repo
project.yml                        XcodeGen spec (the .xcodeproj is generated, not committed)
Packages/WhisperFramework/         the whisper.cpp v1.9.2 XCFramework, vendored, plus its SwiftPM wrapper
xiuxiu/Config.swift                language, initial prompt, model URL  ← the knobs
xiuxiu/Whisper.swift               whisper.cpp context (loaded once) + transcription
xiuxiu/Recorder.swift              16 kHz mono PCM WAV recording
xiuxiu/ModelDownloader.swift       first-launch model download with progress
xiuxiu/AppModel.swift              state machine: downloading → loading → ready ⇄ recording → transcribing
xiuxiu/ContentView.swift           UI: record button, editor, copy, history
```

## Getting it on your iPhone (free Apple account)

One-time setup on the Mac:

1. `brew install xcodegen`
2. In this repo: `xcodegen` creates `xiuxiu.xcodeproj`. Then `open xiuxiu.xcodeproj`.
   The whisper XCFramework is committed to the repo, so there is nothing to download.
3. **Xcode → Settings → Accounts → +** and sign in with your Apple ID.
   This creates a "Personal Team".
4. Select the **xiuxiu** target, open **Signing & Capabilities**, check
   **Automatically manage signing**, and set **Team** to *<your name> (Personal Team)*.
   Bundle ID is `cat.campoy.xiuxiu`.
   - So that re-running `xcodegen` doesn't reset the team: copy the Team ID (shown in
     Build Settings → `DEVELOPMENT_TEAM` after you pick the team) into
     `DEVELOPMENT_TEAM` in `project.yml`.
5. Plug the iPhone in with a cable, unlock it, and tap **Trust This Computer**.
6. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on, and
   restart. The toggle only appears after Xcode has seen the device once.
7. In Xcode, pick your iPhone as the run destination and press **⌘R**.
8. The first launch is blocked with "Untrusted Developer". On the iPhone, go to
   **Settings → General → VPN & Device Management → (your Apple ID) → Trust**, then
   run again.

On first launch the app downloads the model (~550 MB) into its Documents folder.
Stay on Wi-Fi and keep the app open; the screen stays awake while it downloads. After that,
the model only needs to load, which takes a few seconds each time the app starts.

Limits of a free account:
- **The app stops launching after 7 days.** Plug in and press ⌘R again to re-sign it.
  Your entries and the downloaded model survive, because reinstalling over the app keeps its data.
- At most 3 sideloaded apps per device. Deleting the app deletes entries and the model.

## Knobs (`xiuxiu/Config.swift`)

- `language`: `"auto"` by default. Set it to `"es"`, `"en"`, `"ca"`, … to force one language.
  Auto-detect only listens to the first 30 s, so an entry that starts in one language
  tends to come out in it throughout. Forcing a language can *translate* the other one.
- `initialPrompt`: Whisper imitates its style **and continues its language**. That second part
  matters more than it sounds: with a Spanish/English-only prompt, French audio came back as
  broken Spanish — *"Hoy hoy hoy trabajo por un nuevo proyecto"* — even though auto-detect had
  correctly reported `fr`. Detection was never the problem; the prompt was overriding it. The
  prompt now also carries a French and a Catalan sentence, which fixes French and leaves Catalan
  and the Spanish/English code-switching unchanged. If you journal in another language, add a
  punctuated sentence of it here rather than reaching for `language`.

## Notes / possible next steps

- **Core ML is off.** Metal already runs the whole model on the GPU. Adding the Core ML encoder
  (`ggml-large-v3-turbo-encoder.mlmodelc`, ~1.2 GB extra download) would run the encoder on the
  Neural Engine. That's maybe 2–3× faster encoding, but the first load compiles the model for minutes. It's
  only worth it if transcription feels slow on the 16 Pro. No code change is needed: the vendored
  XCFramework has Core ML compiled in and probes for that file in Documents on every init,
  falling back silently when it is absent.
- Decoding is greedy (fastest). Beam search (`WHISPER_SAMPLING_BEAM_SEARCH`, beam 5) is a bit
  more accurate and noticeably slower.
- whisper.cpp v1.9.3+ ship no prebuilt XCFramework. To upgrade, build one with
  `./build-xcframework.sh` from a whisper.cpp checkout and replace
  `Packages/WhisperFramework/whisper.xcframework` with it.
- Recording stops if you leave the app. Fine for short entries; long ones would need
  `UIBackgroundModes: audio`.
