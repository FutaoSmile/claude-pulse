import Foundation

enum HookInstaller {
    private static let eventNames = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "PostToolBatch",
        "PermissionRequest",
        "Notification",
        "Stop",
        "StopFailure",
        "SessionEnd"
    ]

    private static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    private static var settingsURL: URL {
        claudeDirectory.appendingPathComponent("settings.json")
    }

    private static var helperURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent("cc-light")
    }

    @discardableResult
    static func repairIfNeeded() throws -> Bool {
        let repairedHelper = try ensureHelperExists()
        let manager = FileManager.default
        try manager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        var settings: [String: Any]
        if manager.fileExists(atPath: settingsURL.path) {
            let data = try Data(contentsOf: settingsURL)
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RepairError.invalidSettings
            }
            settings = decoded
        } else {
            settings = [:]
        }

        var hooks: [String: Any]
        if let existingHooks = settings["hooks"] {
            guard let decodedHooks = existingHooks as? [String: Any] else {
                throw RepairError.invalidHooks
            }
            hooks = decodedHooks
        } else {
            hooks = [:]
        }

        let command = "\"\(helperURL.path)\" emit"
        var repairedSettings = false
        for eventName in eventNames {
            var groups: [[String: Any]]
            if let existingGroups = hooks[eventName] {
                guard let decodedGroups = existingGroups as? [[String: Any]] else {
                    throw RepairError.invalidHookEvent(eventName)
                }
                groups = decodedGroups
            } else {
                groups = []
            }

            let alreadyInstalled = groups.contains { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return false }
                return entries.contains { entry in
                    entry["type"] as? String == "command"
                        && entry["command"] as? String == command
                }
            }
            guard !alreadyInstalled else { continue }

            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 5
                ]]
            ])
            hooks[eventName] = groups
            repairedSettings = true
        }

        guard repairedSettings else { return repairedHelper }
        settings["hooks"] = hooks
        var encoded = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted])
        encoded.append(0x0A)
        try encoded.write(to: settingsURL, options: [.atomic])
        return true
    }

    private static func ensureHelperExists() throws -> Bool {
        let manager = FileManager.default
        let helperDirectory = helperURL.deletingLastPathComponent()
        try manager.createDirectory(at: helperDirectory, withIntermediateDirectories: true)

        if manager.fileExists(atPath: helperURL.path) {
            if !manager.isExecutableFile(atPath: helperURL.path) {
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
                return true
            }
            return false
        }

        guard let executableURL = Bundle.main.executableURL else {
            throw RepairError.missingApplicationExecutable
        }
        try manager.copyItem(at: executableURL, to: helperURL)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        return true
    }

    private enum RepairError: LocalizedError {
        case invalidSettings
        case invalidHooks
        case invalidHookEvent(String)
        case missingApplicationExecutable

        var errorDescription: String? {
            switch self {
            case .invalidSettings:
                "Claude Code 设置文件不是有效的 JSON 对象"
            case .invalidHooks:
                "Claude Code 设置中的 hooks 字段格式不正确"
            case let .invalidHookEvent(eventName):
                "Claude Code 设置中的 \(eventName) Hook 格式不正确"
            case .missingApplicationExecutable:
                "找不到 Claude Pulse 应用程序文件"
            }
        }
    }
}
