import Darwin
import Foundation

/// A helper a stub script started inside the run's process group, read from a file holding
/// `"<helper pid> <group id>"`. The script writes `$! $$`, and `$$` is the root, whose pid is
/// the group id.
struct StrayHelper {
    let pid: pid_t
    let group: pid_t

    init(contentsOf file: URL) throws {
        let fields = try String(contentsOf: file, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pid_t($0) }
        guard fields.count == 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pid = fields[0]
        group = fields[1]
    }

    /// Cleanup for a failed expectation. The pid is signalled only while it is still alive in
    /// the run's group, so a reused pid that belongs to an unrelated process is left alone.
    func killIfStillInGroup() {
        if getpgid(pid) == group {
            kill(pid, SIGKILL)
        }
    }
}

func eventuallyProcessExits(_ pid: pid_t, within timeout: TimeInterval = 2.0) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if kill(pid, 0) != 0, errno == ESRCH {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    return false
}
