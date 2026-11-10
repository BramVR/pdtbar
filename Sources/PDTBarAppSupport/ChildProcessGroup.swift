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
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)
        posix_spawnattr_setpgroup(&attributes, 0)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        switch launch.stdio {
        case let .terminal(descriptor):
            for target: Int32 in 0...2 {
                posix_spawn_file_actions_adddup2(&actions, descriptor, target)
            }
        case let .pipes(stdout, stderr):
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, 1)
            posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, 2)
        }
        if let workingDirectory = launch.workingDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path)
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
        guard result == 0 else {
            throw ChildSpawnError(code: result)
        }
        return ChildProcessGroup(pid: pid)
    }

    /// Polls without reaping, so the group ID stays reserved.
    var isRunning: Bool {
        Self.naturalExitStatus(of: pid) == nil
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
        let naturalStatus = naturalExitStatus(of: pid)
        kill(-pid, SIGTERM)
        if naturalStatus == nil {
            let deadline = Date().addingTimeInterval(terminationGrace)
            while naturalExitStatus(of: pid) == nil, Date() < deadline {
                usleep(50000)
            }
        }
        // Unconditional: helpers that ignore SIGTERM or outlived the root are still in the group.
        kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        return naturalStatus
    }

    /// The root's exit code (or terminating signal, as Foundation reports it) once it has exited.
    private static func naturalExitStatus(of pid: pid_t) -> Int32? {
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == -1 {
            // ECHILD: something else reaped the root, so it is not running.
            guard errno == EINTR else { return -1 }
        }
        guard info.si_pid == pid else { return nil }
        return info.si_status
    }
}
