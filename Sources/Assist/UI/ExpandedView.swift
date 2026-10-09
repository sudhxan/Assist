import SwiftUI

struct ExpandedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            HeaderRow()
            if let notice = model.notice {
                NoticeBanner(notice: notice)
            }
            if model.showingSettings {
                SettingsView()
            } else {
                HStack(spacing: 10) {
                    TranscriptPanel()
                        .frame(width: 250)
                    AnswerPanel()
                }
                ActionChips()
                InputBar()
            }
        }
        .padding(.horizontal, AppModel.flare + 12)
        .padding(.bottom, 14)
        .frame(width: AppModel.expandedSize.width, height: AppModel.expandedSize.height, alignment: .top)
    }
}

// MARK: - Header

private struct HeaderRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                BuddySlot(spot: .header, size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Assist")
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    StatusLine()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Keep clear of the camera housing.
            Color.clear.frame(width: model.notchSize.width + 12)

            HStack(spacing: 4) {
                ListenButton()
                IconButton(symbol: model.isPinned ? "pin.fill" : "pin", help: "Keep open (⌘\\)", active: model.isPinned) {
                    model.isPinned.toggle()
                }
                IconButton(symbol: model.showingSettings ? "xmark" : "gearshape.fill", help: "Settings") {
                    model.showingSettings.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: max(model.notchSize.height, 34))
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(text(now: context.date))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.isListening ? Palette.mint.opacity(0.9) : .white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private func text(now: Date) -> String {
        if model.isStarting { return model.startupStatus ?? "Waking up…" }
        if model.isListening {
            let seconds = Int(now.timeIntervalSince(model.sessionStart ?? now))
            let source = model.systemAudioActive ? "mic + call" : "mic only"
            let engine = model.activeSpeechEngine.map { " · \($0.label)" } ?? ""
            return String(format: "Listening · %@%@ · %d:%02d", source, engine, seconds / 60, seconds % 60)
        }
        if model.provider.isLocal, model.localState == .loading { return "Loading \(model.localSpec.label)…" }
        return "Ready · ⌘⇧L to listen"
    }
}

private struct ListenButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button { model.toggleListening() } label: {
            HStack(spacing: 5) {
                if model.isStarting {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .fill(model.isListening ? AnyShapeStyle(Color.red) : AnyShapeStyle(Palette.auroraLinear))
                        .frame(width: 7, height: 7)
                }
                Text(model.isListening ? "Stop" : "Listen")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Start / stop listening (⌘⇧L)")
    }
}

// MARK: - Transcript

private struct TranscriptPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("LIVE")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.45))
                if model.isListening {
                    LevelPill(label: model.systemAudioActive ? "You" : "Room", level: model.micLevel,
                              color: model.systemAudioActive ? Palette.mint : Palette.violet)
                    if model.systemAudioActive {
                        LevelPill(label: "Them", level: model.systemLevel, color: Palette.sky)
                    }
                }
                Spacer(minLength: 0)
                if !model.lines.isEmpty {
                    IconButton(symbol: "trash", help: "Clear transcript", size: 10) { model.clearTranscript() }
                }
            }
            .frame(height: 20)

            if model.lines.isEmpty && model.volatile.isEmpty {
                EmptyTranscript()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(model.lines) { line in
                                TranscriptRow(line: line)
                                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                            }
                            ForEach([Speaker.them, .room, .me], id: \.self) { speaker in
                                if let text = model.volatile[speaker] {
                                    VolatileRow(speaker: speaker, text: text)
                                }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: model.lines.count)
                    }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: model.transcriptRevision) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground())
    }
}

private struct LevelPill: View {
    let label: String
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5 + CGFloat(level) * 4, height: 5 + CGFloat(level) * 4)
                .frame(width: 9, height: 9)
                .animation(.easeOut(duration: 0.1), value: level)
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

private struct EmptyTranscript: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            BuddySlot(spot: .transcript, size: 36, seat: true)
            Text(model.isListening ? "All ears. Say something!" : "Not listening yet.")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text(model.isListening
                 ? "Questions from the other side get answered automatically."
                 : "Hit Listen (or ⌘⇧L) and I'll follow the conversation and whisper answers.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }
}

private struct TranscriptRow: View {
    @Environment(AppModel.self) private var model
    let line: TranscriptLine
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(Palette.speaker(line.speaker)).frame(width: 6, height: 6)
                Text(line.speaker.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.speaker(line.speaker))
                Text(model.stamp(for: line.start))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.3))
                Spacer(minLength: 0)
                if hovering && line.speaker != .me {
                    Button { model.answer(line: line) } label: {
                        Label("Answer", systemImage: "sparkles")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.mint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 14)
            Text(line.text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct VolatileRow: View {
    let speaker: Speaker
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(Palette.speaker(speaker).opacity(0.5)).frame(width: 6, height: 6)
                Text(speaker.label + " …")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.speaker(speaker).opacity(0.6))
            }
            Text(text)
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Answers

private struct AnswerPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let card = model.selectedCard {
                CardView(card: card)
                    .id(card.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.9, anchor: .top).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                WelcomeView()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.selectedCard?.id)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground(glowing: model.selectedCard?.phase == .streaming))
        // Perch on the card's top edge, where the buddy sits while it writes and celebrates.
        .overlay(alignment: .top) {
            BuddySlot(spot: .answer, size: 24)
                .offset(y: -20)
                .allowsHitTesting(false)
        }
    }
}

