import AppKit
import Foundation

@MainActor
enum SessionNavigator {
    struct ConversationTitleLookup {
        let title: String?
    }

    static func conversationTitle(for session: ClaudeSession) -> ConversationTitleLookup? {
        conversationTitles(for: [session])[session.id]
    }

    static func conversationTitles(
        for sessions: [ClaudeSession]
    ) -> [String: ConversationTitleLookup] {
        let sessionsByTerminalID = Dictionary(
            grouping: sessions.compactMap { session in
                session.iTermSessionID.map { ($0, session.id) }
            },
            by: \.0
        )
        guard !sessionsByTerminalID.isEmpty else { return [:] }

        let targetIDs = sessionsByTerminalID.keys
            .map { "\"\(appleScriptString($0))\"" }
            .joined(separator: ", ")
        let source = """
        set targetIDs to {\(targetIDs)}
        set matches to {}
        tell application id "com.googlecode.iterm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        set terminalID to id of aSession
                        if targetIDs contains terminalID then
                            set end of matches to {terminalID, name of aSession}
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return matches
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            return [:]
        }

        var lookups: [String: ConversationTitleLookup] = [:]
        guard result.numberOfItems > 0 else { return lookups }
        for index in 1...result.numberOfItems {
            guard
                let match = result.atIndex(index),
                let terminalID = match.atIndex(1)?.stringValue,
                let rawTitle = match.atIndex(2)?.stringValue,
                let linkedSessions = sessionsByTerminalID[terminalID]
            else { continue }
            let lookup = ConversationTitleLookup(title: cleanConversationTitle(rawTitle))
            for linkedSession in linkedSessions {
                lookups[linkedSession.1] = lookup
            }
        }
        return lookups
    }

    static func open(_ session: ClaudeSession) {
        if focusTerminal(session) { return }
        openWorkingDirectory(session)
    }

    @discardableResult
    static func focusTerminal(_ session: ClaudeSession) -> Bool {
        guard let sessionID = session.iTermSessionID else { return false }
        let escapedID = appleScriptString(sessionID)
        let source = """
        tell application id "com.googlecode.iterm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if id of aSession is "\(escapedID)" then
                            select aSession
                            select aTab
                            select aWindow
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil, result?.booleanValue == true else { return false }
        // Activate after the SwiftUI click finishes; otherwise the floating panel's
        // mouse event can immediately reclaim focus from iTerm2.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" })?
                .activate(options: [.activateAllWindows])
        }
        return true
    }

    static func openWorkingDirectory(_ session: ClaudeSession) {
        guard !session.cwd.isEmpty else { return }
        let url = URL(fileURLWithPath: session.cwd, isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    static func copyWorkingDirectory(_ session: ClaudeSession) {
        guard !session.cwd.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.cwd, forType: .string)
    }

    static func revealTranscript(_ session: ClaudeSession) {
        guard let transcriptPath = session.transcriptPath, !transcriptPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func cleanConversationTitle(_ rawTitle: String) -> String? {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.replacingOccurrences(
            of: #"^[^\p{L}\p{N}]+\s*"#,
            with: "",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s+\((?:node|claude)\)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let genericTitles = ["claude", "claude code", "node", "zsh", "bash"]
        guard !title.isEmpty, !genericTitles.contains(title.lowercased()) else { return nil }
        return title
    }
}
