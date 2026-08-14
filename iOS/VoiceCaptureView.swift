import SwiftUI
import SwiftData
import Speech
import AVFoundation
import MapKit
import DunduKit

/// Voice capture: it starts listening the moment it opens, keeps everything
/// you've said across pauses, and understands "add it to the Hoomans list".
/// Nothing saves silently; abandoning mid-review parks the cards in the Inbox.
struct VoiceCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<ReminderList> { $0.tombstonedAt == nil },
        sort: \ReminderList.sortOrder
    ) private var lists: [ReminderList]

    @State private var recorder = SpeechRecorder()
    @State private var phase: Phase = .recording
    @State private var cards: [CaptureCard] = []
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case recording, processing, review
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
        /// Set when the list came from something the user actually said, so
        /// the card can show that it was heard rather than guessed.
        var listWasSpoken = false
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .recording: recordingScreen
            case .processing: processingScreen
            case .review: reviewScreen
            }
        }
        .background(Tokens.Colors.paper)
        .interactiveDismissDisabled(phase == .review)
        // Tapping the mic means "record" — there is no reason to ask twice.
        .task { await beginIfNeeded() }
        .onDisappear { recorder.stop() }
    }

    // MARK: - Recording

    private var recordingScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Button { abandon() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.ink)
                        .frame(width: 40, height: 40)
                        .background(Circle().stroke(Tokens.Colors.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                Spacer()
                Label(
                    recorder.isRecording ? "Listening" : "Paused",
                    systemImage: recorder.isRecording ? "waveform" : "pause.fill"
                )
                .font(Tokens.Typo.label)
                .foregroundStyle(recorder.isRecording ? Tokens.Colors.accent : Tokens.Colors.quiet)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.vertical, Tokens.Spacing.md)

            ScrollView {
                Text(recorder.transcript.isEmpty ? Self.prompt : recorder.transcript)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        recorder.transcript.isEmpty ? Tokens.Colors.quiet : Tokens.Colors.ink
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Spacing.xl)
                    .padding(.top, Tokens.Spacing.lg)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Tokens.Typo.label)
                    .foregroundStyle(Tokens.Colors.dueSoon)
                    .padding(.horizontal, Tokens.Spacing.xl)
                    .padding(.bottom, Tokens.Spacing.sm)
            }

            if !lists.isEmpty && recorder.transcript.isEmpty {
                listHints
            }

            levelMeter
                .padding(.vertical, Tokens.Spacing.lg)

            HStack(spacing: Tokens.Spacing.md) {
                Button {
                    recorder.isRecording ? recorder.pause() : resume()
                } label: {
                    Image(systemName: recorder.isRecording ? "pause.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.ink)
                        .frame(width: 56, height: 56)
                        .background(Circle().stroke(Tokens.Colors.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())

                PillButton(title: "Done", glyph: "checkmark") { stopAndProcess() }
                    .disabled(recorder.transcript.isEmpty)
                    .opacity(recorder.transcript.isEmpty ? 0.4 : 1)
            }
            .padding(.bottom, Tokens.Spacing.xl)
        }
    }

    private static let prompt = "Say everything in one go — several tasks, deadlines, places. Dundu splits it up."

    /// Naming the lists out loud only works if you know what they're called.
    private var listHints: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text("Try saying “add it to …”")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Tokens.Colors.quiet)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.sm) {
                    ForEach(lists) { list in
                        Text(list.title)
                            .font(Tokens.Typo.label)
                            .foregroundStyle(Tokens.Colors.ink)
                            .padding(.horizontal, Tokens.Spacing.md)
                            .padding(.vertical, 6)
                            .background(Capsule().stroke(Tokens.Colors.hairline, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.horizontal, Tokens.Spacing.xl)
    }

    /// A row of bars that answers "is it actually hearing me?" — the one
    /// question a recording screen has to answer at a glance.
    private var levelMeter: some View {
        HStack(spacing: 4) {
            ForEach(0..<13, id: \.self) { index in
                Capsule()
                    .fill(recorder.isRecording ? Tokens.Colors.accent : Tokens.Colors.hairline)
                    .frame(width: 4, height: barHeight(index))
                    .animation(.easeOut(duration: 0.12), value: recorder.level)
            }
        }
        .frame(height: 44)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard recorder.isRecording else { return 6 }
        // Tallest in the middle, so speech reads as a shape rather than a row
        // of equal sticks.
        let distance = abs(Double(index) - 6) / 6
        let falloff = 1 - distance * 0.65
        return 6 + CGFloat(recorder.level * falloff) * 38
    }

    private var processingScreen: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            ProgressView()
            Text("Splitting into actions…")
                .font(Tokens.Typo.body)
                .foregroundStyle(Tokens.Colors.quiet)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recorder lifecycle

    private func beginIfNeeded() async {
        guard phase == .recording, !recorder.isRecording, recorder.transcript.isEmpty else { return }
        await start()
    }

    private func resume() {
        Task { await start() }
    }

    private func start() async {
        errorMessage = nil
        do {
            try await recorder.start()
        } catch {
            errorMessage = "Couldn't start recording — check microphone and speech permissions in Settings."
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
            phase = .recording
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

        let targets = lists.map { ListCommandParser.Target(id: $0.id, name: $0.title) }
        let defaultListID = (try? context.defaultList())?.id
        var built: [CaptureCard] = []

        for action in actions {
            // 3. A list named out loud beats anything the router infers, and
            // the instruction comes back out of the title.
            let spoken = ListCommandParser.parse(action.title, lists: targets)
            var card = CaptureCard(
                title: spoken.title,
                hasDue: action.resolvedDue != nil,
                due: action.resolvedDue ?? Date().addingTimeInterval(3600),
                hasTime: action.hasTime,
                listID: spoken.listID ?? defaultListID,
                locationName: action.locationName,
                locationProximity: action.locationProximity,
                listWasSpoken: spoken.listID != nil
            )

            if spoken.listID == nil,
               let decision = try? await IntelligenceService.makeProvider().route(RoutingInput(
                   title: card.title,
                   candidateBusinesses: ContextRetriever
                       .candidates(for: card.title, profile: profile).map(\.business),
                   listOptions: lists.map {
                       RoutingTarget(id: $0.id.uuidString, name: $0.title,
                                     role: $0.isDefault ? "default" : nil)
                   }
               )), let routed = UUID(uuidString: decision.targetID) {
                card.listID = routed
            }
            built.append(card)
        }

        if built.isEmpty {
            // Nothing extracted: one card with the whole transcript, so the
            // note is never lost. A spoken list still applies.
            let spoken = ListCommandParser.parse(transcript, lists: targets)
            built = [CaptureCard(
                title: spoken.title,
                hasDue: false,
                due: Date().addingTimeInterval(3600),
                hasTime: false,
                listID: spoken.listID ?? defaultListID,
                locationName: nil,
                locationProximity: nil,
                listWasSpoken: spoken.listID != nil
            )]
        }

        cards = built
        phase = .review
    }

    // MARK: - Review

    private var reviewScreen: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                glyph: "checklist",
                title: cards.count == 1 ? "1 reminder" : "\(cards.count) reminders",
                subtitle: "Edit anything before saving"
            ) {
                Button { abandon() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.Colors.ink)
                        .frame(width: 40, height: 40)
                        .background(Circle().stroke(Tokens.Colors.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }

            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.md) {
                    ForEach($cards) { $card in
                        captureCard($card)
                    }
                }
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.bottom, Tokens.Spacing.lg)
            }

            PillButton(
                title: cards.count == 1 ? "Add reminder" : "Add \(cards.count) reminders",
                glyph: "checkmark"
            ) {
                Task { await confirmAll() }
            }
            .disabled(cards.isEmpty)
            .padding(.bottom, Tokens.Spacing.xl)
        }
    }

    private func captureCard(_ card: Binding<CaptureCard>) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
                TextField("Title", text: card.title, axis: .vertical)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Tokens.Colors.ink)
                Button {
                    withAnimation(Tokens.Anim.content) {
                        cards.removeAll { $0.id == card.wrappedValue.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Tokens.Colors.hairline)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Tokens.Spacing.sm) {
                Menu {
                    ForEach(lists) { list in
                        Button(list.title) { card.listID.wrappedValue = list.id }
                    }
                } label: {
                    chip(
                        listName(card.listID.wrappedValue) ?? "No list",
                        glyph: card.listWasSpoken.wrappedValue ? "mic.fill" : "folder",
                        tint: card.listWasSpoken.wrappedValue
                            ? Tokens.Colors.accent : Tokens.Colors.quiet
                    )
                }

                Button {
                    withAnimation(Tokens.Anim.content) { card.hasDue.wrappedValue.toggle() }
                } label: {
                    chip(
                        card.hasDue.wrappedValue
                            ? card.due.wrappedValue.formatted(
                                date: .abbreviated,
                                time: card.hasTime.wrappedValue ? .shortened : .omitted
                              )
                            : "No date",
                        glyph: "calendar",
                        tint: card.hasDue.wrappedValue ? Tokens.Colors.hueTask : Tokens.Colors.quiet
                    )
                }
                Spacer(minLength: 0)
            }

            if card.hasDue.wrappedValue {
                DatePicker(
                    "Due",
                    selection: card.due,
                    displayedComponents: card.hasTime.wrappedValue
                        ? [.date, .hourAndMinute] : [.date]
                )
                .font(Tokens.Typo.label)
            }

            if let place = card.locationName.wrappedValue, !place.isEmpty {
                Label(
                    "\(card.locationProximity.wrappedValue == "leave" ? "Leaving" : "Arriving"): \(place)",
                    systemImage: "mappin"
                )
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Tokens.Colors.hueTravel)
            }
        }
        .padding(Tokens.Spacing.lg)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .fill(Tokens.Colors.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .stroke(Tokens.Colors.hairline, lineWidth: 1)
                }
        }
    }

    private func chip(_ text: String, glyph: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Tokens.Spacing.sm + 2)
        .padding(.vertical, 5)
        .background(Capsule().stroke(Tokens.Colors.hairline, lineWidth: 1))
    }

    private func listName(_ id: UUID?) -> String? {
        lists.first { $0.id == id }?.title
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

/// On-device speech recognition with a live transcript that survives pauses.
///
/// A recognition task reports the whole of *its own* session each time, so
/// assigning that straight to the transcript throws away everything said
/// before the pause. Finished sessions are committed to `settled` and the
/// live session is appended to it, which is what makes stop/start additive.
@Observable
@MainActor
final class SpeechRecorder {
    /// Everything from sessions that have already ended.
    private var settled = ""
    /// The session currently being spoken, if any.
    private var live = ""

    var transcript: String {
        [settled, live]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private(set) var isRecording = false
    /// 0…1, smoothed, for the level meter.
    private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    enum RecorderError: Error {
        case notAuthorized
        case recognizerUnavailable
    }

    func start() async throws {
        guard !isRecording else { return }

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
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let peak = Self.peak(of: buffer)
            Task { @MainActor in self?.absorb(peak) }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self?.live = text }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Ends the session but keeps what was said, so speaking again continues
    /// the same transcript instead of replacing it.
    func pause() {
        guard isRecording else { return }
        teardown()
        if !live.isEmpty {
            settled = settled.isEmpty ? live : settled + " " + live
            live = ""
        }
    }

    func stop() {
        pause()
    }

    /// Throws the transcript away — for starting a genuinely new capture.
    func reset() {
        stop()
        settled = ""
        live = ""
    }

    private func teardown() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Smoothed so the meter reads as a voice rather than a strobe: quick to
    /// rise on a syllable, slow to fall between them.
    private func absorb(_ peak: Double) {
        level = peak > level ? peak : level * 0.82 + peak * 0.18
    }

    private nonisolated static func peak(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            sum += channel[index] * channel[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        // Speech sits well below full scale; this range makes normal talking
        // fill most of the meter instead of a twitch at the bottom.
        return min(1, max(0, Double(rms) * 12))
    }
}
