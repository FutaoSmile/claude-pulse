import AppKit
import Foundation

@MainActor
enum SessionNavigator {
    static func conversationTitle(for session: ClaudeSession) -> String? {
        guard let sessionID = session.iTermSessionID else { return nil }
        let escapedID = appleScriptString(sessionID)
        let source = """
        tell application id "com.googlecode.iterm2"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if id of aSession is "\(escapedID)" then return name of aSession
                    end repeat
                end repeat
            end repeat
        end tell
        return missing value
        """
        var error: NSDictionary?
        guard
            let value = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue,
            error == nil
        else { return nil }
        return cleanConversationTitle(value)
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
