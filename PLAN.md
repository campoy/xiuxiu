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
| Acceleration | Metal on device (default), CPU in the simulator (its Metal driver cannot allocate the model buffer). Core ML off for v1. Revisit only if transcription is slow. |
| Transcription | Batch only (no streaming), greedy decoding, off the main thread (Swift actor). Recording a new clip while earlier ones transcribe is allowed; the actor runs them one at a time. |
| Audio | `AVAudioRecorder` → 16 kHz mono 16-bit WAV, read back as Float via `AVAudioFile` |
| Language | `language = "auto"` constant. Entries mix Spanish and English within one recording. |
| Prompt | Punctuated Spanish/English `initialPrompt` to encourage punctuation and code-switching |
| Typical length | Under 5 minutes; foreground only (no background audio mode) |
| Storage | SwiftData `Entry(date, text)`. Auto-save after transcription; edits auto-save. |
| Audio retention | Delete the recording after a successful transcription, by its own URL. Each recording gets a unique filename, so finishing one clip cannot delete another. |
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
- [x] Record a short clip (Mac mic), check that the text appears, Copy works, and the entry shows up in History.
      A 3.8 s English question came back as "Is this working?" -- capitalised, with the question mark.
      That punctuation is the whole reason the app exists, and it is there. Copy put the same string on
      the simulator pasteboard (which syncs to the Mac's). The entry reached SwiftData; the History
      list itself is the one thing nobody has looked at yet.
- [x] Kill and relaunch: the model must not re-download, and entries persist. Both confirmed. The model
      file came back with an identical inode and mtime, so it was neither re-fetched nor rewritten, and
      the app went straight to ready. The entry survived in the store.

The simulator needs the CPU backend. Its Metal driver ships buffers to the host GPU over XPC, and
the model's 573 MB buffer trips an XPC shared-memory limit (`MTLSimDevice newBufferWithLength:` ->
`_xpc_api_misuse` -> SIGTRAP). A device has unified memory and never takes that path.

Treat simulator timings as meaningless. That 3.8 s clip took about 100 s on the CPU backend, and
Whisper pads every request to a 30 s window, so a 4 s clip costs what a 30 s one would -- the worst
possible showing. Step 4 on the phone, with Metal, is the first real measurement.

What this machine actually has, which is not what the rest of this file assumed:

| | |
|---|---|
| Xcode | 27.1, installed from the App Store. A clean build is still warning-free there -- the only `warning:` in the log is appintentsmetadataprocessor noting there is no AppIntents dependency. |
| Runtime | iOS 27.0, not 17.0. iOS 27.1 ships exactly one device type, an unreleased "iPhone Duo", so iPhone 16 Pro only exists on 27.0. Deployment target 17.0 means it runs either way. |
| Simulator GUI | `Simulator.app` is gone in Xcode 27 -- it is `DeviceHub.app`, under `Xcode.app/Contents/Applications`. `open -a Simulator` fails, so step 2 needs DeviceHub to get a window to tap. |

The toolchain is declared in the dotfiles repo (`xcodegen` and `mas` as brews, Xcode via `masApps`),
so it survives a `darwin-rebuild switch` with `onActivation.cleanup = "zap"` set.

### 3. Get it on the iPhone (needs the human; see README)
- [x] Apple ID in Xcode → Personal Team → put the Team ID in `DEVELOPMENT_TEAM` in `project.yml`.
      The Team ID is the signing certificate's **OU**, not the id in its common name -- the
      certificate reads `Apple Development: <email> (3HPW3CG3K5)` while the team is `88X2U864WM`.
      Read it with `security find-certificate -c "Apple Development: <email>" -p | openssl x509
      -noout -subject`. Signing in to Xcode alone creates no certificate; one appears only once a
      team is selected for the target, which is also what unblocks `-allowProvisioningUpdates`.
- [x] Trust the computer, turn on Developer Mode, ⌘R, then trust the developer profile on the phone.
      `xcodebuild -allowProvisioningUpdates` plus `xcrun devicectl device install app` does this
      without opening Xcode, once the team is set. The device showed `connected (no DDI)` until the
      first install, which mounted the disk image on its own. The first launch is still refused with
      "Untrusted Developer" until the profile is trusted on the phone; that is expected, not a fault.
- [x] First launch: model download on Wi-Fi, then load. Done; the app runs on the phone.

### 4. Validate on device
- [ ] Record about 1, 3 and 5 minute entries mixing Spanish and English. Note transcription time and
      punctuation quality. This is the first measurement that means anything: every earlier number
      came from the simulator's CPU backend, and the device is the first run on Metal at all.
- [ ] Record a Catalan entry. Catalan coming out as Spanish was reported but could not be reproduced
      with synthesised speech, so real audio is what will settle it. See step 6's prompt note.
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

### 6. Record while transcribing

Wanted after the simulator smoke test: tapping record again while an earlier clip is still
being transcribed, instead of waiting for it to finish.

- [x] Give every recording its own file. This was the real blocker, not the disabled button.
      `Recorder` wrote every clip to one fixed `tmp/recording.wav`, so a second recording would
      truncate the file the first was still being read from -- and worse, finishing the first
      called `deleteRecording()` on that shared path, deleting the *second* clip's audio.
      Recordings are now `recording-<uuid>.wav` and are deleted by URL.
- [x] Split the state machine. `AppModel.State` conflated the model's lifecycle with what the
      user was doing, and recording and transcribing are no longer mutually exclusive. `State`
      now covers only downloading/loading/ready/failed; `isRecording` and `transcribingCount`
      sit alongside it. The record button gates on `canRecord`, which asks only about the model.
