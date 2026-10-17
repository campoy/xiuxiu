import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var app = AppModel()
    @State private var entry: Entry?
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                status
                if let entry {
                    EntryEditor(entry: entry)
                } else {
                    emptyState
                }
                if !app.jobs.isEmpty { transcribingStack }
                recordButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Nit.ground(scheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showHistory) { HistoryView() }
            .toolbarBackground(Nit.ground(scheme), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("xiuxiu")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Nit.text(scheme))
                }
                // iOS 26 gives toolbar buttons a glass pill, which reads as stray chrome
                // against a flat ground. buttonStyle does not reach it -- the background is
                // the toolbar's, not the button's -- so it has to be hidden on the item.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) { historyLink }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarTrailing) { historyLink }
                }
            }
        }
        .tint(Nit.accent(scheme))
        .task {
            await app.prepare()
            await drainInbox()
        }
        // Also drain on every activation, not only on the wake URL. The share extension's
        // attempt to open the app is best effort, so this is what makes a share that arrived
        // while the app was closed -- or that failed to wake it -- still turn into an entry.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await drainInbox() }
            } else {
                // Lock behind us. Otherwise History stays open in the app switcher and across
                // a hand-over, which is most of what this is meant to prevent.
                showHistory = false
            }
        }
        .onOpenURL { url in
            Task {
                if url.scheme == "xiuxiu" {
                    await drainInbox()
                } else {
                    // Open With, handing the file over directly rather than through the inbox.
                    await transcribe(url, removingSource: false)
                }
            }
        }
    }

    /// Audio left by the share extension, oldest first.
    private func drainInbox() async {
        for url in Inbox.pending() {
            await transcribe(url, removingSource: true)
        }
        reportFailedShare()
    }

    /// A share that offered nothing xiuxiu could read leaves a note behind rather than failing
    /// silently, since from the share sheet the two are indistinguishable.
    private func reportFailedShare() {
        guard let url = Inbox.diagnosticURL,
              let note = try? String(contentsOf: url, encoding: .utf8) else { return }
        app.lastError = note
        try? FileManager.default.removeItem(at: url)
    }

    private func transcribe(_ url: URL, removingSource: Bool) async {
        guard let text = await app.transcribeShared(url) else { return }
        let new = Entry(text: text)
        modelContext.insert(new)
        entry = new
        // Only once it is safely an entry, so a failure leaves the audio to retry.
        if removingSource { try? FileManager.default.removeItem(at: url) }
    }

    private var historyLink: some View {
        Button {
            Task {
                switch await Lock.authenticate() {
                case .unlocked:
                    showHistory = true
                case .cancelled:
                    break
                case .failed(let message):
                    app.lastError = message
                }
            }
        } label: {
            Text("History").metaLabel().foregroundStyle(Nit.accent(scheme))
        }
    }

    @ViewBuilder private var status: some View {
        switch app.state {
        case .downloading(let p):
            VStack(spacing: 8) {
                Text("Downloading Whisper model (~550 MB)").metaLabel()
                ProgressView(value: p).tint(Nit.accent(scheme))
                Text("\(Int(p * 100))%").metaLabel().monospacedDigit()
            }
            .foregroundStyle(Nit.dim(scheme))
            .padding(.top, 8)
        case .loading:
            Text("Loading model").metaLabel().foregroundStyle(Nit.dim(scheme)).padding(.top, 8)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).font(.footnote).foregroundStyle(Nit.live(scheme))
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await app.retry() } }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Nit.accent(scheme))
            }
            .padding(.top, 8)
        case .ready:
            // Recording and transcribing overlap, so this reports both rather than choosing.
            VStack(spacing: 6) {
                if app.isRecording {
                    Text("● Recording").metaLabel().foregroundStyle(Nit.live(scheme))
                }
                if let lastError = app.lastError {
                    Text(lastError).font(.caption).foregroundStyle(Nit.live(scheme))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 4)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            if case .ready = app.state, !app.isRecording, app.jobs.isEmpty {
                Text("Tap to speak")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Nit.dim(scheme))
            }
            Spacer()
        }
    }

    /// Clips still being transcribed, shaped like the History rows they are about to become:
    /// a caption line over the content. Only the first is actually running -- the Whisper actor
    /// takes one at a time -- so the rest sit at 0% until their turn.
    private var transcribingStack: some View {
        // Re-renders once a second purely so the elapsed times tick.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                ForEach(app.jobs) { job in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(job.progress > 0 ? "Transcribing" : "Queued").metaLabel()
                            Spacer()
                            Text(Self.elapsed(from: job.startedAt, to: context.date))
                                .metaLabel().monospacedDigit()
                        }
                        .foregroundStyle(Nit.dim(scheme))
                        ProgressView(value: job.progress)
                            .tint(Nit.accent(scheme))
                    }
                    .padding(.vertical, 10)
                    if job.id != app.jobs.last?.id {
                        Divider().overlay(Nit.line(scheme))
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Nit.raised(scheme), in: .rect(cornerRadius: 12))
        }
    }

    private static func elapsed(from: Date, to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var recordButton: some View {
        let recording = app.isRecording
        let colour = recording ? Nit.live(scheme) : Nit.accent(scheme)
        return Button {
            // Each tap gets its own Task, so stopping one clip never blocks starting the next:
            // the transcription runs on in the task that stopped it.
            Task {
                if recording {
                    if let text = await app.stopAndTranscribe() {
                        let new = Entry(text: text)
                        modelContext.insert(new)
                        entry = new
                    }
                } else {
                    // The previous entry deliberately stays on screen while the next clip
                    // records; it is replaced only once new text actually arrives.
                    await app.startRecording()
                }
            }
        } label: {
            Image(systemName: recording ? "stop.fill" : "mic.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Nit.ground(scheme))
                .frame(width: 68, height: 68)
                .background(Circle().fill(colour))
                // A hairline ring rather than a filled halo: a tinted fill over ink muddies
                // into brown, while a stroke stays legible in both appearances.
                .overlay(
                    Circle().stroke(colour.opacity(0.28), lineWidth: 1.5)
                        .frame(width: 84, height: 84)
                )
        }
        .disabled(!app.canRecord)
        .opacity(app.canRecord ? 1 : 0.4)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

/// Editable text for one entry. SwiftData autosaves edits.
struct EntryEditor: View {
    @Environment(\.colorScheme) private var scheme
    @Bindable var entry: Entry
    @State private var sendError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .metaLabel()
                .foregroundStyle(Nit.dim(scheme))

            // Serif, because this is the writing -- the one thing on screen worth reading.
            TextEditor(text: $entry.text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Nit.text(scheme))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Nit.raised(scheme), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Nit.line(scheme), lineWidth: 1)
                )

            if let sendError {
                Text(sendError).font(.caption).foregroundStyle(Nit.live(scheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = entry.text
                } label: {
                    Text("Copy").metaLabel()
                        .foregroundStyle(Nit.dim(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Nit.line(scheme), lineWidth: 1))
                }

                if DayOne.isInstalled {
                    Button {
                        Task {
                            sendError = await DayOne.post(entry.text)
                                ? nil
                                : "Couldn't open Day One — the entry may be too long for a link. Use Share instead."
                        }
                    } label: {
                        Text("Day One").metaLabel()
                            .foregroundStyle(Nit.ground(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Nit.accent(scheme)))
                    }
                }

                // The general escape hatch, and the one with no length limit.
                ShareLink(item: entry.text) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Nit.dim(scheme))
                        .frame(width: 46, height: 44)
                        .overlay(Capsule().stroke(Nit.line(scheme), lineWidth: 1))
                }
            }
        }
    }
}

struct HistoryView: View {
    static let build: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "xiuxiu \(version) (\(build))"
    }()

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]

    var body: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink {
                    EntryEditor(entry: entry)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Nit.ground(scheme).ignoresSafeArea())
                        .navigationTitle("Entry")
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                            .metaLabel()
                            .foregroundStyle(Nit.dim(scheme))
                        Text(entry.text)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(Nit.text(scheme))
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(entries[i]) }
            }
            .listRowBackground(Nit.ground(scheme))
            .listRowSeparatorTint(Nit.line(scheme))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Nit.ground(scheme).ignoresSafeArea())
        .navigationTitle("History")
        .safeAreaInset(edge: .bottom) {
            // Which build is actually on the phone. Sounds trivial; without it there is no way
            // to tell one install from the next, and "did that deploy?" becomes unanswerable.
            Text(Self.build)
                .metaLabel()
                .foregroundStyle(Nit.dim(scheme))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .background(Nit.ground(scheme))
        }
        .overlay {
            if entries.isEmpty {
                Text("No entries yet")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Nit.dim(scheme))
            }
        }
    }
}
