#if canImport(Darwin)
import Darwin
#endif
import Foundation

struct ChildLaunch {
    enum Stdio {
        /// The PTY secondary goes on 0, 1 and 2. The caller keeps owning the descriptor.
        case terminal(Int32)
        /// stdin reads /dev/null. The pipes' write ends go on 1 and 2 and are closed in this process after spawn.
        case pipes(stdout: Pipe, stderr: Pipe)
    }

    var executable: String
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: URL?
    var stdio: Stdio
}

struct ChildSpawnError: LocalizedError, Equatable {
    var code: Int32

    var message: String {
        String(cString: strerror(code))
    }

    var errorDescription: String? {
        message
    }
}

/// Sole owner of a spawned child and of every process in its process group.
///
/// The child is spawned as the leader of a new group, so the group ID equals `pid`. The root
/// is never reaped while this value exists, so that ID stays reserved and a group signal can
/// reach no one else, even after helpers are reparented to launchd. Ending the value by `end()`
/// or by going out of scope signals the whole group and reaps the root, on every path.
struct ChildProcessGroup: ~Copyable {
    private static let terminationGrace: TimeInterval = 2

    let pid: pid_t

    private init(pid: pid_t) {
        self.pid = pid
    }

    static func spawn(_ launch: ChildLaunch) throws(ChildSpawnError) -> ChildProcessGroup {
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        try check(posix_spawnattr_setsigdefault(&attributes, &defaultSignals))
        try check(posix_spawnattr_setsigmask(&attributes, &emptyMask))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        try check(posix_spawnattr_setflags(&attributes, Int16(flags)))

        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        switch launch.stdio {
        case let .terminal(descriptor):
            for target: Int32 in 0...2 {
                try check(posix_spawn_file_actions_adddup2(&actions, descriptor, target))
            }
        case let .pipes(stdout, stderr):
            try check(posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0))
            try check(posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, 1))
            try check(posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, 2))
        }
        if let workingDirectory = launch.workingDirectory {
            try check(posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path))
        }

        let argv = ([launch.executable] + launch.arguments).map { strdup($0) } + [nil]
        let envp = launch.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, launch.executable, &actions, &attributes, argv, envp)
        if case let .pipes(stdout, stderr) = launch.stdio {
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
        }
        try check(result)
        return ChildProcessGroup(pid: pid)
    }

    /// Polls without reaping, so the group ID stays reserved.
    var isRunning: Bool {
        if case .unreaped(_, exitStatus: nil) = RootObservation.observe(pid) {
            return true
        }
        return false
    }

    /// Ends the group and returns the root's exit status if the root had exited on its own,
    /// or nil if this call's signals ended it.
    consuming func end() -> Int32? {
        let status = Self.terminate(pid: pid)
        discard self
        return status
    }

    deinit {
        _ = Self.terminate(pid: pid)
    }

    private static func terminate(pid: pid_t) -> Int32? {
        guard case let .unreaped(group, naturalStatus) = RootObservation.observe(pid) else {
            return nil
        }
        group.signal(SIGTERM)
        var latest = RootObservation.observe(pid)
        let deadline = Date().addingTimeInterval(terminationGrace)
        while case .unreaped(_, exitStatus: nil) = latest, Date() < deadline {
            usleep(50000)
            latest = RootObservation.observe(pid)
        }
        guard case let .unreaped(group, _) = latest else {
            return nil
        }
        // Unconditional: helpers that ignore SIGTERM or outlived the root are still in the group.
        group.signal(SIGKILL)
        group.reapLeader()
        return naturalStatus
    }

    private static func check(_ code: Int32) throws(ChildSpawnError) {
        guard code == 0 else {
            throw ChildSpawnError(code: code)
        }
    }
}

/// What a non-reaping wait says about the root.
private enum RootObservation {
    /// The root is still this process's unreaped child, running or a zombie, so its group ID is
    /// reserved. `exitStatus` is the exit code (or terminating signal, as Foundation reports it)
    /// once it has exited.
    case unreaped(ReservedGroup, exitStatus: Int32?)
    /// The root is no longer this process's child (ECHILD: something else reaped it). Its group
    /// ID may already belong to an unrelated group, so nothing may signal it.
    case lost

    static func observe(_ pid: pid_t) -> RootObservation {
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == -1 {
            guard errno == EINTR else { return .lost }
        }
        return .unreaped(ReservedGroup(leader: pid), exitStatus: info.si_pid == pid ? info.si_status : nil)
    }
}

/// The only way to signal a process group: a value that exists only inside an `.unreaped` observation.
private struct ReservedGroup {
    fileprivate let leader: pid_t

    func signal(_ signal: Int32) {
        kill(-leader, signal)
    }

    func reapLeader() {
        var status: Int32 = 0
        while waitpid(leader, &status, 0) == -1, errno == EINTR {}
    }
}
