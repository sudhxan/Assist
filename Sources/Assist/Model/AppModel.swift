import AppKit
import Observation
import SwiftUI

@MainActor
protocol NotchWindowBridge: AnyObject {
    func applyCapturePolicy()
    func releaseKeyFocus()
    func focusInput()
}

@MainActor @Observable
final class AppModel {
    static let earWidth: CGFloat = 54
    static let flare: CGFloat = 8
    static let expandedSize = CGSize(width: 700, height: 480)
    static let peekSize = CGSize(width: 460, height: 50)

    // MARK: Notch & panel

    var notchSize = CGSize(width: 185, height: 32)
    var hasHardwareNotch = true
    var state: NotchState = .collapsed {
        didSet {
            if state == .expanded { hasUnseenAnswer = false }
            if state != .expanded { showingSettings = false }
            if state == .expanded { wakeUp() } else if state == .collapsed { scheduleDoze() }
        }
    }
    /// Cursor is over the closed notch: the buddy stirs before the panel opens.
    var isHoveringNotch = false
    var sleepPhase = SleepPhase.asleep
    var isPinned = false
    var showingSettings = false
    var settingsTab = SettingsTab.context
    var focusInputRequest = 0

    // MARK: Listening

    var isListening = false
    var isStarting = false
    var startupStatus: String?
    var sessionStart: Date?
    var micLevel: Float = 0
    var systemLevel: Float = 0
    var systemAudioActive = false
    var lines: [TranscriptLine] = []
    var volatile: [Speaker: String] = [:]
    var transcriptRevision = 0
    var notice: Notice?

    // MARK: Assistant

    var cards: [AnswerCard] = []
    var selectedCardID: UUID?
    var hasUnseenAnswer = false
    var pendingQuestion = false
    var celebrating = false
    var inputText = ""
    var isDictating = false
    var isCapturingScreen = false

    // MARK: Settings (persisted)

    var provider = AIProvider.claude {
        didSet {
            defaults.set(provider.rawValue, forKey: Key.provider)
            guard provider != oldValue else { return }
            if provider.isLocal { prepareLocalModel() } else if oldValue.isLocal { unloadLocalModel() }
        }
    }
    var localModelID = LocalModelSpec.recommended.id {
        didSet {
            defaults.set(localModelID, forKey: Key.localModel)
            guard localModelID != oldValue else { return }
            unloadLocalModel()
            if provider.isLocal { prepareLocalModel() }
        }
    }
    var speechEngine = SpeechEngine.parakeet { didSet { defaults.set(speechEngine.rawValue, forKey: Key.speech) } }
    var modelID = ClaudeModel.all[0].id { didSet { defaults.set(modelID, forKey: Key.model) } }
    var openRouterModel = AIProvider.openRouter.defaultModel { didSet { defaults.set(openRouterModel, forKey: Key.openRouterModel) } }
    var geminiModel = AIProvider.gemini.defaultModel { didSet { defaults.set(geminiModel, forKey: Key.geminiModel) } }
    var profile = "" { didSet { defaults.set(profile, forKey: Key.profile) } }
    var prerequisites = "" { didSet { defaults.set(prerequisites, forKey: Key.prerequisites) } }
    var notes = "" { didSet { defaults.set(notes, forKey: Key.notes) } }
    var meetingContext = "" { didSet { defaults.set(meetingContext, forKey: Key.context) } }
    var autoAnswer = true { didSet { defaults.set(autoAnswer, forKey: Key.autoAnswer) } }
    var captureSystemAudio = true { didSet { defaults.set(captureSystemAudio, forKey: Key.systemAudio) } }
    var localeID = "en-US" { didSet { defaults.set(localeID, forKey: Key.locale) } }
    var hideFromScreenShare = true {
        didSet {
            defaults.set(hideFromScreenShare, forKey: Key.hide)
            window?.applyCapturePolicy()
        }
    }
    /// Providers with a key saved in the Keychain.
    var keyedProviders: Set<AIProvider> = []
    var hasAPIKey: Bool { keyedProviders.contains(provider) }

    // MARK: On-device model

    var localState = LocalModelState.notDownloaded
    /// The recognizer actually running, which may differ from `speechEngine` after a fallback.
    var activeSpeechEngine: SpeechEngine?
    var localSpec: LocalModelSpec { LocalModelSpec.named(localModelID) }

    // MARK: Plumbing

    @ObservationIgnored weak var window: NotchWindowBridge?
    /// Reports harness decisions (draft started, kept, verified, …); used by the end-to-end bench.
    @ObservationIgnored var trace: ((String) -> Void)?
    /// Per-card timing breakdown from the on-device engine, for the bench.
    @ObservationIgnored var statsDetail: [UUID: String] = [:]
    @ObservationIgnored let audio = AudioController()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cachedKeys: [AIProvider: String] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var autoAnswerTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSince: Date?
    @ObservationIgnored private var lastAutoQuestion: String?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var celebrateTask: Task<Void, Never>?
    @ObservationIgnored private var dozeTask: Task<Void, Never>?
    @ObservationIgnored private var dictationBase = ""
    @ObservationIgnored private var dictationFinal = ""
    @ObservationIgnored private var dictationFinishing = false
    @ObservationIgnored private var loadedLocalID: String?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var syncAgain = false
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// The engine job currently writing into each card; events from any other job are stale.
    @ObservationIgnored private var localJobs: [UUID: UUID] = [:]
    @ObservationIgnored private var draft: Draft?
    @ObservationIgnored private var volatileStart: [Speaker: Date] = [:]
    @ObservationIgnored private var appendedCount = 0
    @ObservationIgnored private var suggestions: [SuggestionNote] = []

    /// An answer Assist gave, threaded into the on-device model's transcript at the point it
    /// appeared. It's prefilled with the transcript in the background instead of being re-sent
    /// with every request, and the model sees its earlier advice in order.
    private struct SuggestionNote {
        let id = UUID()
        /// Sits after every line with `seq` up to this.
        let afterSeq: Int
        let start: Date
        let text: String
    }

