import AppKit
import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.090, green: 0.212, blue: 0.165)
    static let secondary = Color(red: 0.337, green: 0.443, blue: 0.388)
    static let brand = Color(red: 0.839, green: 0.337, blue: 0.231)
    static let brandInk = Color(red: 0.173, green: 0.388, blue: 0.286)
    static let border = Color(red: 0.714, green: 0.831, blue: 0.749)
    static let divider = Color(red: 0.851, green: 0.910, blue: 0.867)
    static let surface = Color(red: 0.988, green: 0.996, blue: 0.984)
    static let surfaceTint = Color(red: 0.925, green: 0.969, blue: 0.933)
    static let control = Color(red: 0.867, green: 0.941, blue: 0.886)
}

struct FloatingLightView: View {
    @ObservedObject var store: SessionStore
    @State private var pulse = false
    @State private var hovering = false
    @State private var hoveringDisclosure = false

    var body: some View {
        Group {
            if store.isExpanded {
                SessionPanel(store: store) { requestExpanded(false) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                capsule
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
    }

    private var capsule: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                BrandIcon(size: 25)

                Circle()
                    .fill(store.dominantState.color)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse && store.dominantState == .working ? 1.25 : 1)
                    .shadow(
                        color: store.dominantState == .working
                            ? store.dominantState.color.opacity(0.35)
                            : .clear,
                        radius: 3
                    )

                Text(capsuleTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText())
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(WindowDragSurface())
            .help("按住并拖动可移动位置")
            .accessibilityLabel("Claude Pulse 状态，拖动可移动位置")

            Button {
                requestExpanded(true)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.brandInk)
                    .frame(width: 24, height: 24)
                    .background(
                        Palette.control.opacity(hoveringDisclosure ? 1 : 0.72),
                        in: Circle()
                    )
                    .background(ControlAnchorReader(role: .capsuleDisclosure))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .help("展开会话面板")
            .accessibilityLabel("展开会话面板")
            .onHover { value in
                withAnimation(.easeOut(duration: 0.12)) { hoveringDisclosure = value }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(hovering ? Palette.surfaceTint : Palette.surface, in: Capsule())
        .overlay(Capsule().stroke(Palette.border, lineWidth: hovering ? 1.2 : 0.8))
        .contentShape(Capsule())
        .onHover { value in
            withAnimation(.easeOut(duration: 0.14)) { hovering = value }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var capsuleTitle: String {
        if store.attentionCount > 0 { return "\(store.attentionCount) 项待处理" }
        if store.sessions.isEmpty { return "暂无任务" }
        return "\(store.sessions.count) 个会话进行中"
    }
}

private struct SessionPanel: View {
    @ObservedObject var store: SessionStore
    let collapse: () -> Void
    @State private var showsLegend = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)

            Group {
                if store.sessions.isEmpty {
                    EmptySessionsView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.sortedSessions) { session in
                                SessionRow(session: session) { store.remove(session.id) }
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Palette.surface, Palette.surfaceTint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Palette.border, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    BrandIcon(size: 21)
                    Text("CLAUDE PULSE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Palette.brand)
                }
                Text(panelHeadline)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
            }

            Spacer(minLength: 8)
            Button {
                showsLegend.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .background(Palette.control, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.brandInk)
            .help("查看状态说明")
            .accessibilityLabel("查看状态说明")
            .popover(isPresented: $showsLegend, arrowEdge: .top) {
                StatusLegend(close: { showsLegend = false })
                    .frame(width: 310)
            }
            headerButton("power", help: "退出 Claude Pulse（不会关闭 Claude Code）") {
                NSApplication.shared.terminate(nil)
            }
            headerButton("chevron.up", help: "收起为状态胶囊", action: collapse)
                .background(ControlAnchorReader(role: .panelCollapse))
        }
        .padding(.horizontal, 17)
        .padding(.top, 16)
        .padding(.bottom, 13)
        .contentShape(Rectangle())
        .background(WindowDragSurface())
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 27, height: 27)
                .background(Palette.control, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.brandInk)
        .help(help)
        .accessibilityLabel(help)
    }

    private var panelHeadline: String {
        if store.sessions.isEmpty { return "目前没有活跃会话" }
        if store.attentionCount > 0 { return "有 \(store.attentionCount) 项需要你处理" }
        if store.dominantState == .working { return "Claude 正在处理任务" }
        return "Claude Code 会话"
    }
}

private struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Palette.brand)
            Text("Claude Code 下次有活动时\n会自动显示在这里")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Button {
                SessionNavigator.open(session)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(session.state.color.opacity(0.13))
                        StatusGlyph(state: session.state, size: 24)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.projectName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(session.state.title).foregroundStyle(session.state.color)
                            if session.state != .waiting {
                                Text("·")
                                TimelineView(.periodic(from: .now, by: 1)) { _ in
                                    Text(session.lastUpdated, style: .relative)
                                }
                            }
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.secondary)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: session.supportsPreciseTerminalFocus ? "arrow.up.forward.app" : "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.brandInk)
                        .opacity(hovering ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .help(session.supportsPreciseTerminalFocus ? "切回对应的 iTerm2 会话" : "打开工作目录")

            if hovering {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(Palette.control, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.brandInk)
                .help("从面板隐藏此会话（不会结束 Claude Code；有新活动时会再次出现）")
                .accessibilityLabel("从面板隐藏会话，不结束 Claude Code")
                .transition(.opacity.combined(with: .scale))
            } else if !session.supportsPreciseTerminalFocus {
                Circle()
                    .fill(session.state.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: session.state.color.opacity(0.55), radius: 3)
            }
        }
        .padding(10)
        .background(
            hovering ? Palette.control.opacity(0.72) : Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.divider, lineWidth: hovering ? 1 : 0.7)
        )
        .onHover { value in
            withAnimation(.easeOut(duration: 0.15)) { hovering = value }
        }
        .help(session.abbreviatedPath)
        .contextMenu {
            if session.supportsPreciseTerminalFocus {
                Button("切回 iTerm2 会话") { SessionNavigator.focusTerminal(session) }
            }
            Button("打开工作目录") { SessionNavigator.openWorkingDirectory(session) }
            Button("复制工作目录路径") { SessionNavigator.copyWorkingDirectory(session) }
            if session.transcriptPath != nil {
                Divider()
                Button("显示会话记录文件") { SessionNavigator.revealTranscript(session) }
            }
        }
    }
}

