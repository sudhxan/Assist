import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless, non-activating panel that sits over the menu bar around the notch.
/// `sharingType = .none` keeps it out of screen shares, recordings and screenshots.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Borderless windows normally get pushed below the menu bar; we want to sit on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController: NotchWindowBridge {
    /// Fixed transparent canvas; the visible notch shape animates inside it. Leaves room for the drop shadow.
    static let canvas = CGSize(width: 820, height: 590)

    private let model: AppModel
    private let panel = NotchPanel()
    private let forceVisibleToCapture: Bool
    private var screen: NSScreen
    private var trackingTimer: Timer?
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var monitors: [Any] = []
    private var holdToTalk: DispatchWorkItem?

    init(model: AppModel, forceVisibleToCapture: Bool) {
        self.model = model
        self.forceVisibleToCapture = forceVisibleToCapture
        self.screen = Self.preferredScreen()

        let host = NotchHostingView(rootView: NotchContainer(model: model))
        host.sizingOptions = []
        panel.contentView = host

        model.window = self
        applyCapturePolicy()
        layout()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
        installMonitors()
    }

    func show() {
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    /// Renders the panel's own views to a PNG. Debug aid: an app drawing its own window
    /// needs no screen-recording permission.
    func snapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: NotchWindowBridge

    func applyCapturePolicy() {
        panel.sharingType = (model.hideFromScreenShare && !forceVisibleToCapture) ? .none : .readOnly
    }

    /// Hands keyboard focus back to whatever app the user was in.
    func releaseKeyFocus() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    func focusInput() {
        model.expand(pinned: true)
        model.showingSettings = false
        panel.makeKeyAndOrderFront(nil)
        model.focusInputRequest += 1
    }

    // MARK: Actions

    func togglePinned() {
        if model.state == .expanded {
            model.collapse()
        } else {
            model.expand(pinned: true)
        }
    }

    // MARK: Layout

    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenParametersChanged() {
        screen = Self.preferredScreen()
        layout()
    }

    private func layout() {
        model.updateGeometry(for: screen)
        let frame = screen.frame
        let canvas = Self.canvas
        panel.setFrame(NSRect(x: (frame.midX - canvas.width / 2).rounded(),
                              y: frame.maxY - canvas.height,
                              width: canvas.width, height: canvas.height),
                       display: true)
    }

    // MARK: Hover tracking

    /// Polls the cursor: the panel only accepts clicks where the notch is actually drawn,
    /// and hovering the notch opens it.
    private func trackMouse() {
        let mouse = NSEvent.mouseLocation
        let inside = model.hitRect(in: screen.frame).contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        let hovering = inside && model.state != .expanded
        if model.isHoveringNotch != hovering { model.isHoveringNotch = hovering }

        let now = Date()
        switch model.state {
        case .collapsed, .peek:
            outsideSince = nil
            guard inside else { hoverSince = nil; return }
            if hoverSince == nil { hoverSince = now }
            // A beat longer than a twitch, so you see the buddy stir before the panel opens.
            if let since = hoverSince, now.timeIntervalSince(since) > 0.35 {
                model.expand(pinned: false)
                hoverSince = nil
            }
        case .expanded:
            hoverSince = nil
            if inside || model.isPinned || model.isDictating {
                outsideSince = nil
                return
            }
            if outsideSince == nil { outsideSince = now }
            if let since = outsideSince, now.timeIntervalSince(since) > 0.45 {
                model.collapse()
                outsideSince = nil
            }
        }
    }

    // MARK: Event monitors

    private func installMonitors() {
        // A click inside the open panel pins it, so it stays open while you read or type.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.panel, self.model.state == .expanded { self.model.isPinned = true }
            }
            return event
        }) { monitors.append(m) }

        // A click anywhere else closes it.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.state == .expanded, !self.model.isDictating else { return }
                if !self.model.hitRect(in: self.screen.frame).contains(NSEvent.mouseLocation) { self.model.collapse() }
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: { [weak self] event in
            guard let self else { return event }
            let swallow = MainActor.assumeIsolated { self.handleKey(event) }
            return swallow ? nil : event
        }) { monitors.append(m) }
    }

    /// Returns true when the key event was handled and should not reach the text field.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }

        if event.type == .flagsChanged {
            // Hold ⌘ on its own to dictate into the input.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, model.state == .expanded, !model.showingSettings {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.model.beginDictation() }
                }
                holdToTalk?.cancel()
                holdToTalk = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            } else {
                holdToTalk?.cancel()
                holdToTalk = nil
                if model.isDictating { model.endDictation() }
            }
            return false
        }

        // Any real key press means ⌘ is part of a shortcut, not a hold-to-talk.
        holdToTalk?.cancel()
        holdToTalk = nil

        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.showingSettings { model.showingSettings = false } else { model.collapse() }
            return true
        case kVK_LeftArrow where event.modifierFlags.contains(.command) && model.inputText.isEmpty:
            model.selectCard(offset: -1)
            return true
        case kVK_RightArrow where event.modifierFlags.contains(.command) && model.inputText.isEmpty:
            model.selectCard(offset: 1)
            return true
        default:
            return false
        }
    }
}
