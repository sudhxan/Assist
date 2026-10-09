import Speech
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            TabBar(selection: $model.settingsTab)
            ScrollView(showsIndicators: false) {
                Group {
                    switch model.settingsTab {
                    case .context: ContextSettings()
                    case .ai: AISettings()
                    case .general: GeneralSettings()
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
    }
}

// MARK: - Tabs

private struct TabBar: View {
    @Binding var selection: SettingsTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) { selection = tab }
                } label: {
                    Label(tab.rawValue, systemImage: tab.symbol)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(selection == tab ? AnyShapeStyle(.black) : AnyShapeStyle(.white.opacity(0.65)))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if selection == tab {
                                Capsule().fill(Palette.auroraLinear).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Context

private struct ContextSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Section(title: "About me", symbol: "person.crop.circle") {
                    Editor(text: $model.profile, placeholder: "Your role, experience, projects and wins, so answers sound like you.")
                }
                Section(title: "Prerequisites", symbol: "checklist") {
                    Editor(text: $model.prerequisites, placeholder: "What to know going in: job description, agenda, product facts, pasted docs…")
                }
            }
            GridRow {
                Section(title: "Notes & instructions", symbol: "note.text") {
                    Editor(text: $model.notes, placeholder: "How I should answer, e.g. \"Use STAR format\", \"Max 3 bullets\", \"Always mention our SOC 2 report\".")
                }
                Section(title: "This meeting", symbol: "calendar") {
                    Editor(text: $model.meetingContext, placeholder: "Who's attending and what you want out of it.")
                }
            }
        }
    }
}

// MARK: - AI model