private struct CardView: View {
    @Environment(AppModel.self) private var model
    let card: AnswerCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: card.kind.symbol)
                    Text(card.kind.label.uppercased()).tracking(1)
                }
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.auroraLinear)
                Spacer(minLength: 0)
                if model.cards.count > 1, let index = model.selectedIndex {
                    IconButton(symbol: "chevron.left", help: "Previous (⌘←)", size: 10) { model.selectCard(offset: -1) }
                    Text("\(index + 1)/\(model.cards.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                    IconButton(symbol: "chevron.right", help: "Next (⌘→)", size: 10) { model.selectCard(offset: 1) }
                }
                if card.phase != .streaming {
                    IconButton(symbol: "arrow.clockwise", help: "Try again", size: 10) { model.regenerate(card) }
                }
                IconButton(symbol: "doc.on.doc", help: "Copy", size: 10) { model.copy(card) }
            }
            .frame(height: 20)

            Text(card.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if card.text.isEmpty && card.phase == .streaming {
                            ThinkingDots()
                        }
                        MarkdownText(text: card.text)
                        if case .failed(let message) = card.phase {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: card.text.count) {
                    if card.phase == .streaming { proxy.scrollTo("end", anchor: .bottom) }
                }
            }

            Text(([card.modelLabel] + (card.stats.map { [$0] } ?? []) + [card.created.formatted(date: .omitted, time: .shortened)])
                    .joined(separator: " · "))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
                .lineLimit(1)
        }
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    private let shortcuts: [(String, String)] = [
        ("⌘⇧L", "Start / stop listening"),
        ("⌘↩", "Answer the latest question"),
        ("⌘⇧↩", "Look at my screen"),
        ("⌘⇧K", "Ask me anything"),
        ("⌘\\", "Show / hide this panel"),
        ("hold ⌘", "Talk to me while typing"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BuddySlot(spot: .welcome, size: 30, seat: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hey! I'm your notch buddy.")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Invisible to screen share. Answers land right here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shortcuts, id: \.0) { key, label in
                    HStack(spacing: 8) {
                        KeyCap(text: key).frame(width: 56, alignment: .leading)
                        Text(label)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(.top, 2)
            if let step = setupStep {
                Button {
                    model.openSettings(.ai)
                } label: {
                    Label(step.title, systemImage: step.symbol)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.auroraLinear))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// What's still missing before answers can work, if anything.
    private var setupStep: (title: String, symbol: String)? {
        if model.provider.isLocal {
            return model.localState == .notDownloaded ? ("Download the on-device model", "arrow.down.circle.fill") : nil
        }
        return model.hasAPIKey ? nil : ("Add your \(model.provider.label) API key", "key.fill")
    }
}

// MARK: - Actions & input

private struct ActionChips: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    private let chips: [(title: String, kind: CardKind, shortcut: String?)] = [
        ("Answer", .answer, "⌘↩"),
        ("Screen", .screen, "⌘⇧↩"),
        ("Recap", .recap, nil),
        ("Follow-ups", .followUps, nil),
        ("Explain", .explain, nil),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                ActionChip(title: chip.title, symbol: chip.kind.symbol, shortcut: chip.shortcut) { model.run(chip.kind) }
                    // Pop in one after another when the panel opens.
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.42, dampingFraction: 0.5).delay(0.08 + Double(index) * 0.045), value: appeared)
            }
            Spacer(minLength: 0)
        }
        .onAppear { appeared = true }
    }
}

private struct InputBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Image(systemName: model.isDictating ? "waveform" : "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.auroraLinear)
                .symbolEffect(.variableColor.iterative, isActive: model.isDictating)
                .frame(width: 16)
            ZStack(alignment: .leading) {
                if model.inputText.isEmpty {
                    placeholder.allowsHitTesting(false)
                }
                TextField("", text: $model.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit { model.sendChat() }
            }
            HoldToTalkButton()
            Button { model.sendChat() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(model.inputText.trimmed.isEmpty ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(Palette.auroraLinear))
            }
            .buttonStyle(.plain)
            .disabled(model.inputText.trimmed.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused || model.isDictating ? AnyShapeStyle(Palette.auroraLinear) : AnyShapeStyle(.white.opacity(0.08)),
                        lineWidth: focused || model.isDictating ? 1 : 0.5)
        )
        .onChange(of: model.focusInputRequest) { focused = true }
    }

    @ViewBuilder
    private var placeholder: some View {
        if model.isDictating {
            Text("Listening… let go to send")
                .font(.system(size: 13))
                .foregroundStyle(Palette.mint.opacity(0.8))
        } else {
            HStack(spacing: 5) {
                Text("Type or hold")
                KeyCap(text: "command")
                Text("to speak")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.38))
        }
    }
}

private struct HoldToTalkButton: View {
    @Environment(AppModel.self) private var model
    @State private var pressed = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(model.isDictating ? AnyShapeStyle(.black) : AnyShapeStyle(.white.opacity(0.6)))
            .frame(width: 24, height: 24)
            .background(Circle().fill(model.isDictating ? AnyShapeStyle(Palette.auroraLinear) : AnyShapeStyle(.white.opacity(0.08))))
            .scaleEffect(pressed ? 1.15 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        model.beginDictation()
                    }
                    .onEnded { _ in
                        pressed = false
                        model.endDictation()
                    }
            )
            .help("Hold to talk")
    }
}
