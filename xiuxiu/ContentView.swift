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
        case .ready:
            EmptyView()
        case .recording:
            Label("Recording…", systemImage: "waveform").foregroundStyle(.red)
        case .transcribing:
            ProgressView("Transcribing…")
        case .failed(let message):
            VStack {
                Text(message).foregroundStyle(.red)
                Button("Retry") { Task { await app.retry() } }
            }
        }
    }

    private var recordButton: some View {
        let recording = app.state == .recording
        return Button {
            Task {
                if recording {
                    if let text = await app.stopAndTranscribe() {
                        let new = Entry(text: text)
                        modelContext.insert(new)
                        entry = new
                    }
                } else {
                    entry = nil
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
        .disabled(app.state != .ready && !recording)
        .opacity(app.state != .ready && !recording ? 0.4 : 1)
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