private struct AISettings: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var openRouterModels: [String] = []
    @State private var geminiModels: [String] = []
    @State private var listStatus: String?

    private let openRouterPicks = ["anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5", "openai/gpt-6.1-sol",
                                   "google/gemini-3.8-flash", "deepseek/deepseek-v4.1-flash", "x-ai/grok-4.7"]
    private let geminiPicks = ["gemini-3.8-flash", "gemini-3.5-flash-lite", "gemini-3.1-pro-preview"]

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Section(title: "Provider", symbol: "cpu") {
                    Picker("", selection: $model.provider) {
                        ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(providerBlurb)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.provider.isLocal {
                    LocalModelStatus()
                } else {
                    Section(title: "\(model.provider.label) API key", symbol: "key.fill") {
                        HStack(spacing: 6) {
                            SecureField(model.hasAPIKey ? "Key saved · paste to replace" : model.provider.keyPlaceholder, text: $keyDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
                                .onSubmit(saveKey)
                            Button("Save", action: saveKey)
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(keyDraft.trimmed.isEmpty ? .white.opacity(0.3) : Palette.mint)
                                .disabled(keyDraft.trimmed.isEmpty)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: model.hasAPIKey ? "checkmark.seal.fill" : "key")
                                .foregroundStyle(model.hasAPIKey ? Palette.mint : .white.opacity(0.4))
                            Text(model.hasAPIKey ? "Stored in your Keychain" : "Get one at \(model.provider.keySource)")
                                .foregroundStyle(.white.opacity(0.45))
                            Spacer()
                            if model.hasAPIKey {
                                Button("Remove") { model.removeAPIKey(for: model.provider) }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .font(.system(size: 10.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Section(title: "Model", symbol: "sparkles") {
                switch model.provider {
                case .local:
                    Picker("", selection: $model.localModelID) {
                        ForEach(LocalModelSpec.all) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(localBlurb)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                case .claude:
                    Picker("", selection: $model.modelID) {
                        ForEach(ClaudeModel.all) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Opus is smartest, Haiku answers fastest.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                case .openRouter:
                    ModelField(text: $model.openRouterModel, placeholder: "vendor/model", picks: openRouterPicks,
                               catalog: openRouterModels, status: listStatus)
                case .gemini:
                    ModelField(text: $model.geminiModel, placeholder: "gemini-…", picks: geminiPicks,
                               catalog: geminiModels, status: listStatus)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: "\(model.provider.rawValue)-\(model.hasAPIKey)") { await loadCatalog() }
    }

    private var localBlurb: String {
        let spec = model.localSpec
        var text = spec.blurb
        if spec.id == LocalModelSpec.recommended.id { text += " Recommended for this Mac." }
        return text + " The transcript stays prefilled in the model's cache and drafting begins the moment they pause, so answers start about half a second after they stop talking."
    }

    private var providerBlurb: String {
        switch model.provider {
        case .local: "Runs entirely on this Mac with MLX. Nothing leaves your computer, and it works offline."
        case .claude: "Anthropic's Claude, direct. Low-effort thinking for quick replies."
        case .openRouter: "One key, hundreds of models: Claude, GPT, Gemini, DeepSeek, Grok and more."
        case .gemini: "Google's Gemini through the Gemini API (AI Studio key)."
        }
    }

    private func saveKey() {
        model.saveAPIKey(keyDraft, for: model.provider)
        keyDraft = ""
    }

    private func loadCatalog() async {
        listStatus = nil
        switch model.provider {
        case .local, .claude:
            return
        case .openRouter:
            guard openRouterModels.isEmpty else { break }
            listStatus = "Loading models…"
            do { openRouterModels = try await ModelCatalog.openRouterModels() } catch { listStatus = "Couldn't load the model list."; return }
        case .gemini:
            guard geminiModels.isEmpty else { break }
            guard let key = model.apiKey(for: .gemini) else {
                listStatus = "Save a key to browse every model."
                return
            }
            listStatus = "Loading models…"
            do { geminiModels = try await ModelCatalog.geminiModels(apiKey: key) } catch { listStatus = error.localizedDescription; return }
        }
        let count = model.provider == .openRouter ? openRouterModels.count : geminiModels.count
        listStatus = "\(count) models · type to filter, then pick from the list"
    }
}

/// Download, load and readiness of the on-device model.
private struct LocalModelStatus: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingRemove = false

    var body: some View {
        let spec = model.localSpec
        Section(title: "On-device model", symbol: "memorychip") {
            switch model.localState {
            case .notDownloaded:
                StatusRow(symbol: "arrow.down.circle", tint: .white.opacity(0.5),
                          text: String(format: "%@ · %.1f GB download", spec.label, spec.downloadGB)) {
                    Button("Download") { model.downloadLocalModel() }
                }
            case .downloading(let fraction):
                ProgressView(value: fraction)
                    .tint(Palette.mint)
                StatusRow(symbol: "arrow.down.circle.fill", tint: Palette.mint,
                          text: String(format: "Downloading %@ · %.0f%%", spec.label, fraction * 100)) {
                    Button("Cancel") { model.cancelLocalDownload() }
                }
            case .downloaded:
                StatusRow(symbol: "internaldrive", tint: .white.opacity(0.5), text: "Downloaded") {
                    Button("Load") { model.prepareLocalModel() }
                }
            case .loading:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading into memory and warming up…")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.system(size: 10.5))
            case .ready:
                StatusRow(symbol: "checkmark.seal.fill", tint: Palette.mint, text: "Ready · nothing leaves this Mac") {
                    // Re-downloading takes minutes, so deleting takes a second click.
                    Button(confirmingRemove ? String(format: "Delete %.1f GB?", spec.downloadGB) : "Remove") {
                        if confirmingRemove {
                            model.deleteLocalModel()
                        } else {
                            confirmingRemove = true
                            Task {
                                try? await Task.sleep(for: .seconds(4))
                                confirmingRemove = false
                            }
                        }
                    }
                    .foregroundStyle(confirmingRemove ? AnyShapeStyle(.orange) : AnyShapeStyle(.white.opacity(0.45)))
                }
            case .failed(let message):
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                StatusRow(symbol: "exclamationmark.triangle", tint: .orange, text: "Couldn't get the model ready") {
                    Button("Retry") { spec.isDownloaded ? model.prepareLocalModel() : model.downloadLocalModel() }
                }
            }
        }
    }
}

private struct StatusRow<Action: View>: View {
    let symbol: String
    let tint: Color
    let text: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            action
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.mint)
        }
        .font(.system(size: 10.5))
    }
}

/// Free-form model ID with quick picks and a filterable menu of everything the provider offers.
private struct ModelField: View {
    @Binding var text: String
    let placeholder: String
    let picks: [String]
    let catalog: [String]
    let status: String?

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
            Menu {
                if matches.isEmpty {
                    Text(catalog.isEmpty ? "No list loaded" : "No matches")
                }
                ForEach(matches, id: \.self) { id in
                    Button(id) { text = id }
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(catalog.isEmpty)
        }
        FlowChips(items: picks, selected: text) { text = $0 }
        if let status {
            Text(status)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var matches: [String] {
        let query = text.trimmed.lowercased()
        let filtered = catalog.contains(text) || query.isEmpty ? catalog : catalog.filter { $0.lowercased().contains(query) }
        return Array(filtered.prefix(60))
    }
}

private struct FlowChips: View {
    let items: [String]
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { item in
                        // Show "claude-sonnet-5.5" for "anthropic/claude-sonnet-5.5"; the full ID is what's saved.
                        PickChip(title: item.split(separator: "/").last.map(String.init) ?? item,
                                 isSelected: item == selected) { pick(item) }
                            .help(item)
                    }
                }
            }
        }
    }
}

private struct PickChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(isSelected ? AnyShapeStyle(.black) : AnyShapeStyle(.white.opacity(0.75)))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(isSelected ? AnyShapeStyle(Palette.auroraLinear) : AnyShapeStyle(.white.opacity(hovering ? 0.14 : 0.07))))
                .scaleEffect(hovering ? 1.05 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isSelected)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var locales: [Locale] = []

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: 12) {
            Section(title: "Listening", symbol: "ear") {
                Toggle("Hear other people on the call", isOn: $model.captureSystemAudio)
                Toggle("Answer questions automatically", isOn: $model.autoAnswer)
                Picker("Speech recognition", selection: $model.speechEngine) {
                    Text("Parakeet · most accurate").tag(SpeechEngine.parakeet)
                    Text("Apple").tag(SpeechEngine.apple)
                }
                .pickerStyle(.menu)
                Text(speechBlurb)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Language", selection: $model.localeID) {
                    if !locales.contains(where: { $0.identifier == model.localeID }) {
                        Text(name(for: model.localeID)).tag(model.localeID)
                    }
                    ForEach(locales, id: \.identifier) { locale in
                        Text(name(for: locale.identifier)).tag(locale.identifier)
                    }
                }
                .pickerStyle(.menu)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Section(title: "Privacy", symbol: "eye.slash") {
                    Toggle("Invisible to screen share & recording", isOn: $model.hideFromScreenShare)
                    Text("Transcripts stay in memory and disappear when you quit.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                HStack {
                    Spacer()
                    Button("Quit Assist") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            let supported = await SpeechTranscriber.supportedLocales
            locales = supported.sorted { name(for: $0.identifier) < name(for: $1.identifier) }
            // Normalize the saved locale ("en_US" vs "en-US") so the picker shows it.
            if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: model.localeID)),
               locales.contains(where: { $0.identifier == match.identifier }) {
                model.localeID = match.identifier
            }
        }
    }

    private func name(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private var speechBlurb: String {
        switch model.speechEngine {
        case .parakeet:
            guard ParakeetTranscriber.supports(Locale(identifier: model.localeID)) else {
                return "Parakeet is English-only, so Apple's recognizer handles \(name(for: model.localeID))."
            }
            return "NVIDIA Parakeet on the Neural Engine: about 3× fewer errors than Apple's and finals in ~0.7 s. "
                + (ParakeetTranscriber.isDownloaded ? "Downloaded." : "0.6 GB download the first time you listen.")
        case .apple:
            return "Apple's on-device recognizer. Works in every language macOS supports."
        }
    }
}

// MARK: - Building blocks

private struct Section<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Palette.auroraLinear)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PanelBackground())
    }
}

private struct Editor: View {
    @Binding var text: String
    let placeholder: String
    var height: CGFloat = 128

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
    }
}