    private enum TimelineRow {
        case line(TranscriptLine)
        case note(SuggestionNote)
    }

    /// An answer started speculatively at a pause, before the turn was final.
    private struct Draft {
        var cardID: UUID
        var jobID: UUID
        var key: String
        var question: String
    }

    private enum Key {
        static let provider = "provider", model = "model", openRouterModel = "openRouterModel", geminiModel = "geminiModel"
        static let profile = "profile", prerequisites = "prerequisites", notes = "notes", context = "meetingContext"
        static let autoAnswer = "autoAnswer", systemAudio = "captureSystemAudio", hide = "hideFromScreenShare"
        static let locale = "locale", localModel = "localModel", speech = "speechEngine"
        static func hasKey(_ provider: AIProvider) -> String {
            provider == .claude ? "hasStoredAPIKey" : "hasStoredAPIKey.\(provider.rawValue)"
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.model: ClaudeModel.all[0].id,
            Key.autoAnswer: true,
            Key.systemAudio: true,
            Key.hide: true,
            Key.locale: Locale.current.identifier,
        ])
        provider = AIProvider(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .claude
        modelID = ClaudeModel.named(defaults.string(forKey: Key.model) ?? "").id
        openRouterModel = defaults.string(forKey: Key.openRouterModel) ?? AIProvider.openRouter.defaultModel
        geminiModel = defaults.string(forKey: Key.geminiModel) ?? AIProvider.gemini.defaultModel
        profile = defaults.string(forKey: Key.profile) ?? ""
        prerequisites = defaults.string(forKey: Key.prerequisites) ?? ""
        notes = defaults.string(forKey: Key.notes) ?? ""
        meetingContext = defaults.string(forKey: Key.context) ?? ""
        autoAnswer = defaults.bool(forKey: Key.autoAnswer)
        captureSystemAudio = defaults.bool(forKey: Key.systemAudio)
        hideFromScreenShare = defaults.bool(forKey: Key.hide)
        localeID = defaults.string(forKey: Key.locale) ?? "en-US"
        localModelID = LocalModelSpec.named(defaults.string(forKey: Key.localModel) ?? "").id
        speechEngine = SpeechEngine(rawValue: defaults.string(forKey: Key.speech) ?? "") ?? .parakeet
        keyedProviders = Set(AIProvider.allCases.filter { defaults.bool(forKey: Key.hasKey($0)) })
        wireAudio()
        refreshLocalState()
        if provider.isLocal { prepareLocalModel() }
    }

    func shutdown() {
        tasks.values.forEach { $0.cancel() }
        let audio = audio
        Task.detached { await audio.stopMeeting() }
    }

    // MARK: Geometry