- [x] Keep transcription failures off the fatal path. A failed clip sets `lastError` and leaves
      the model loaded, rather than putting the whole app in `.failed` and disabling recording.
- [x] Builds clean, no new warnings.
- [x] Show the outstanding clips as a stack, laid out like the History rows they are about to
      become: a caption line (start time, elapsed, ticking once a second) over a progress bar.
- [x] Real progress, not an estimate. whisper.cpp exposes `whisper_progress_callback`, so the bar
      is driven by the measured figure. The callback is a C function pointer and cannot capture,
      so the Swift closure travels through `progress_callback_user_data` (`ProgressBridge`).
- [ ] Try it in the simulator: record, stop, and record again while the first is transcribing.
      The CPU backend makes the window to do this comfortably wide.

Two things worth knowing about the design:

- **Transcriptions queue, they do not run in parallel.** `Whisper` is an actor around a single
  `whisper_context`, which is not thread-safe, so overlapping calls serialise on it. That is the
  intended behaviour: parallel transcription would mean a second ~550 MB context. `transcribingCount`
  reports the backlog so the UI can say "Transcribing 2 clips…".
- **The progress bar is granular, and the elapsed timer is the better signal for short clips.**
  Whisper processes audio in 30 s windows and reports progress per window, so a clip under 30 s
  effectively goes 0% then 100%. A 5-minute entry steps in roughly ten increments. Nothing is wrong
  when a short clip's bar sits at zero -- that is the resolution of the measurement.
- **Only the first job in the stack is running.** The others sit at 0% until the actor reaches them,
  because a single `whisper_context` serialises them. The stack is a queue, shown honestly.
- **The on-screen entry is replaced only when new text arrives**, not when recording starts.
  Finished clips always land in SwiftData, so nothing is lost either way; this just avoids blanking
  the screen for however long a transcription takes. If a result arrives while an earlier entry is
  being edited, the editor does swap to the new one -- the edit is already saved, but the cursor moves.

### 7. Look and feel

- [x] Theme "Nit": cool ink ground, warm terracotta accent, cream text; light mode is warm
      paper rather than white, so the two appearances share a temperature instead of
      swapping personality. Constants in `Theme.swift`, not an asset catalog colour set --
      five colours in two appearances is less machinery than a catalog, and it stays greppable.
- [x] The transcript is set in a serif (`.system(.body, design: .serif)`). Single highest-leverage
      change: it stops reading as a form field and starts reading as writing.
- [x] Metadata is small, tracked and upper case, so dates and status stop competing with the text.
- [x] Record button down from 120pt to 68pt with a hairline ring. The button you press twice
      should not outweigh the text you keep. A filled halo was tried first and muddied to brown
      over ink; a stroke stays legible in both appearances.
- [x] App icon: "Pals ona" -- la senyera's four pals stood upright with waveform heights, so the
      mark says Catalan and audio at once. Source is `design/appicon.svg`; the 1024 PNG is
      rendered with `rsvg-convert` and lives in `xiuxiu/Assets.xcassets`. Muted gold and red
      (`#EFBF2E`/`#CC3328`) rather than the official `#FCDD09`/`#DA121A`, which is built to be
      read across a flag and is very loud inside a 60pt rounded square. Before this there was no
      asset catalog at all and iOS drew the blank placeholder.
- [x] UI copy stays English; only the icon carries the Catalan.
- [x] On the phone. Both appearances have only been *screenshotted* in the simulator, so the
      daylight judgement is still yours to make.

iOS 26 wraps toolbar buttons in a glass pill, which reads as stray chrome on a flat ground.
`buttonStyle` does not reach it -- the background belongs to the toolbar, not the button -- so
it needs `sharedBackgroundVisibility(.hidden)` on the `ToolbarItem`, behind an availability check.

### 8. Send to Day One

The transcripts are going into Day One, so the app hands off directly rather than making you
copy and paste.

- [x] `dayone2://post?entry=...` opens a new Day One entry with the text already in it: one tap
      rather than the share sheet's two. `DayOne.swift`.
- [x] `LSApplicationQueriesSchemes: [dayone2]` in `project.yml`. Without it `canOpenURL` always
      answers false and the button would never appear, even with Day One installed.
- [x] The button only appears when Day One is actually installed.
- [x] A ShareLink sits alongside it. A custom-scheme URL carries the whole entry in its query
      string and a long enough one is rejected rather than truncated, so rather than guessing
      where that limit sits, a failed open reports itself and points at Share, which has no limit.
- [ ] Confirm on device: a short entry, and a 5-minute one, which is where the URL length
      question actually gets answered.

Day One on this phone is `com.bloombuilt.dayone-ios` 2026.20.

## File map

```
AGENTS.md                       conventions for coding agents working in this repo
project.yml                     XcodeGen spec
Packages/WhisperFramework/      vendored whisper.xcframework and its binaryTarget wrapper
xiuxiu/Config.swift             language, initialPrompt, model URL
xiuxiu/Theme.swift              the Nit palette and the metadata label style
xiuxiu/DayOne.swift             dayone2:// hand-off
design/appicon.svg              app icon source; render with rsvg-convert
xiuxiu/Whisper.swift            actor owning whisper_context; transcribe(fileAt:onProgress:)
xiuxiu/Recorder.swift           mic permission + 16 kHz mono WAV recording, one file per clip
xiuxiu/ModelDownloader.swift    URLSession download with progress, atomic move into Documents
xiuxiu/AppModel.swift           model state: downloading → loading → ready / failed,
                                plus isRecording and transcribingCount alongside it
xiuxiu/ContentView.swift        record button, EntryEditor (edit + copy), HistoryView
xiuxiu/XiuxiuApp.swift          app entry + SwiftData Entry model
```
