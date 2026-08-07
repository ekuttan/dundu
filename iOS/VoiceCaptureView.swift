import SwiftUI
import SwiftData
import Speech
import AVFoundation
import MapKit
import DunduKit

/// Voice capture (M17): hold forth freely, watch the live transcript, then
/// review one editable card per extracted action. Nothing saves silently;
/// abandoning mid-review parks the cards in the Inbox instead of losing them.
struct VoiceCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil },
        sort: \ReminderList.sortOrder
    ) private var lists: [ReminderList]

    @State private var recorder = SpeechRecorder()
    @State private var phase: Phase = .idle
    @State private var cards: [CaptureCard] = []
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case idle, recording, processing, review
    }

    struct CaptureCard: Identifiable {
        let id = UUID()
        var title: String
        var hasDue: Bool
        var due: Date
        var hasTime: Bool
        var listID: UUID?
        var locationName: String?
        var locationProximity: String?
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle, .recording:
                    recordingScreen
                case .processing:
                    ProgressView("Splitting into actions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review:
                    reviewScreen
                }
            }
            .navigationTitle("Voice Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { abandon() }
                }
            }
        }
        .interactiveDismissDisabled(phase == .review)
    }

    // MARK: - Recording

    private var recordingScreen: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            ScrollView {
                Text(recorder.transcript.isEmpty
                     ? "Say everything in one go — several tasks, different deadlines, places. Dundu splits it up."
                     : recorder.transcript)
                    .font(.title3)
                    .foregroundStyle(recorder.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            Button {
                phase == .recording ? stopAndProcess() : startRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(phase == .recording ? Color.red : Color.accentColor)
                        .frame(width: 72, height: 72)
                    Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, Tokens.Spacing.xl)
        }
    }

    private func startRecording() {
        errorMessage = nil
        Task {
            do {
                try await recorder.start()
                phase = .recording
            } catch {
                errorMessage = "Couldn't start recording — check microphone and speech permissions in Settings."
            }
        }
    }

    private func stopAndProcess() {
        recorder.stop()
        phase = .processing
        Task { await process() }
    }

    // MARK: - Pipeline

    private func process() async {
        var transcript = recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            phase = .idle
            return
        }

        // 1. Repair pass first, so "Jobi" becomes "Joby" before splitting —
        // visible in the cards, still confirmed by the user.
        let profile = ProfileContextStore().load()
        let suspects = PhoneticMatcher.suspects(in: transcript, people: profile.allPeople)
        if !suspects.isEmpty,
           let repaired = try? await IntelligenceService.makeProvider().repair(
               RepairInput(originalTitle: transcript, candidates: suspects)
           ), repaired.looksGarbled {
            transcript = repaired.suggestedTitle
        }

        // 2. Split into actions (model when available, rules otherwise).
        let actions = (try? await CaptureSplitterFactory.make().split(transcript)) ?? []

        // 3. Route each action to a proposed list.
        let defaultListID = (try? context.defaultList())?.id
        var built: [CaptureCard] = []
        for action in actions {
            var card = CaptureCard(
                title: action.title,
                hasDue: action.resolvedDue != nil,
                due: action.resolvedDue ?? Date().addingTimeInterval(3600),
                hasTime: action.hasTime,
                listID: defaultListID,
                locationName: action.locationName,
                locationProximity: action.locationProximity
            )
            if let decision = try? await IntelligenceService.makeProvider().route(RoutingInput(
                title: action.title,
                candidateBusinesses: ContextRetriever.candidates(for: action.title, profile: profile).map(\.business),
                listOptions: lists.map {
                    RoutingTarget(id: $0.id.uuidString, name: $0.title, role: $0.isDefault ? "default" : nil)
                }
            )), let routed = UUID(uuidString: decision.targetID) {
                card.listID = routed
            }
            built.append(card)
        }

        if built.isEmpty {
            // Nothing extracted: one card with the whole transcript, so the
            // note is never lost.
            built = [CaptureCard(
                title: transcript,
                hasDue: false,
                due: Date().addingTimeInterval(3600),
                hasTime: false,
                listID: defaultListID,
                locationName: nil,
                locationProximity: nil
            )]
        }

        cards = built
        phase = .review
    }

    // MARK: - Review

    private var reviewScreen: some View {
        List {
            ForEach($cards) { $card in
                Section {
                    TextField("Title", text: $card.title, axis: .vertical)
                    Toggle("Due date", isOn: $card.hasDue.animation())
                    if card.hasDue {
                        DatePicker(
                            "Due",
                            selection: $card.due,
                            displayedComponents: card.hasTime ? [.date, .hourAndMinute] : [.date]
                        )
                    }
                    Picker("List", selection: $card.listID) {
                        ForEach(lists) { list in
                            Text(list.title).tag(Optional(list.id))
                        }
                    }
                    if let place = card.locationName, !place.isEmpty {
                        Label(
                            "\(card.locationProximity == "leave" ? "Leaving" : "Arriving"): \(place)",
                            systemImage: "location"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { cards.remove(atOffsets: $0) }

            Section {
                Button {
                    Task { await confirmAll() }
                } label: {
                    Text("Add \(cards.count == 1 ? "reminder" : "\(cards.count) reminders")")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
                .disabled(cards.isEmpty)
            }
        }
    }

    private func confirmAll() async {
        for card in cards {
            let item = ReminderItem(title: card.title, listID: card.listID, origin: .voiceCapture)
            if card.hasDue {
                item.dueDate = card.due
                item.hasTime = card.hasTime
            }
            if let place = card.locationName, !place.isEmpty {
                item.locationAlarm = await resolvePlace(
                    place, proximity: card.locationProximity == "leave" ? .leave : .enter
                )
            }
            context.insert(item)
        }
        try? context.save()
        dismiss()
        Task { await ReminderSyncService.syncNow(context: context) }
    }

    /// First MKLocalSearch hit; no match simply drops the trigger — the
    /// reminder itself still saves.
    private func resolvePlace(_ name: String, proximity: LocationAlarm.Proximity) async -> LocationAlarm? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        guard let item = (try? await MKLocalSearch(request: request).start())?.mapItems.first
        else { return nil }
        return LocationAlarm(
            title: item.name ?? name,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            proximity: proximity
        )
    }

    /// Abandoned mid-review: park the cards in the Inbox (spec §8 Task 3.6).
    private func abandon() {
        recorder.stop()
        if phase == .review && !cards.isEmpty {
            for card in cards {
                let item = ReminderItem(title: card.title, listID: card.listID, origin: .voiceCapture)
                if card.hasDue {
                    item.dueDate = card.due
                    item.hasTime = card.hasTime
                }
                item.reviewState = .pending
                context.insert(item)
            }
            try? context.save()
        }
        dismiss()
    }
}

// MARK: - Recorder

/// On-device speech recognition with a live transcript. SFSpeechRecognizer
/// with `requiresOnDeviceRecognition` keeps audio on the phone; the
/// SpeechAnalyzer upgrade path (iOS 26+) can slot in behind this same
/// surface later.
@Observable
@MainActor
final class SpeechRecorder {
    private(set) var transcript = ""

    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    enum RecorderError: Error {
        case notAuthorized
        case recognizerUnavailable
    }

    func start() async throws {
        transcript = ""

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw RecorderError.notAuthorized }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw RecorderError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            Task { @MainActor in
                self?.transcript = result.bestTranscription.formattedString
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
