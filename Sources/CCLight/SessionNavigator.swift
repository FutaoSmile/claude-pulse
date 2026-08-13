import AppKit
import Foundation

@MainActor
enum SessionNavigator {
    static func open(_ session: ClaudeSession) {
        if focusTerminal(session) { return }
        openWorkingDirectory(session)
    }

    @discardableResult
    static func focusTerminal(_ session: ClaudeSession) -> Bool {
        guard let sessionID = session.iTermSessionID else { return false }
        let escapedID = sessionID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
}
