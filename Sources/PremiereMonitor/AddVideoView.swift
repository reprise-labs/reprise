import SwiftUI

struct AddVideoView: View {
    @ObservedObject private var engine = MonitorEngine.shared

    /// When editing an existing premiere, its id (nil when adding a new one).
    private let editingId: UUID?
    /// When opened from an Upcoming/Discovered row's "Add" button, the id to remove
    /// from discoveredVideos once the add actually succeeds — not just when this
    /// dialog opens, so cancelling leaves it sitting in Upcoming for later, same as
    /// never having clicked Add at all.
    private let discoveredVideoId: String?

    @State private var url: String
    @State private var label: String
    @State private var scheduledDate: Date
    @State private var quality: VideoQuality

    @State private var isLookingUp: Bool = false
    @State private var lookupMessage: String?
    @State private var lookupSucceeded: Bool = false

    init(editing video: MonitoredVideo? = nil) {
        self.editingId = video?.id
        self.discoveredVideoId = nil
        _url = State(initialValue: video?.url ?? "")
        _label = State(initialValue: video?.label ?? "")
        _scheduledDate = State(initialValue: video?.scheduledDate ?? Date().addingTimeInterval(3600))
        _quality = State(initialValue: video?.quality ?? .best)
    }

    /// URL and title are already known from channel discovery; scheduled time isn't
    /// (the flat-playlist channel listing that found this video doesn't carry it) —
    /// fetched the same way a manual "Look Up" click would, automatically, the moment
    /// this view appears (see .task below), so the user doesn't have to click it
    /// themselves for something Reprise already had the means to fill in.
    init(discovered: DiscoveredVideo) {
        self.editingId = nil
        self.discoveredVideoId = discovered.videoID
        _url = State(initialValue: discovered.url)
        _label = State(initialValue: discovered.title)
        _scheduledDate = State(initialValue: Date().addingTimeInterval(3600))
        _quality = State(initialValue: .best)
    }

    private var isEditing: Bool { editingId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit premiere" : "Add new premiere")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("YouTube URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("https://www.youtube.com/watch?v=...", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await lookupInfo() } }

                    Button {
                        Task { await lookupInfo() }
                    } label: {
                        if isLookingUp {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Text("Look up")
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUp)
                }

                if let lookupMessage {
                    Text(lookupMessage)
                        .font(.caption)
                        .foregroundStyle(lookupSucceeded ? .green : .orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Label (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Band name - Concert", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Scheduled time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $scheduledDate)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Quality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // YouTube-style quality menu, same label/position as YouTube's own
                // (verified 15-10-2026): "1080p Premium" above plain "1080p" — not
                // a standalone "Premium" entry. Only appears at all once it's been
                // confirmed (on any video, not necessarily this one) — before that
                // there's nothing to offer, so it's left out rather than shown
                // disabled. See VideoQuality and AppSettings.youtubePremiumConfirmed
                // for why this can't reliably be narrowed down to "available for
                // this exact video": a premiere is normally added days before it
                // airs, when YouTube doesn't have a format list for it yet at all.
                Picker("", selection: $quality) {
                    if engine.settings.youtubePremiumConfirmed == true {
                        Text(VideoQuality.premium.displayName).tag(VideoQuality.premium)
                    }
                    ForEach(VideoQuality.allCases.filter { $0 != .premium }) { q in
                        Text(q.displayName).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 180)

                if quality == .premium {
                    Text("Only downloads at this bitrate if YouTube offers it for this video — otherwise falls back to Best available.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 360, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    StatusItemController.shared?.closeAddWindowAndShowMain()
                }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    let succeeded: Bool
                    if let editingId {
                        succeeded = engine.updateVideo(id: editingId, url: url, label: label, scheduledDate: scheduledDate, quality: quality)
                    } else {
                        succeeded = engine.addVideo(url: url, label: label, scheduledDate: scheduledDate, quality: quality)
                    }
                    if succeeded {
                        if let discoveredVideoId {
                            engine.dismissDiscovered(byId: discoveredVideoId)
                        }
                        StatusItemController.shared?.closeAddWindowAndShowMain()
                    } else {
                        lookupMessage = "This URL is already used by another premiere."
                        lookupSucceeded = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .task {
            if discoveredVideoId != nil { await lookupInfo() }
        }
    }

    private func lookupInfo() async {
        isLookingUp = true
        lookupMessage = nil
        let result = await engine.lookupVideoInfo(url: url)
        isLookingUp = false

        if let title = result.title, label.trimmingCharacters(in: .whitespaces).isEmpty {
            label = title
        }
        if let date = result.scheduledDate {
            scheduledDate = date
            lookupMessage = "Scheduled time filled in automatically."
            lookupSucceeded = true
        } else if result.isLiveNow {
            scheduledDate = Date()
            lookupMessage = "This video is already live!"
            lookupSucceeded = true
        } else {
            lookupMessage = result.errorMessage ?? "No scheduled time found — enter it manually."
            lookupSucceeded = false
        }
    }
}