private struct StatusLegend: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Claude Pulse 支持的状态")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondary)
                .help("关闭状态说明")
            }
            ForEach(SessionState.allCases, id: \.self) { state in
                HStack(alignment: .top, spacing: 9) {
                    StatusGlyph(state: state, size: 24)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink)
                        Text(state.explanation)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Palette.surface)
    }
}

private struct StatusGlyph: View {
    let state: SessionState
    let size: CGFloat

    var body: some View {
        if state == .working {
            WorkingAIGlyph(size: size)
        } else {
            Image(systemName: state.symbol)
                .font(.system(size: size * 0.58, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: size, height: size)
                .background(state.color.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(state.color.opacity(0.22), lineWidth: 0.7))
                .accessibilityLabel(state.title)
        }
    }
}

private struct WorkingAIGlyph: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.8) / 1.8
            ZStack {
                Circle()
                    .stroke(SessionState.working.color.opacity(0.16), lineWidth: max(1.2, size * 0.065))
                Circle()
                    .trim(from: 0.06, to: 0.42)
                    .stroke(
                        SessionState.working.color,
                        style: StrokeStyle(lineWidth: max(1.4, size * 0.075), lineCap: .round)
                    )
                    .rotationEffect(.degrees(phase * 360))

                BrandIcon(size: size * 0.54)
                    .clipShape(Circle())

                Circle()
                    .fill(SessionState.working.color)
                    .frame(width: size * 0.16, height: size * 0.16)
                    .offset(y: -size * 0.48)
                    .rotationEffect(.degrees(phase * 360))
                    .shadow(color: SessionState.working.color.opacity(0.5), radius: 2)
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel("Claude 正在处理任务")
    }
}

private struct BrandIcon: View {
    private static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "ClaudeIcon-Rounded", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return image
    }()

    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Claude Code")
    }
}

enum ControlAnchorRole: String {
    case capsuleDisclosure
    case panelCollapse
}

extension Notification.Name {
    static let ccLightExpansionRequested = Notification.Name("app.cclight.expansionRequested")
}

private func requestExpanded(_ expanded: Bool) {
    NotificationCenter.default.post(
        name: .ccLightExpansionRequested,
        object: nil,
        userInfo: ["expanded": expanded]
    )
}

private struct ControlAnchorReader: NSViewRepresentable {
    let role: ControlAnchorRole

    func makeNSView(context: Context) -> ControlAnchorView {
        ControlAnchorView(role: role)
    }

    func updateNSView(_ nsView: ControlAnchorView, context: Context) {
        nsView.role = role
    }
}

final class ControlAnchorView: NSView {
    var role: ControlAnchorRole

    init(role: ControlAnchorRole) {
        self.role = role
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

}

private struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NativeWindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NativeWindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
}
