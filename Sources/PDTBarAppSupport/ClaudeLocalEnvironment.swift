public enum ClaudeLocalEnvironment {
    public static func removingScriptedHandoffHook(_ environment: [String: String]) -> [String: String] {
        guard environment.keys.contains(where: { $0.hasPrefix("PDTBAR_CLAUDE_HANDOFF_") }) else {
            return environment
        }
        var sanitized = environment
        sanitized.removeValue(forKey: "PDTBAR_CLAUDE_BIN")
        return sanitized
    }
}
