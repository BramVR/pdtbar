import Foundation

final class ClaudeProjectDirectoryCache: @unchecked Sendable {
    private let projectsDirectory: URL
    private let lock = NSLock()
    private var rememberedDirectory: URL?
    private var discoveryCount = 0

    init(projectsDirectory: URL) {
        self.projectsDirectory = projectsDirectory
    }

    func directory(
        containing sessionID: String,
        discoverIfNeeded: Bool = true
    ) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let rememberedDirectory {
            return rememberedDirectory
        }
        guard discoverIfNeeded else { return nil }
        discoveryCount += 1
        let discoveredDirectories = projectDirectories(containing: sessionID)
        if let discoveredDirectory = discoveredDirectories.first {
            rememberedDirectory = discoveredDirectory
        }
        return discoveredDirectories.first
    }

    func rediscoverDirectories(containing sessionID: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        discoveryCount += 1
        return projectDirectories(containing: sessionID)
    }

    func remember(_ directory: URL) {
        lock.lock()
        rememberedDirectory = directory
        lock.unlock()
    }

    private func projectDirectories(containing sessionID: String) -> [URL] {
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return projects.filter { project in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return false }
            var isSessionDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: project.appending(path: sessionID).path,
                isDirectory: &isSessionDirectory
            ) && isSessionDirectory.boolValue
        }
    }

    var discoveryCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return discoveryCount
    }
}
