import Foundation
import SwiftUI

enum SessionState: String, Codable, CaseIterable {
    case working
    case waiting
    case approval
    case error
    case idle

    var title: String {
        switch self {
        case .working: "处理中"
        case .waiting: "等你回复"
        case .approval: "等待授权"
        case .error: "出现错误"
        case .idle: "暂时空闲"
        }
    }

    var explanation: String {
        switch self {
        case .working: "Claude 正在思考、读取文件或执行操作"
        case .waiting: "Claude 已回复，正在等你继续输入"
        case .approval: "有一项操作需要你确认后才能继续"
        case .error: "工具执行失败，建议打开对应窗口查看"
        case .idle: "会话已连接，目前没有正在进行的任务"
        }
    }

    var symbol: String {
        switch self {
        case .working: "cpu.fill"
        case .waiting: "ellipsis.bubble.fill"
        case .approval: "key.fill"
        case .error: "exclamationmark.triangle.fill"
        case .idle: "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .working: Color(red: 0.180, green: 0.514, blue: 0.980) // sky blue
        case .waiting: Color(red: 0.063, green: 0.596, blue: 0.451) // meadow teal
        case .approval: Color(red: 0.918, green: 0.286, blue: 0.176) // coral orange
        case .error: Color(red: 0.875, green: 0.220, blue: 0.255) // coral red
        case .idle: Color(red: 0.420, green: 0.478, blue: 0.557) // blue gray
        }
    }

    var priority: Int {
        switch self {
        case .approval: 5
        case .waiting: 4
        case .error: 3
        case .working: 2
        case .idle: 1
        }
    }
}

struct HookEvent: Codable {
    let sessionID: String
    let cwd: String
    let eventName: String
    let notificationType: String?
    let message: String?
    let transcriptPath: String?
    let receivedAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cwd
        case eventName = "hook_event_name"
        case notificationType = "notification_type"
        case message
        case transcriptPath = "transcript_path"
        case receivedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        eventName = try values.decode(String.self, forKey: .eventName)
        notificationType = try values.decodeIfPresent(String.self, forKey: .notificationType)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        transcriptPath = try values.decodeIfPresent(String.self, forKey: .transcriptPath)
        receivedAt = try values.decodeIfPresent(Date.self, forKey: .receivedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(cwd, forKey: .cwd)
        try values.encode(eventName, forKey: .eventName)
        try values.encodeIfPresent(notificationType, forKey: .notificationType)
        try values.encodeIfPresent(message, forKey: .message)
        try values.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
        try values.encode(receivedAt, forKey: .receivedAt)
    }
}

struct ClaudeSession: Identifiable, Equatable {
    let id: String
    var cwd: String
    var state: SessionState
    var detail: String?
    var lastUpdated: Date
    var transcriptPath: String?

    var projectName: String {
        guard !cwd.isEmpty else { return "Claude Code" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    var abbreviatedPath: String {
        (cwd as NSString).abbreviatingWithTildeInPath
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published var isExpanded = false

    var dominantState: SessionState {
        sessions.max(by: { $0.state.priority < $1.state.priority })?.state ?? .idle
    }

    var attentionCount: Int {
        sessions.filter { $0.state == .approval || $0.state == .waiting || $0.state == .error }.count
    }

    var sortedSessions: [ClaudeSession] {
        sessions.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority > $1.state.priority }
            return $0.lastUpdated > $1.lastUpdated
        }
    }

    func consume(_ event: HookEvent) {
        if event.eventName == "SessionEnd" {
            sessions.removeAll { $0.id == event.sessionID }
            return
        }

        let mapped = map(event)
        let detail = event.notificationType == "permission_prompt" ? event.message : nil
        if let index = sessions.firstIndex(where: { $0.id == event.sessionID }) {
            sessions[index].cwd = event.cwd.isEmpty ? sessions[index].cwd : event.cwd
            sessions[index].state = mapped
            sessions[index].detail = detail
            sessions[index].lastUpdated = event.receivedAt
            sessions[index].transcriptPath = event.transcriptPath ?? sessions[index].transcriptPath
        } else {
            sessions.append(ClaudeSession(
                id: event.sessionID,
                cwd: event.cwd,
                state: mapped,
                detail: detail,
                lastUpdated: event.receivedAt,
                transcriptPath: event.transcriptPath
            ))
        }
    }

    func remove(_ id: String) {
        sessions.removeAll { $0.id == id }
    }

    func expireStaleSessions() {
        let now = Date()
        sessions = sessions.compactMap { session in
            let age = now.timeIntervalSince(session.lastUpdated)
            if age > 24 * 60 * 60 { return nil }
            var updated = session
            if age > 2 * 60 * 60 && session.state == .working { updated.state = .idle }
            return updated
        }
    }

    private func map(_ event: HookEvent) -> SessionState {
        switch event.eventName {
        case "PermissionRequest": return .approval
        case "Notification":
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog": return .approval
            case "idle_prompt": return .waiting
            default: return .waiting
            }
        case "Stop": return .waiting
        case "StopFailure", "PostToolUseFailure": return .error
        case "SessionStart": return .idle
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolBatch": return .working
        default: return .working
        }
    }
}
