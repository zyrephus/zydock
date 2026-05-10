import Foundation

/// Installs Claude Code hooks pointing at the local zydockd daemon.
/// Mirrors hooks/install.sh — kept in sync with that script's hook block.
enum HookInstaller {
    private static let daemonURL = "http://localhost:6767/events"
    private static let settingsPath = ("~/.claude/settings.json" as NSString).expandingTildeInPath

    static func installIfNeeded() {
        let url = URL(fileURLWithPath: settingsPath)

        guard FileManager.default.fileExists(atPath: settingsPath) else {
            NSLog("zydock: ~/.claude/settings.json not found, skipping hook install")
            return
        }

        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("zydock: failed to parse ~/.claude/settings.json")
            return
        }

        if hooksAlreadyInstalled(in: root) { return }

        let merged = merge(hooks: hookBlock(), into: root)

        let backup = url.appendingPathExtension("bak")
        try? data.write(to: backup)

        do {
            let out = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url)
            NSLog("zydock: installed Claude Code hooks (backup at \(backup.path))")
        } catch {
            NSLog("zydock: failed to write settings.json: \(error)")
        }
    }

    // MARK: - Hook block

    private static let eventNames = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "Stop",
    ]

    private static func httpHook() -> [String: Any] {
        ["type": "http", "url": daemonURL, "timeout": 5]
    }

    private static func hookBlock() -> [String: Any] {
        var hooks: [String: Any] = [:]
        for name in eventNames {
            hooks[name] = [["hooks": [httpHook()]]]
        }
        hooks["Notification"] = [[
            "matcher": "permission_prompt",
            "hooks": [httpHook()],
        ]]
        return hooks
    }

    // MARK: - Merge

    private static func merge(hooks: [String: Any], into root: [String: Any]) -> [String: Any] {
        var out = root
        out["hooks"] = hooks
        return out
    }

    private static func hooksAlreadyInstalled(in root: [String: Any]) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        for name in eventNames + ["Notification"] {
            guard let entries = hooks[name] as? [[String: Any]] else { return false }
            let hasOurURL = entries.contains { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
                return inner.contains { ($0["url"] as? String) == daemonURL }
            }
            if !hasOurURL { return false }
        }
        return true
    }
}