    func updateGeometry(for screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
            hasHardwareNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 180, height: max(menuBar, 28))
            hasHardwareNotch = false
        }
    }

    var collapsedSize: CGSize {
        CGSize(width: notchSize.width + 2 * Self.earWidth + 2 * Self.flare, height: notchSize.height)
    }

    var shapeSize: CGSize {
        switch state {
        case .collapsed: collapsedSize
        case .peek: CGSize(width: max(collapsedSize.width, Self.peekSize.width), height: notchSize.height + Self.peekSize.height)
        case .expanded: Self.expandedSize
        }
    }

    var bottomRadius: CGFloat {
        switch state {
        case .collapsed: notchSize.height * 0.36
        case .peek: 18
        case .expanded: 24
        }
    }

    /// Screen-space rect where the panel takes clicks (and hover keeps it open).
    func hitRect(in screenFrame: CGRect) -> CGRect {
        let size = shapeSize
        let pad: CGFloat = state == .collapsed ? 6 : 0
        return CGRect(x: screenFrame.midX - size.width / 2 - pad,
                      y: screenFrame.maxY - size.height - pad,
                      width: size.width + 2 * pad,
                      height: size.height + pad + 2) // +2: the cursor can sit on the screen's top edge
    }

    // MARK: Panel state

    func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        showingSettings = true
    }

    func expand(pinned: Bool) {
        peekTask?.cancel()
        state = .expanded
        if pinned { isPinned = true }
    }

    func collapse() {
        state = .collapsed
        isPinned = false
        window?.releaseKeyFocus()
    }

    private func showPeek(autoHideAfter seconds: Double?) {
        guard state != .expanded else { return }
        state = .peek
        peekTask?.cancel()
        guard let seconds else { return }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.state == .peek else { return }
            self.state = .collapsed
        }
    }

    var mood: BuddyMood {
        if isGenerating || isCapturingScreen { return .thinking }
        if pendingQuestion { return .alert }
        if celebrating { return .happy }
        if isListening || isDictating { return .listening }
        if state == .expanded { return .idle }
        if isHoveringNotch && sleepPhase != .awake { return .waking }
        switch sleepPhase {
        case .awake: return .idle
        case .drowsy: return .drowsy
        case .asleep: return .sleeping
        }
    }

    /// Where the buddy hops to: wherever the action is.
    var buddySpot: BuddySpot {
        guard state == .expanded else { return .ear }
        if showingSettings { return .header }
        if (isGenerating || celebrating) && selectedCard != nil { return .answer }
        if lines.isEmpty && volatile.isEmpty {
            if isListening { return .transcript }
            if cards.isEmpty { return .welcome }
        }
        return .header
    }

    // MARK: Napping

    private var canDoze: Bool {
        state != .expanded && !isListening && !isDictating && !isGenerating && !celebrating && !isHoveringNotch
    }

    private func wakeUp() {
        dozeTask?.cancel()
        sleepPhase = .awake
    }

    /// Once the notch closes and nothing's going on: awake → drowsy → asleep.
    private func scheduleDoze() {
        dozeTask?.cancel()
        guard sleepPhase != .asleep else { return }
        dozeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, self.state != .expanded else { return }
            guard self.canDoze else { return self.scheduleDoze() } // busy: check again shortly
            self.sleepPhase = .drowsy
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self.state != .expanded else { return }
            guard self.canDoze else { return self.scheduleDoze() }
            self.sleepPhase = .asleep
        }
    }

    var combinedLevel: Float { max(micLevel, systemLevel) }

    // MARK: Listening

    func toggleListening() {
        guard !isStarting else { return }
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isListening, !isStarting else { return }
        isStarting = true
        notice = nil
        let locale = Locale(identifier: localeID)
        let includeSystem = captureSystemAudio
        let engine = speechEngine
        Task {
            do {
                let result = try await audio.startMeeting(locale: locale, includeSystemAudio: includeSystem, engine: engine)
                isListening = true
                wakeUp()
                systemAudioActive = result.systemAudio
                activeSpeechEngine = result.engine
                if sessionStart == nil { sessionStart = Date() }
                if let error = result.systemAudioError {
                    notice = Notice(text: "Only hearing your mic. \(error.localizedDescription)",
                                    action: (error as? AssistError)?.noticeAction)
                } else if let error = result.speechFallback {
                    notice = Notice(text: "Using Apple speech recognition: Parakeet couldn't start (\(error.localizedDescription)).", isError: false)
                }
                startSettling()
            } catch {
                notice = Notice(error)
                expand(pinned: true)
            }
            isStarting = false
            startupStatus = nil
        }
    }

    func stopListening() {
        isListening = false
        systemAudioActive = false
        activeSpeechEngine = nil
        settleTask?.cancel()
        discardDraft()
        micLevel = 0
        systemLevel = 0
        pendingQuestion = false
        autoAnswerTask?.cancel()
        let audio = audio
        Task { await audio.stopMeeting() }
        if state != .expanded { scheduleDoze() }
    }

    func clearTranscript() {
        discardDraft()
        suggestions.removeAll()
        lines.removeAll()
        volatile.removeAll()
        volatileStart.removeAll()
        sessionStart = isListening ? Date() : nil
        lastAutoQuestion = nil
        transcriptRevision += 1
    }

    private func wireAudio() {
        audio.onTranscript = { [weak self] speaker, update in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handleTranscript(speaker, update) } }
        }
        audio.onLevel = { [weak self] speaker, level in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateLevel(speaker, level) } }
        }
        audio.onDictation = { [weak self] update in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handleDictation(update) } }
        }
        audio.onStatus = { [weak self] text in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.startupStatus = text } }
        }
        audio.onSystemAudioStopped = { [weak self] error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isListening else { return }
                    self.systemAudioActive = false
                    self.notice = Notice(text: "System audio stopped: \(error?.localizedDescription ?? "unknown reason"). Restart listening to retry.")
                }
            }
        }
    }

    private func updateLevel(_ speaker: Speaker, _ raw: Float) {
        guard isListening || isDictating else { return }
        if speaker == .them {
            systemLevel = raw > systemLevel ? raw : systemLevel * 0.55 + raw * 0.45
        } else {
            micLevel = raw > micLevel ? raw : micLevel * 0.55 + raw * 0.45
        }
    }

    private func handleTranscript(_ speaker: Speaker, _ update: LiveTranscriber.Update) {
        switch update {
        case .volatile(let raw):
            let text = raw.trimmed
            if volatile[speaker] == nil, !text.isEmpty { volatileStart[speaker] = Date() }
            volatile[speaker] = text.isEmpty ? nil : text
            transcriptRevision += 1
            if questionSpeakers.contains(speaker), !text.isEmpty { invalidateDraft(for: text) }
        case .pause(let raw):
            let text = raw.trimmed
            guard !text.isEmpty else { return }
            if speaker == .me, isEcho(text) { return }
            volatile[speaker] = text
            anticipate(speaker, text: text)
        case .final(let raw):
            let start = volatileStart[speaker]
            volatile[speaker] = nil
            volatileStart[speaker] = nil
            let text = raw.trimmed
            transcriptRevision += 1
            guard !text.isEmpty else { return }
            if speaker == .me, isEcho(text) { return }
            if speaker == .them { dropEchoedMicLines(matching: text) }
            appendFinal(speaker, text, start: start)
            if questionSpeakers.contains(speaker), let question = currentQuestion(), resolveDraft(question: question) {
                syncWarmPrefix()
                return
            }
            considerAutoAnswer(after: speaker, text: text)
            syncWarmPrefix()
        case .amend(let marks):
            // Late sentence-final punctuation from Parakeet belongs to the speaker's last line.
            guard let index = lines.lastIndex(where: { $0.speaker == speaker }),
                  Date().timeIntervalSince(lines[index].updated) < Self.settleAfter else { return }
            lines[index].text += marks
            transcriptRevision += 1
            if marks.contains("?"), draft == nil, !pendingQuestion { considerAutoAnswer(after: speaker, text: lines[index].text) }
        }
    }

    /// Utterances from the same speaker this close together are one turn. Longer gaps start a
    /// new line, so "the last thing they said" stays a single, unambiguous line.
    static let mergeWindow: TimeInterval = 2.5
    /// Lines older than this can't change any more (merges and late punctuation are done).
    static let settleAfter: TimeInterval = 3.5

    private func canMerge(_ speaker: Speaker, into last: TranscriptLine, now: Date) -> Bool {
        last.speaker == speaker && now.timeIntervalSince(last.updated) < Self.mergeWindow && last.text.count < 320
            && (suggestions.last?.afterSeq ?? 0) < last.seq
    }

    private func appendFinal(_ speaker: Speaker, _ text: String, start: Date? = nil) {
        let now = Date()
        if var last = lines.last, canMerge(speaker, into: last, now: now) {
            last.text += " " + text
            last.updated = now
            lines[lines.count - 1] = last
        } else {
            // Stamp the line when the speaker started, not when recognition finished.
            appendedCount += 1
            lines.append(TranscriptLine(speaker: speaker, text: text, start: min(start ?? now, now), updated: now, seq: appendedCount))
        }
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
    }

    /// With speakers (no headphones) the mic also hears the other side; skip those copies.
    private func isEcho(_ text: String) -> Bool {
        guard systemAudioActive else { return false }
        let now = Date()
        var recent = lines.suffix(8).filter { $0.speaker == .them && now.timeIntervalSince($0.updated) < 12 }.map(\.text)
        if let v = volatile[.them] { recent.append(v) }
        return recent.contains { EchoFilter.overlap(text, $0) >= 0.6 }
    }

    /// Your lines can be dropped as echoes this long after they're written, so they only
    /// settle into the model's warm prefix after it. Both recognizers report within about a
    /// second of each other, so this leaves wide margin.
    static let echoWindow: TimeInterval = 6

    private func dropEchoedMicLines(matching text: String) {
        let now = Date()
        lines.removeAll { $0.speaker == .me && now.timeIntervalSince($0.updated) < Self.echoWindow && EchoFilter.overlap($0.text, text) >= 0.6 }
    }

    // MARK: Auto answer

    private var questionSpeakers: Set<Speaker> { [.them, .room] }

    private func considerAutoAnswer(after speaker: Speaker, text: String) {
        guard autoAnswer, questionSpeakers.contains(speaker) else { return }
        if QuestionDetector.isQuestion(text) {
            if !pendingQuestion { pendingSince = Date() }
            pendingQuestion = true
        } else if localReady, !pendingQuestion, text.split(separator: " ").count >= 5 {
            // Not phrased as a question, but it may still be waiting on you ("I'd love to hear
            // about…"). Let the model decide.
            Task { [weak self] in
                guard let p = await self?.turnCheck(), p >= Self.replyThreshold, let self,
                      self.lines.last?.text.hasSuffix(text) == true, !self.pendingQuestion else { return }
                self.pendingSince = Date()
                self.pendingQuestion = true
                self.scheduleAutoAnswer()
            }
        }
        if pendingQuestion { scheduleAutoAnswer() }
    }

    /// Parakeet only finalizes after the speaker has gone quiet, so its finals are turn ends;
    /// Apple's recognizer finalizes mid-thought, so wait for a real pause.
    private var autoAnswerDelay: Duration {
        activeSpeechEngine == .parakeet ? .milliseconds(150) : .milliseconds(1300)
    }

    /// While listening, lines settle as time passes; fold them into the warm prefix.
    func startSettling() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.syncWarmPrefix()
            }
        }
    }

    /// Waits for a short pause after a question so we answer the whole thing, not half of it.
    private func scheduleAutoAnswer() {
        autoAnswerTask?.cancel()
        autoAnswerTask = Task { [weak self] in
            try? await Task.sleep(for: self?.autoAnswerDelay ?? .milliseconds(1300))
            guard !Task.isCancelled, let self, self.pendingQuestion else { return }
            let stillTalking = self.questionSpeakers.contains { !(self.volatile[$0] ?? "").isEmpty }
            let waitedTooLong = Date().timeIntervalSince(self.pendingSince ?? Date()) > 7
            if stillTalking && !waitedTooLong {
                self.scheduleAutoAnswer()
                return
            }
            self.pendingQuestion = false
            self.trace?("auto answer after final")
            self.answerNow(auto: true)
        }
    }

    /// The other side's most recent turn (up to three lines), including anything still being spoken.
    private func currentQuestion() -> String? {
        var parts: [String] = []
        // Words still being spoken are the newest part of the turn.
        var boundary: Date?
        for speaker in questionSpeakers {
            if let v = volatile[speaker], !v.isEmpty {
                parts.append(v)
                boundary = volatileStart[speaker] ?? Date()
            }
        }
        // Then their latest lines, back to your last line, as long as they run together
        // (a statement from a minute ago isn't part of this question).
        for line in lines.reversed() {
            if line.speaker == .me {
                if parts.isEmpty { continue } else { break }
            }
            if let boundary, boundary.timeIntervalSince(line.updated) > 8 { break }
            parts.insert(line.text, at: 0)
            boundary = line.start
            if parts.count >= 3 { break }
        }
        let question = parts.joined(separator: " ").trimmed
        return question.isEmpty ? nil : String(question.suffix(700))
    }

    // MARK: Asking the model

    var isGenerating: Bool { cards.contains { $0.phase == .streaming } }

    var selectedCard: AnswerCard? {
        cards.first { $0.id == selectedCardID } ?? cards.last
    }

    var selectedIndex: Int? {
        guard let card = selectedCard else { return nil }
        return cards.firstIndex { $0.id == card.id }
    }

    func selectCard(offset: Int) {
        guard let index = selectedIndex else { return }
        let next = min(max(index + offset, 0), cards.count - 1)
        selectedCardID = cards[next].id
    }

    func answerNow(auto: Bool = false) {
        let question = currentQuestion()
        if auto {
            guard let question, question != lastAutoQuestion else { return }
            lastAutoQuestion = question
        }
        if question == nil && lines.isEmpty {
            if !inputText.trimmed.isEmpty { sendChat(); return }
            notice = Notice(text: "Nothing heard yet. Press ⌘⇧L to start listening, or type a question below.", isError: false)
            expand(pinned: true)
            return
        }
        // On-device, the question is already the transcript's last turn; a fixed task keeps the
        // prompt identical to the one a speculative draft would have used.
        let task = provider.isLocal && question != nil ? Prompts.localAnswerTask : Prompts.answerTask(question: question)
        ask(kind: .answer, title: question ?? "What should I say next?", task: task)
    }

    func answer(line: TranscriptLine) {
        ask(kind: .answer, title: line.text, task: Prompts.answerTask(question: line.text))
    }

    func run(_ kind: CardKind) {
        switch kind {
        case .answer: answerNow()
        case .screen: analyzeScreen()
        case .recap: ask(kind: .recap, title: "Recap so far", task: Prompts.recapTask)
        case .followUps: ask(kind: .followUps, title: "What could I say next?", task: Prompts.followUpTask)
        case .explain: ask(kind: .explain, title: "Explain what just came up", task: Prompts.explainTask)
        case .chat: sendChat()
        }
    }

    func sendChat() {
        let text = inputText.trimmed
        guard !text.isEmpty else { return }
        inputText = ""
        ask(kind: .chat, title: text, task: Prompts.chatTask(text))
    }

    func analyzeScreen() {
        guard !isCapturingScreen else { return }
        isCapturingScreen = true
        let typed = inputText.trimmed
        let displayID = Self.displayUnderMouse()
        Task {
            defer { isCapturingScreen = false }
            do {
                let title = typed.isEmpty ? "What's on my screen?" : typed
                if provider.isLocal {
                    let image = try await ScreenGrabber.captureImage(displayID: displayID, maxDimension: 2600)
                    let text = try await ScreenText.recognize(image)
                    if !typed.isEmpty { inputText = "" }
                    ask(kind: .screen, title: title, task: Prompts.screenTextTask(text, typed: typed))
                    return
                }
                let jpeg = try await ScreenGrabber.capture(displayID: displayID)
                if !typed.isEmpty { inputText = "" }
                ask(kind: .screen, title: title, task: Prompts.screenTask(typed), image: jpeg)
            } catch {
                notice = Notice(error)
                expand(pinned: true)
            }
        }
    }

    func regenerate(_ card: AnswerCard) {
        ask(kind: card.kind, title: card.title, task: card.task, image: card.imageJPEG)
    }

    func copy(_ card: AnswerCard) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(card.text, forType: .string)
    }

    private func ask(kind: CardKind, title: String, task: String, image: Data? = nil) {
        let provider = provider
        if provider.isLocal {
            askLocal(kind: kind, title: title, task: task)
            return
        }
        guard let key = apiKey(for: provider) else {
            notice = Notice(text: "Add your \(provider.label) API key to get answers.", action: .apiKeySettings)
            expand(pinned: true)
            openSettings(.ai)
            return
        }

        let model = currentModel
        let id = createCard(kind: kind, title: title, task: task, image: image)
        let request = LLMRequest(
            system: systemPrompt,
            text: Prompts.user(task: task, transcript: transcriptForPrompt(), recent: recentRepliesForPrompt(excluding: id)),
            imageJPEG: image
        )
        tasks[id] = Task { [weak self] in
            do {
                for try await chunk in LLMClient.stream(request, provider: provider, model: model, apiKey: key) {
                    self?.append(chunk, to: id)
                }
                self?.finish(id, error: nil)
            } catch is CancellationError {
                self?.finish(id, error: nil)
            } catch {
                self?.finish(id, error: error)
            }
        }
    }

    @discardableResult
    private func createCard(kind: CardKind, title: String, task: String, image: Data?, id: UUID = UUID()) -> UUID {
        wakeUp()
        var card = AnswerCard(kind: kind, title: title, task: task, imageJPEG: image, modelLabel: currentModelLabel)
        card.id = id
        cards.append(card)
        if cards.count > 60 { cards.removeFirst(cards.count - 60) }
        selectedCardID = card.id
        if state == .collapsed { showPeek(autoHideAfter: nil) }
        return card.id
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].text += chunk
    }

    private func finish(_ id: UUID, error: Error?) {
        tasks[id] = nil
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if let error {
            cards[index].phase = .failed(error.localizedDescription)
        } else {
            cards[index].phase = .done
            celebrate()
        }
        if state != .expanded { hasUnseenAnswer = true }
        if state == .peek { showPeek(autoHideAfter: 14) }
    }

    private func celebrate() {
        celebrating = true
        celebrateTask?.cancel()
        celebrateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            self.celebrating = false
            if self.state == .collapsed { self.scheduleDoze() }
        }
    }

    func stamp(for date: Date) -> String {
        let start = sessionStart ?? lines.first?.start ?? date
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func transcriptForPrompt() -> String {
        var rows = lines.map { "[\(stamp(for: $0.start))] \($0.speaker.promptLabel): \($0.text)" }
        for speaker in [Speaker.them, .room, .me] {
            if let v = volatile[speaker], !v.isEmpty { rows.append("[now] \(speaker.promptLabel) (still speaking): \(v)") }
        }
        var out: [String] = []
        var count = 0
        for row in rows.reversed() {
            count += row.count
            if count > 16_000 { break }
            out.insert(row, at: 0)
        }
        return out.isEmpty ? "(nothing captured yet)" : out.joined(separator: "\n")
    }

    private func recentRepliesForPrompt(excluding id: UUID) -> String {
        cards.filter { $0.id != id && $0.phase == .done }.suffix(3).map {
            "Q: \($0.title.prefix(300))\nA: \($0.text.prefix(1200))"
        }.joined(separator: "\n\n")
    }

    private static func displayUnderMouse() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    // MARK: Provider, model & API keys

    var currentModel: String {
        switch provider {
        case .local: localSpec.id
        case .claude: modelID
        case .openRouter: openRouterModel.trimmed.isEmpty ? AIProvider.openRouter.defaultModel : openRouterModel.trimmed
        case .gemini: geminiModel.trimmed.isEmpty ? AIProvider.gemini.defaultModel : geminiModel.trimmed
        }
    }

    var currentModelLabel: String {
        switch provider {
        case .local: "\(localSpec.label) · on-device"
        case .claude: ClaudeModel.named(modelID).label
        case .openRouter: "OpenRouter · " + (currentModel.split(separator: "/").last.map(String.init) ?? currentModel)
        case .gemini: "Gemini · " + currentModel
        }
    }

    func apiKey(for provider: AIProvider) -> String? {
        if let cached = cachedKeys[provider] { return cached }
        guard let stored = Keychain.read(provider.keychainAccount), !stored.isEmpty else { return nil }
        cachedKeys[provider] = stored
        return stored
    }

    func saveAPIKey(_ raw: String, for provider: AIProvider) {
        let key = raw.trimmed
        guard !key.isEmpty else { return }
        Keychain.write(key, account: provider.keychainAccount)
        cachedKeys[provider] = key
        keyedProviders.insert(provider)
        defaults.set(true, forKey: Key.hasKey(provider))
        if notice?.action == .apiKeySettings { notice = nil }
    }

    func removeAPIKey(for provider: AIProvider) {
        Keychain.delete(provider.keychainAccount)
        cachedKeys[provider] = nil
        defaults.set(false, forKey: Key.hasKey(provider))
        keyedProviders.remove(provider)
    }

    // MARK: On-device model lifecycle

    func refreshLocalState() {
        switch localState {
        case .downloading, .loading: return
        default: break
        }
        if loadedLocalID == localSpec.id {
            localState = .ready
        } else {
            localState = localSpec.isDownloaded ? .downloaded : .notDownloaded
        }
    }

    func downloadLocalModel() {
        let spec = localSpec
        downloadTask?.cancel()
        localState = .downloading(0)
        let throttle = ProgressThrottle()
        downloadTask = Task { [weak self] in
            do {
                try await ModelDownloader.download(spec) { fraction in
                    guard throttle.shouldReport(fraction) else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, case .downloading = self.localState else { return }
                            self.localState = .downloading(fraction)
                        }
                    }
                }
                guard let self else { return }
                self.localState = .downloaded
                if self.provider.isLocal { self.prepareLocalModel() }
            } catch {
                guard let self else { return }
                self.localState = error is CancellationError ? .notDownloaded : .failed(error.localizedDescription)
                self.refreshLocalState()
            }
        }
    }

    func cancelLocalDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        localState = .notDownloaded
        refreshLocalState()
    }

    func deleteLocalModel() {
        unloadLocalModel()
        LocalModelStore.delete(localSpec)
        localState = .notDownloaded
    }

    /// Loads the selected model into memory and warms its kernels, so the first answer is fast.
    func prepareLocalModel() {
        guard provider.isLocal else { return }
        let spec = localSpec
        guard spec.isDownloaded else {
            localState = .notDownloaded
            return
        }
        if loadedLocalID == spec.id { localState = .ready; return }
        if case .loading = localState { return }
        localState = .loading
        loadTask = Task { [weak self] in
            do {
                try await LocalEngine.shared.load(spec)
                guard let self else { return }
                guard self.localSpec.id == spec.id, self.provider.isLocal else {
                    self.unloadLocalModel()
                    return
                }
                self.loadedLocalID = spec.id
                self.localState = .ready
                self.syncWarmPrefix()
            } catch {
                self?.localState = .failed(error.localizedDescription)
            }
        }
    }

    func unloadLocalModel() {
        loadTask?.cancel()
        discardDraft()
        loadedLocalID = nil
        Task { await LocalEngine.shared.unload() }
        if case .loading = localState { localState = .downloaded }
        refreshLocalState()
    }

    private var localReady: Bool { provider.isLocal && localState == .ready }

    private var promptContext: PromptContext {
        PromptContext(profile: profile, prerequisites: prerequisites, notes: notes, meeting: meetingContext)
    }

    private var systemPrompt: String { Prompts.system(promptContext) }
    private var localSystemPrompt: String { Prompts.system(promptContext, local: true) }

    /// Keeps the model's warm prefix up to date with the settled transcript. Runs in the
    /// background and steps aside the moment an answer is requested.
    private func syncWarmPrefix() {
        guard localReady else { return }
        if syncTask != nil {
            syncAgain = true
            return
        }
        let system = localSystemPrompt
        let settled = settledPrefixLines()
        syncTask = Task { [weak self] in
            await LocalEngine.shared.sync(system: system, settled: settled, background: true)
            guard let self else { return }
            self.syncTask = nil
            if self.syncAgain {
                self.syncAgain = false
                self.syncWarmPrefix()
            }
        }
    }

    /// Transcript lines and Assist's earlier suggestions, in the order they happened.
    private func timeline() -> [TimelineRow] {
        var rows: [TimelineRow] = []
        var pending = suggestions[...]
        for line in lines {
            while let note = pending.first, note.afterSeq < line.seq {
                rows.append(.note(note))
                pending = pending.dropFirst()
            }
            rows.append(.line(line))
        }
        rows += pending.map(TimelineRow.note)
        return rows
    }

    /// Rows settle once nothing can change them: merges and late punctuation stop after
    /// `settleAfter`, the echo filter revisits your own lines for `echoWindow`, and notes never
    /// change. The settled rows form a contiguous prefix.
    private func settledPrefixLines(now: Date = Date()) -> [PrefixLine] {
        var result: [PrefixLine] = []
        for row in timeline() {
            switch row {
            case .line(let line):
                let settle = line.speaker == .me ? Self.echoWindow : Self.settleAfter
                guard now.timeIntervalSince(line.updated) >= settle else { return result }
                result.append(PrefixLine(key: line.id, text: self.row(line.speaker, line.text, start: line.start)))
            case .note(let note):
                result.append(PrefixLine(key: note.id, text: noteRow(note)))
            }
        }
        return result
    }

    private func row(_ speaker: Speaker, _ text: String, start: Date) -> String {
        "[\(stamp(for: start))] \(speaker.promptLabel): \(text)"
    }

    private func noteRow(_ note: SuggestionNote) -> String {
        "[\(stamp(for: note.start))] Assist (suggested to me): \(note.text)"
    }

    /// Rows after the settled prefix, with words still being spoken rendered exactly as the
    /// final transcript will render them (including the merge into a recent line). A draft
    /// started at a pause then sees the same prompt the final turn produces, so it can be kept.
    private func unsettledRows(after settledCount: Int, now: Date) -> [String] {
        var tail = Array(timeline().dropFirst(settledCount))
        for speaker in [Speaker.them, .room, .me] {
            guard let text = volatile[speaker], !text.isEmpty else { continue }
            if case .line(var last)? = tail.last, canMerge(speaker, into: last, now: now) {
                last.text += " " + text
                tail[tail.count - 1] = .line(last)
            } else {
                tail.append(.line(TranscriptLine(speaker: speaker, text: text, start: volatileStart[speaker] ?? now, updated: now)))
            }
        }
        return tail.map { row in
            switch row {
            case .line(let line): self.row(line.speaker, line.text, start: line.start)
            case .note(let note): noteRow(note)
            }
        }
    }

    /// Records a finished on-device answer in the model's transcript.
    private func addNote(for cardID: UUID) {
        guard let card = cards.first(where: { $0.id == cardID }), card.kind != .recap else { return }
        let text = card.text.replacingOccurrences(of: "**", with: "")
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " / ")
        guard !text.isEmpty else { return }
        suggestions.append(SuggestionNote(afterSeq: appendedCount, start: card.created, text: String(text.prefix(500))))
        if suggestions.count > 200 { suggestions.removeFirst(suggestions.count - 200) }
    }

    /// The prompt for an on-device request, plus a key identifying its full rendered content
    /// (independent of how it's split between the warm prefix and the tail).
    private func localPrompt(task: String) -> (prompt: LocalPrompt, key: String) {
        let now = Date()
        let settled = settledPrefixLines(now: now)
        let rows = unsettledRows(after: settled.count, now: now)
        let system = localSystemPrompt
        let prompt = LocalPrompt(system: system, settled: settled,
                                 tail: Prompts.localTail(recentLines: rows, task: task))
        let key = ([system] + settled.map(\.text) + rows + [task]).joined(separator: "\n")
        return (prompt, key)
    }

    private func askLocal(kind: CardKind, title: String, task: String) {
        guard localReady else {
            notice = Notice(text: localState == .loading ? "The on-device model is still loading." : "Download the on-device model to get answers.",
                            action: .apiKeySettings)
            expand(pinned: true)
            if localState != .loading { openSettings(.ai) }
            return
        }
        let id = createCard(kind: kind, title: title, task: task, image: nil)
        runLocal(localPrompt(task: task).prompt, cardID: id)
    }

    /// Runs a request on the engine. The GPU serves one request at a time, so a new answer
    /// stops any older one still writing: the conversation has moved on, and the newest
    /// question is the one being asked.
    @discardableResult
    private func runLocal(_ prompt: LocalPrompt, cardID: UUID) -> UUID {
        let engine = LocalEngine.shared
        let jobID = UUID()
        for (card, job) in localJobs {
            engine.signals.cancel(job)
            localJobs[card] = nil
            // A job cancelled before it starts never reports back, so close its card here.
            if card != cardID, let index = cards.firstIndex(where: { $0.id == card }), cards[index].phase == .streaming {
                cards[index].phase = .done
                if draft?.cardID != card { addNote(for: card) }
            }
        }
        localJobs[cardID] = jobID
        engine.signals.enter()
        let requestedAt = Date()
        tasks[cardID] = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await engine.generate(prompt, id: jobID, continuing: nil, maxTokens: 600, requestedAt: requestedAt) { event in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.applyLocal(event, cardID: cardID, jobID: jobID) }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.localJobs[cardID] == jobID else { return }
                        self.localJobs[cardID] = nil
                        self.finish(cardID, error: error)
                    }
                }
            }
            engine.signals.leave()
        }
        return jobID
    }

    private func applyLocal(_ event: LocalEvent, cardID: UUID, jobID: UUID) {
        guard localJobs[cardID] == jobID, let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        switch event {
        case .replace(let text):
            cards[index].text = text
        case .delta(let chunk):
            cards[index].text += chunk
        case .finished(let stats):
            localJobs[cardID] = nil
            cards[index].stats = stats.summary
            if draft?.cardID != cardID { addNote(for: cardID) }
            if trace != nil {
                statsDetail[cardID] = String(format: "queued %.0f ms · sync %.0f ms · prefill %d tok over %d warm · %d tok out",
                                             stats.queuedSeconds * 1000, stats.syncSeconds * 1000,
                                             stats.prefillTokens, stats.reusedTokens, stats.generatedTokens)
            }
            finish(cardID, error: nil)
        }
    }

    /// SpeculativeETD's verifier stage: when the cheap question detector says no, ask the
    /// model whether the last utterance still expects a reply (one short forward pass).
    private func turnCheck() async -> Double? {
        guard localReady else { return nil }
        let now = Date()
        let settled = settledPrefixLines(now: now)
        let prompt = LocalPrompt(system: localSystemPrompt, settled: settled,
                                 tail: Prompts.turnCheckTail(recentLines: unsettledRows(after: settled.count, now: now)))
        let engine = LocalEngine.shared
        engine.signals.enter()
        defer { engine.signals.leave() }
        return await engine.expectsReply(prompt)
    }

    // MARK: Speculative answers (on-device)

    /// Endpoint anticipation: the moment the other side pauses on what looks like a question,
    /// start answering. If the final transcript matches, the draft simply becomes the answer.
    private func anticipate(_ speaker: Speaker, text: String) {
        guard autoAnswer, isListening, localReady, questionSpeakers.contains(speaker) else { return }
        guard let question = currentQuestion(), question != lastAutoQuestion else { return }
        if QuestionDetector.isQuestion(text) {
            startDraft(question)
        } else if text.split(separator: " ").count >= 5 {
            Task { [weak self] in
                guard let p = await self?.turnCheck() else { return }
                self?.trace?(String(format: "turn check at pause: p(reply)=%.2f", p))
                guard p >= Self.replyThreshold, let self, self.currentQuestion() == question, self.draft == nil else { return }
                self.startDraft(question)
            }
        }
    }

    static let replyThreshold = 0.65

    private func startDraft(_ question: String) {
        let cardID = draft?.cardID ?? UUID()
        let (prompt, key) = localPrompt(task: Prompts.localAnswerTask)
        if let draft, Self.normalized(draft.key) == Self.normalized(key) { return }
        if let index = cards.firstIndex(where: { $0.id == cardID }) {
            cards[index].text = ""
            cards[index].title = question
            cards[index].phase = .streaming
            cards[index].stats = nil
            selectedCardID = cardID
        } else {
            createCard(kind: .answer, title: question, task: Prompts.localAnswerTask, image: nil, id: cardID)
        }
        let jobID = runLocal(prompt, cardID: cardID)
        draft = Draft(cardID: cardID, jobID: jobID, key: key, question: question)
        trace?("draft started: \(question)")
    }

    /// They kept talking, so the draft answers a question that isn't finished. Drop it; the
    /// next pause starts a new one.
    private func invalidateDraft(for text: String) {
        guard let draft, !Self.normalized(draft.question).hasSuffix(Self.normalized(text)) else { return }
        discardDraft()
    }

    /// The turn is final. If the draft saw the same words, it already is the answer: keep it.
    /// (A trailing "?" that arrived late doesn't change what was asked.) Otherwise they said
    /// more than the draft heard, so answer afresh in the same card.
    ///
    /// PredGen-style verification (`LocalEngine.generate(continuing:)`) would salvage the
    /// agreeing prefix instead, but on this model greedy answers diverge within a few tokens
    /// of any real change (see `Assist --bench`), so regenerating is faster.
    /// Returns false when there was no draft to resolve.
    private func resolveDraft(question: String) -> Bool {
        guard let current = draft else { return false }
        draft = nil
        lastAutoQuestion = question
        pendingQuestion = false
        autoAnswerTask?.cancel()
        let (prompt, key) = localPrompt(task: Prompts.localAnswerTask)
        guard let index = cards.firstIndex(where: { $0.id == current.cardID }) else { return false }
        if Self.normalized(key) == Self.normalized(current.key) {
            trace?("draft kept: final transcript matched")
            if localJobs[current.cardID] == nil { addNote(for: current.cardID) }
            return true
        }
        trace?("draft replaced: the question changed")
        cards[index].title = question
        cards[index].phase = .streaming
        cards[index].stats = nil
        cards[index].text = ""
        runLocal(prompt, cardID: current.cardID)
        return true
    }

    /// Drops an unconfirmed draft and its card: it was only ever a guess.
    private func discardDraft() {
        guard let current = draft else { return }
        draft = nil
        trace?("draft discarded")
        if let job = localJobs[current.cardID] { LocalEngine.shared.signals.cancel(job) }
        localJobs[current.cardID] = nil
        tasks[current.cardID] = nil
        if let index = cards.firstIndex(where: { $0.id == current.cardID }) {
            cards.remove(at: index)
            if selectedCardID == current.cardID { selectedCardID = cards.last?.id }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Dictation (hold ⌘ or the mic button)

    func beginDictation() {
        guard !isDictating, !dictationFinishing else { return }
        isDictating = true
        dictationBase = inputText.trimmed
        dictationFinal = ""
        let locale = Locale(identifier: localeID)
        Task {
            do {
                try await audio.startDictation(locale: locale)
            } catch {
                isDictating = false
                notice = Notice(error)
            }
        }
    }

    func endDictation() {
        guard isDictating else { return }
        isDictating = false
        dictationFinishing = true
        Task {
            await audio.stopDictation()
            dictationFinishing = false
            micLevel = 0
            if !dictationFinal.trimmed.isEmpty { sendChat() }
        }
    }

    private func handleDictation(_ update: LiveTranscriber.Update) {
        guard isDictating || dictationFinishing else { return }
        switch update {
        case .pause, .amend:
            break
        case .volatile(let text):
            inputText = Self.join(dictationBase, dictationFinal, text)
        case .final(let text):
            dictationFinal = Self.join(dictationFinal, text)
            inputText = Self.join(dictationBase, dictationFinal)
        }
    }

    private static func join(_ parts: String...) -> String {
        parts.map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Demo

    func loadDemo() {
        let now = Date()
        sessionStart = now.addingTimeInterval(-286)
        systemAudioActive = true
        lines = [
            TranscriptLine(speaker: .them, text: "Thanks for joining. Before we get into the roadmap, how does your team handle incident response today?", start: now.addingTimeInterval(-140), updated: now.addingTimeInterval(-132)),
            TranscriptLine(speaker: .me, text: "Sure. We run a weekly on-call rotation with a primary and a secondary, and every incident gets a blameless review.", start: now.addingTimeInterval(-120), updated: now.addingTimeInterval(-104)),
            TranscriptLine(speaker: .them, text: "Got it. And if you had a free hand, what would you change about the on-call rotation?", start: now.addingTimeInterval(-40), updated: now.addingTimeInterval(-34)),
        ]
        cards = [
            AnswerCard(kind: .answer,
                       title: "If you had a free hand, what would you change about the on-call rotation?",
                       task: Prompts.answerTask(question: "What would you change about the on-call rotation?"),
                       text: """
                       - **Follow-the-sun handoffs** between US and EU so nobody gets paged at 3am.
                       - **Cap pages per shift**: anything noisier than two actionable alerts gets a fix-it ticket.
                       - **20-minute weekly review** to kill flaky alerts and share what we learned.
                       - New engineers **shadow one rotation** before going primary.
                       """,
                       phase: .done,
                       modelLabel: currentModelLabel),
        ]
        selectedCardID = cards.last?.id
        transcriptRevision += 1
        state = .expanded
        isPinned = true
    }
}
