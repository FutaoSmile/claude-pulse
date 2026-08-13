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
            _ = try JSONDecoder().decode(HookEvent.self, from: data)
            try SocketTransport.emit(data)
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
    private var didLaunch = false
    private var layoutObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        launch()
    }

    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        createPanel()
        startServer()
        layoutObserver = NotificationCenter.default.addObserver(
            forName: .ccLightLayoutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resizePanel() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.expireStaleSessions() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        if let layoutObserver { NotificationCenter.default.removeObserver(layoutObserver) }
    }

    private func startServer() {
        let server = SocketServer { [weak self] event in
            Task { @MainActor in
                self?.store.consume(event)
                self?.resizePanel()
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
        // Both shapes share one stable center. Anchoring to the top-right made every
        // collapse look like the component moved right, and animated intermediate
        // frames could accumulate that offset during rapid toggles.
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
