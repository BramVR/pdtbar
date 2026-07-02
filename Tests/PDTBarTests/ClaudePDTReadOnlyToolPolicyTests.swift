import Foundation
import Testing
import PDTBarCore

@Suite("Claude PDT read-only tool policy")
struct ClaudePDTReadOnlyToolPolicyTests {
    @Test("Shared denylist pins every denied built-in Claude tool")
    func sharedDenylistPinsDeniedBuiltInTools() {
        // Safety pin: this is the single source of truth for the read-only
        // sync deny policy. Removing an entry here must be a deliberate,
        // reviewed decision, so the full list is asserted exactly.
        #expect(ClaudePDTReadOnlyToolPolicy.disallowedBuiltInTools == [
            "AskUserQuestion",
            "Bash",
            "CronCreate",
            "CronDelete",
            "CronList",
            "DesignSync",
            "Edit",
            "EnterPlanMode",
            "EnterWorktree",
            "ExitPlanMode",
            "ExitWorktree",
            "ListMcpResourcesTool",
            "Monitor",
            "NotebookEdit",
            "PushNotification",
            "Read",
            "ReadMcpResourceTool",
            "RemoteTrigger",
            "ScheduleWakeup",
            "Skill",
            "Task",
            "TaskCreate",
            "TaskGet",
            "TaskList",
            "TaskOutput",
            "TaskStop",
            "TaskUpdate",
            "WebFetch",
            "WebSearch",
            "Workflow",
            "Write",
        ])
    }

    @Test("Shared denylist pins every PDT mutator selector")
    func sharedDenylistPinsPDTMutatorSelectors() {
        #expect(ClaudePDTReadOnlyToolPolicy.disallowedPDTMutationSelectors == [
            "mcp__*__pdt-add-*",
            "mcp__*__pdt-create-*",
            "mcp__*__pdt-delete-*",
            "mcp__*__pdt-patch-*",
            "mcp__*__pdt-post-*",
            "mcp__*__pdt-put-*",
            "mcp__*__pdt-remove-*",
            "mcp__*__pdt-set-*",
            "mcp__*__pdt-update-*",
        ])
    }

    @Test("Full denylist is built-ins plus mutator selectors without duplicates")
    func fullDenylistCombinesBuiltInsAndMutatorSelectors() {
        let full = ClaudePDTReadOnlyToolPolicy.disallowedTools

        #expect(full == ClaudePDTReadOnlyToolPolicy.disallowedBuiltInTools
            + ClaudePDTReadOnlyToolPolicy.disallowedPDTMutationSelectors)
        #expect(Set(full).count == full.count)
        // The smoke derives its ToolSearch-phase denylist by dropping
        // `mcp__`-prefixed selectors, so built-ins must never carry that
        // prefix and every mutator selector must.
        #expect(!ClaudePDTReadOnlyToolPolicy.disallowedBuiltInTools.contains { $0.hasPrefix("mcp__") })
        #expect(ClaudePDTReadOnlyToolPolicy.disallowedPDTMutationSelectors.allSatisfy {
            $0.hasPrefix("mcp__*__pdt-") && $0.hasSuffix("-*")
        })
    }

    @Test("Denylist keeps critical write and execution tools denied")
    func denylistKeepsCriticalWriteAndExecutionToolsDenied() {
        let denied = Set(ClaudePDTReadOnlyToolPolicy.disallowedTools)
        let critical: Set<String> = [
            "Bash",
            "Edit",
            "Write",
            "NotebookEdit",
            "Read",
            "WebFetch",
            "WebSearch",
            "Task",
            "Skill",
            "ListMcpResourcesTool",
            "ReadMcpResourceTool",
        ]

        #expect(critical.isSubset(of: denied))
        // ToolSearch stays allowed so Claude can hydrate deferred MCP tools.
        #expect(!denied.contains("ToolSearch"))
    }
}
