import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var app = AppModel()
    @State private var entry: Entry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                status
                if let entry {
                    EntryEditor(entry: entry)
                } else {
                    Spacer()
                }
                recordButton
            }
            .padding()
            .navigationTitle("xiuxiu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavigationLink("History") { HistoryView() }
            }
        }
        .task { await app.prepare() }
    }

    @ViewBuilder private var status: some View {
        switch app.state {
        case .downloading(let p):
            VStack {
                Text("Downloading Whisper model (~550 MB)…")
                ProgressView(value: p)
                Text("\(Int(p * 100))%").monospacedDigit()
            }
        case .loading:
            ProgressView("Loading model…")
        case .failed(let message):
            VStack {
                Text(message).foregroundStyle(.red)
                Button("Retry") { Task { await app.retry() } }
            }
        case .ready:
            // Recording and transcribing overlap, so this reports both rather than choosing.
            VStack(spacing: 4) {
                if app.isRecording {
                    Label("Recording…", systemImage: "waveform").foregroundStyle(.red)
                }
                if !app.jobs.isEmpty { transcribingStack }
                if let lastError = app.lastError {
                    Text(lastError).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
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
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(job.startedAt, format: .dateTime.hour().minute().second())
                            Spacer()
                            Text(Self.elapsed(from: job.startedAt, to: context.date)).monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ProgressView(value: job.progress)
                    }
                    .padding(.vertical, 8)
                    if job.id != app.jobs.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
        }
    }

    private static func elapsed(from: Date, to: Date) -> String {
        let seconds = max(0, Int(to.timeIntervalSince(from)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var recordButton: some View {
        let recording = app.isRecording
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
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .background(Circle().fill(recording ? Color.red : Color.accentColor))
        }
        .disabled(!app.canRecord)
        .opacity(app.canRecord ? 1 : 0.4)
    }
}

/// Editable text for one entry. SwiftData autosaves edits.
struct EntryEditor: View {
    @Bindable var entry: Entry

    var body: some View {
        VStack(alignment: .leading) {
            Text(entry.date, format: .dateTime.weekday().day().month().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $entry.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
            Button {
                UIPasteboard.general.string = entry.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]

    var body: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink {
                    EntryEditor(entry: entry).padding().navigationTitle("Entry")
                } label: {
                    VStack(alignment: .leading) {
                        Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.text).lineLimit(2)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { modelContext.delete(entries[i]) }
            }
        }
        .navigationTitle("History")
        .overlay {
            if entries.isEmpty { ContentUnavailableView("No entries yet", systemImage: "mic") }
        }
    }
}
