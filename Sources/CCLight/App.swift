import AppKit
import SwiftUI

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        super.draw(dirtyRect)
    }
}

private final class ActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            NSApplication.shared.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.sendEvent(event)
    }
}

@main
@MainActor
struct CCLightMain {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.dropFirst().first == "emit" {
            runEmitter()
            return
        }
        if CommandLine.arguments.dropFirst().first == "demo" {
            runDemoEmitter()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        installMainMenu(on: app)
        delegate.launch()
        app.run()
    }

    private static func installMainMenu(on app: NSApplication) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "Claude Pulse")
        let quitItem = NSMenuItem(
            title: "退出 Claude Pulse",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = app
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        app.mainMenu = mainMenu
    }

    private static func runEmitter() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else { exit(0) }
        do {
            guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let environment = ProcessInfo.processInfo.environment
            payload["_claude_pulse_terminal_program"] = environment["TERM_PROGRAM"]
                ?? environment["LC_TERMINAL"]
            payload["_claude_pulse_terminal_session_id"] = environment["ITERM_SESSION_ID"]
                ?? environment["TERM_SESSION_ID"]
            payload["_claude_pulse_terminal_bundle_id"] = environment["__CFBundleIdentifier"]
            payload["_claude_pulse_tmux_pane"] = environment["TMUX_PANE"]

            let enrichedData = try JSONSerialization.data(withJSONObject: payload)
            _ = try JSONDecoder().decode(HookEvent.self, from: enrichedData)
            try SocketTransport.emit(enrichedData)
        } catch {
            // Hooks must never interrupt Claude Code. A missing app is intentionally silent.
        }
    }

    private static func runDemoEmitter() {
        let states: [(String, String?)] = [
            ("UserPromptSubmit", nil),
            ("PermissionRequest", nil),
            ("Notification", "idle_prompt")
        ]
        for (index, item) in states.enumerated() {
            let payload: [String: Any] = [
                "session_id": "demo-\(index)",
                "cwd": ["/Users/demo/api-server", "/Users/demo/aurora-web", "/Users/demo/design-system"][index],
                "hook_event_name": item.0,
                "notification_type": item.1 as Any
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? SocketTransport.emit(data)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PanelDefaults {
        static let width = 362.0
        static let height = 520.0
    }

    private let store = SessionStore()
    private var server: SocketServer?
    private var panel: NSPanel?
    private var timer: Timer?
    private var titleRefreshTimer: Timer?
    private var didLaunch = false
    private var expansionObserver: NSObjectProtocol?
    private var preferredToggleAnchor: NSPoint?
    private var lastAlignedFrame: NSRect?

    func applicationDidFinishLaunching(_ notification: Notification) {
        launch()
    }

    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        createPanel()
        startServer()
        expansionObserver = NotificationCenter.default.addObserver(
            forName: .ccLightExpansionRequested,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let expanded = notification.userInfo?["expanded"] as? Bool else { return }
            Task { @MainActor in self?.setExpanded(expanded) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.expireStaleSessions() }
        }
        titleRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAllConversationTitles() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        timer?.invalidate()
        titleRefreshTimer?.invalidate()
        if let expansionObserver { NotificationCenter.default.removeObserver(expansionObserver) }
    }

    private func startServer() {
        let server = SocketServer { [weak self] event in
            Task { @MainActor in
                self?.store.consume(event)
                self?.resizePanel()
                self?.scheduleTitleRefresh(for: event)
            }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            let alert = NSAlert()
            alert.messageText = "Claude Pulse 无法启动"
            alert.informativeText = "本地事件通道创建失败：\(error.localizedDescription)"
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleTitleRefresh(for event: HookEvent) {
        let titleEvents = ["SessionStart", "UserPromptSubmit", "Stop", "Notification"]
        guard titleEvents.contains(event.eventName) else { return }
        for delay in [0.2, 1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshConversationTitle(for: event.sessionID)
            }
        }
    }

    private func refreshAllConversationTitles() {
        let sessions = store.sessions.filter(\.supportsPreciseTerminalFocus)
        let lookups = SessionNavigator.conversationTitles(for: sessions)
        for session in sessions {
            guard let lookup = lookups[session.id] else { continue }
            store.updateConversationTitle(lookup.title, for: session.id)
        }
    }

    private func refreshConversationTitle(for sessionID: String) {
        guard
            let session = store.session(withID: sessionID),
            let lookup = SessionNavigator.conversationTitle(for: session)
        else { return }
        store.updateConversationTitle(lookup.title, for: sessionID)
    }

    private func createPanel() {
        let initialSize = panelSize()
        let panel = ActivatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 1
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        let hostingView = TransparentHostingView(rootView: FloatingLightView(store: store))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        self.panel = panel
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    private func positionPanel(_ panel: NSPanel) {
        // Anchor to the macOS primary display (the one whose global origin is 0,0).
        // `NSScreen.main` follows the currently focused app and can unexpectedly place
        // this panel on a secondary monitor.
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.screens.first(where: { $0.frame.minX == 0 && $0.frame.minY == 0 })
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - panel.frame.width - 18
        let y = visible.maxY - panel.frame.height - 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func resizePanel() {
        guard let panel else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let size = panelSize()
        panel.styleMask = [.borderless]

        var frame = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        frame = constrainedToVisibleScreen(frame, preferredScreen: panel.screen)
        panel.setFrame(frame, display: true, animate: false)
    }

    private func setExpanded(_ expanded: Bool) {
        guard let panel, store.isExpanded != expanded else { return }
        let sourceRole: ControlAnchorRole = expanded ? .capsuleDisclosure : .panelCollapse
        let targetRole: ControlAnchorRole = expanded ? .panelCollapse : .capsuleDisclosure
        let currentScreenPoint = controlAnchorScreenPoint(role: sourceRole) ?? NSEvent.mouseLocation
        // AppKit can round a borderless window by one pixel after layout. Treat only
        // a real pointer move as a new user-selected anchor so rounding never builds
        // into cumulative drift across repeated toggles.
        let windowWasMoved = lastAlignedFrame.map {
            hypot($0.origin.x - panel.frame.origin.x, $0.origin.y - panel.frame.origin.y) > 3
        } ?? true
        if preferredToggleAnchor == nil || windowWasMoved {
            preferredToggleAnchor = currentScreenPoint
        }
        let screenPoint = preferredToggleAnchor ?? currentScreenPoint

        store.setExpandedByUser(expanded)
        resizePanel()
        alignControlAnchor(role: targetRole, to: screenPoint, attemptsRemaining: 3)
    }

    private func alignControlAnchor(
        role: ControlAnchorRole,
        to screenPoint: NSPoint,
        attemptsRemaining: Int
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            guard let currentScreenPoint = self.controlAnchorScreenPoint(role: role) else {
                if attemptsRemaining > 0 {
                    self.alignControlAnchor(
                        role: role,
                        to: screenPoint,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                }
                return
            }

            var frame = panel.frame.offsetBy(
                dx: screenPoint.x - currentScreenPoint.x,
                dy: screenPoint.y - currentScreenPoint.y
            )
            frame = self.constrainedToVisibleScreen(frame, preferredScreen: panel.screen)
            panel.setFrame(frame, display: true, animate: false)
            self.lastAlignedFrame = frame
        }
    }

    private func controlAnchorScreenPoint(role: ControlAnchorRole) -> NSPoint? {
        guard
            let panel,
            let contentView = panel.contentView,
            let anchorView = findControlAnchor(in: contentView, role: role)
        else { return nil }
        let localCenter = NSPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY)
        let windowPoint = anchorView.convert(localCenter, to: nil)
        return panel.convertPoint(toScreen: windowPoint)
    }

    private func findControlAnchor(in view: NSView, role: ControlAnchorRole) -> ControlAnchorView? {
        if let anchor = view as? ControlAnchorView, anchor.role == role {
            return anchor
        }
        for subview in view.subviews {
            if let anchor = findControlAnchor(in: subview, role: role) {
                return anchor
            }
        }
        return nil
    }

    private func panelSize() -> NSSize {
        if store.isExpanded {
            return NSSize(width: PanelDefaults.width, height: PanelDefaults.height)
        }
        return collapsedPanelSize()
    }

    private func collapsedPanelSize() -> NSSize {
        let title: String
        if store.attentionCount > 0 {
            title = "\(store.attentionCount) 项待处理"
        } else if store.sessions.isEmpty {
            title = "暂无任务"
        } else {
            title = "\(store.sessions.count) 个会话进行中"
        }
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        // The title is always visible when attention is needed; otherwise reserve the
        // same footprint so the window and capsule boundaries stay stable on hover.
        // 10 leading + 25 logo + 8 gap + 7 status + 8 gap + text + 8 gap
        // + 22 disclosure + 8 trailing.
        return NSSize(width: 96 + textWidth, height: 44)
    }

    private func constrainedToVisibleScreen(_ frame: NSRect, preferredScreen: NSScreen?) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let screen = preferredScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }

        var result = frame
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

}
