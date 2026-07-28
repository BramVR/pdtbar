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
        discoverIfNeeded: Bool = true,
        excluding excludedDirectory: URL? = nil
    ) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let rememberedDirectory, rememberedDirectory != excludedDirectory {
            return rememberedDirectory
        }
        guard discoverIfNeeded else { return nil }
        discoveryCount += 1
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let discoveredDirectory = projects.first { project in
            guard project != excludedDirectory else { return false }
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
        if let discoveredDirectory {
            rememberedDirectory = discoveredDirectory
        }
        return discoveredDirectory
    }

    func invalidate(_ expectedDirectory: URL) {
        lock.lock()
        defer { lock.unlock() }
        if rememberedDirectory == expectedDirectory { rememberedDirectory = nil }
    }

    func rememberIfEmpty(_ directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        if rememberedDirectory == nil { rememberedDirectory = directory }
    }

    var discoveryCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return discoveryCount
    }
}
