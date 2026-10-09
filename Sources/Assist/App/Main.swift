import AppKit
import Carbon.HIToolbox

@main
enum AssistMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--bench") }) {
            Task.detached {
                await Bench.run(CommandLine.arguments)
                exit(0)
            }
            RunLoop.main.run()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var notch: NotchWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let options = LaunchOptions(CommandLine.arguments)

        // Demo and screenshot runs use their own settings domain, never the user's.
        let defaults = options.isolatedSettings ? UserDefaults(suiteName: "com.sudhan.assist.demo") ?? .standard : .standard
        if options.isolatedSettings { defaults.removePersistentDomain(forName: "com.sudhan.assist.demo") }
        model = AppModel(defaults: defaults)
        if let provider = options.provider { model.provider = provider }
        notch = NotchWindowController(model: model, forceVisibleToCapture: options.visibleToCapture)
        notch.show()
        registerHotKeys()

        if options.demo { model.loadDemo() }
        if let state = options.state { model.state = state; model.isPinned = state == .expanded }
        if let tab = options.settingsTab { model.expand(pinned: true); model.openSettings(tab) }
        if let path = options.snapshotPath {
            // Give the on-device model time to load so its status shows, then render and quit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.notch.snapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    private func registerHotKeys() {
        let keys = HotKeyCenter.shared
        keys.register(keyCode: kVK_ANSI_Backslash, modifiers: cmdKey) { [weak self] in self?.notch.togglePinned() }
        keys.register(keyCode: kVK_Return, modifiers: cmdKey) { [weak self] in self?.model.answerNow() }
        keys.register(keyCode: kVK_Return, modifiers: cmdKey | shiftKey) { [weak self] in self?.model.analyzeScreen() }
        keys.register(keyCode: kVK_ANSI_K, modifiers: cmdKey | shiftKey) { [weak self] in self?.notch.focusInput() }
        keys.register(keyCode: kVK_ANSI_L, modifiers: cmdKey | shiftKey) { [weak self] in self?.model.toggleListening() }
    }
}

/// Debug/demo switches: `--demo`, `--visible-to-capture`, `--state=collapsed|peek|expanded`,
/// `--settings=context|ai|general`, `--provider=local|claude|openRouter|gemini`, `--snapshot=<png>`.
/// `--demo` and `--provider` run with throwaway settings, so they never change the real ones.
struct LaunchOptions {
    var demo = false
    var visibleToCapture = false
    var provider: AIProvider?
    /// `--snapshot=/path/to.png`: render the panel to a PNG after a few seconds, then quit.
    var snapshotPath: String?
    var isolatedSettings: Bool { demo || provider != nil || snapshotPath != nil }
    var state: NotchState?
    var settingsTab: SettingsTab?

    init(_ args: [String]) {
        demo = args.contains("--demo")
        visibleToCapture = args.contains("--visible-to-capture")
        snapshotPath = args.first(where: { $0.hasPrefix("--snapshot=") }).map { String($0.dropFirst("--snapshot=".count)) }
        if let raw = args.first(where: { $0.hasPrefix("--provider=") })?.dropFirst("--provider=".count) {
            provider = AIProvider(rawValue: String(raw))
        }
        if let raw = args.first(where: { $0.hasPrefix("--state=") })?.dropFirst("--state=".count) {
            switch raw {
            case "collapsed": state = .collapsed
            case "peek": state = .peek
            case "expanded": state = .expanded
            default: break
            }
        }
        if let raw = args.first(where: { $0.hasPrefix("--settings=") })?.dropFirst("--settings=".count) {
            settingsTab = SettingsTab.allCases.first { $0.rawValue.lowercased().hasPrefix(raw.lowercased()) }
        }
    }
}

/// Accessory apps have no visible menu bar, but the Edit menu's key equivalents
/// are what make ⌘C / ⌘V / ⌘A work inside text fields.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Assist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        return main
    }
}
