import Foundation

public enum ClaudeToolResultParserError: Error, CustomStringConvertible, Equatable, Sendable {
    case malformedStreamJSON(line: Int)
    case missingToolCall(String)
    case missingToolResult(String)
    case unreadableSavedFile(String)

    public var description: String {
        switch self {
        case .malformedStreamJSON(let line):
            "Claude stream-json output contains malformed JSON on line \(line)"
        case .missingToolCall(let tool):
            "Claude did not call \(tool)"
        case .missingToolResult(let tool):
            "Claude did not return structured data for \(tool)"
        case .unreadableSavedFile(let path):
            "Claude saved a tool result file that could not be read: \(path)"
        }
    }
}

public struct ClaudeToolResultParser: Sendable {
    public init() {}

    public func resultData(
        for toolName: String,
        readToolName: String,
        output: String,
        currentSessionResultFiles: Set<URL>
    ) throws -> Data {
        let values = try streamValues(from: output)
        let matchingToolUseIDs = Set(values.flatMap {
            toolUseIDs(for: toolName, readToolName: readToolName, in: $0)
        })
        guard !matchingToolUseIDs.isEmpty else {
            throw ClaudeToolResultParserError.missingToolCall(toolName)
        }
        let matchingResults = values.flatMap { toolResults(in: $0, matching: matchingToolUseIDs) }
        for result in matchingResults {
            if let structured = result.objectValue?["structuredContent"] {
                return try encodedJSONData(structured)
            }
        }
        for result in matchingResults {
            if let file = savedToolResultFile(
                in: result.objectValue?["content"],
                currentSessionResultFiles: currentSessionResultFiles
            ) {
                return try readData(from: file)
            }
        }
        if let sessionFile = sessionToolResultFile(
            for: readToolName,
            in: currentSessionResultFiles
        ) {
            return try readData(from: sessionFile)
        }
        for result in matchingResults {
            if let data = jsonData(inToolResultContent: result.objectValue?["content"]) {
                return data
            }
        }
        throw ClaudeToolResultParserError.missingToolResult(toolName)
    }

    public func cleanupResultFiles(
        output: String,
        readToolNames: [String],
        currentSessionResultFiles: Set<URL>
    ) -> [URL] {
        let readToolFiles = currentSessionResultFiles.filter { file in
            readToolNames.contains { file.lastPathComponent.contains($0) }
        }
        let referenced = readToolFiles.filter { output.contains($0.path) }
        let sessionMatches = readToolFiles
        return Array(referenced.union(sessionMatches)).sorted { $0.path < $1.path }
    }

    private func streamValues(from output: String) throws -> [ClaudeStreamJSONValue] {
        let decoder = JSONDecoder()
        var values: [ClaudeStreamJSONValue] = []
        for (offset, line) in output.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            // The Claude CLI is an npm wrapper that can print plain-text noise
            // (update notices and similar) around stream-json lines. Skip
            // lines that do not look like JSON objects, but keep failing loud
            // when a line that claims to be JSON does not decode.
            guard trimmed.hasPrefix("{") else {
                continue
            }
            guard let data = trimmed.data(using: .utf8),
                  let value = try? decoder.decode(ClaudeStreamJSONValue.self, from: data)
            else {
                throw ClaudeToolResultParserError.malformedStreamJSON(line: offset + 1)
            }
            values.append(value)
        }
        return values
    }

    private func toolUseIDs(
        for toolName: String,
        readToolName: String,
        in value: ClaudeStreamJSONValue
    ) -> [String] {
        let current: [String]
        if value.string(for: "type") == "tool_use",
           let calledToolName = value.string(for: "name"),
           toolNameMatches(calledToolName, allowedToolName: toolName, readToolName: readToolName),
           let id = value.string(for: "id")
        {
            current = [id]
        } else {
            current = []
        }
        return current + value.children.flatMap {
            toolUseIDs(for: toolName, readToolName: readToolName, in: $0)
        }
    }

    private func toolNameMatches(
        _ calledToolName: String,
        allowedToolName: String,
        readToolName: String
    ) -> Bool {
        if calledToolName == allowedToolName {
            return true
        }
        if allowedToolName == readToolName {
            return calledToolName == readToolName || calledToolName.hasSuffix("__\(readToolName)")
        }
        guard allowedToolName.hasSuffix("*") else {
            return false
        }
        let allowedPrefix = String(allowedToolName.dropLast())
        return allowedPrefix.hasSuffix(readToolName) && calledToolName == allowedPrefix
    }

    private func toolResults(
        in value: ClaudeStreamJSONValue,
        matching ids: Set<String>
    ) -> [ClaudeStreamJSONValue] {
        let current: [ClaudeStreamJSONValue]
        if value.string(for: "type") == "tool_result",
           let toolUseID = value.string(for: "tool_use_id"),
           ids.contains(toolUseID)
        {
            current = [value]
        } else {
            current = []
        }
        return current + value.children.flatMap { toolResults(in: $0, matching: ids) }
    }

    private func savedToolResultFile(
        in content: ClaudeStreamJSONValue?,
        currentSessionResultFiles: Set<URL>
    ) -> URL? {
        guard let content else {
            return nil
        }
        if case .string(let text) = content {
            return currentSessionResultFiles.sorted { $0.path < $1.path }.first { text.contains($0.path) }
        }
        if let text = content.string(for: "text") {
            return currentSessionResultFiles.sorted { $0.path < $1.path }.first { text.contains($0.path) }
        }
        for child in content.children {
            if let file = savedToolResultFile(in: child, currentSessionResultFiles: currentSessionResultFiles) {
                return file
            }
        }
        return nil
    }

    private func sessionToolResultFile(
        for readToolName: String,
        in currentSessionResultFiles: Set<URL>
    ) -> URL? {
        currentSessionResultFiles
            .filter { $0.lastPathComponent.contains(readToolName) }
            .sorted { $0.path < $1.path }
            .first
    }

    private func jsonData(inToolResultContent content: ClaudeStreamJSONValue?) -> Data? {
        guard let content else {
            return nil
        }
        if case .string(let text) = content {
            let data = Data(text.utf8)
            return (try? JSONDecoder().decode(ClaudeStreamJSONValue.self, from: data)) == nil ? nil : data
        }
        if let text = content.string(for: "text"),
           let data = jsonData(inToolResultContent: .string(text))
        {
            return data
        }
        for child in content.children {
            if let data = jsonData(inToolResultContent: child) {
                return data
            }
        }
        return nil
    }

    private func encodedJSONData(_ value: ClaudeStreamJSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func readData(from file: URL) throws -> Data {
        do {
            return try Data(contentsOf: file)
        } catch {
            throw ClaudeToolResultParserError.unreadableSavedFile(file.path)
        }
    }
}

private enum ClaudeStreamJSONValue: Codable, Equatable, Sendable {
    case object([String: ClaudeStreamJSONValue])
    case array([ClaudeStreamJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ClaudeStreamJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ClaudeStreamJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var objectValue: [String: ClaudeStreamJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var children: [ClaudeStreamJSONValue] {
        switch self {
        case .object(let value):
            Array(value.values)
        case .array(let value):
            value
        default:
            []
        }
    }

    func string(for key: String) -> String? {
        guard case .object(let value) = self,
              case .string(let string)? = value[key]
        else {
            return nil
        }
        return string
    }
}
