import Foundation

/// One menu `pdtbar-smoke auth-measure` saw, reduced to its connection and fetch rows.
public struct AuthMeasureScreen: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Checking, signing in, disconnecting, or fetching: the menu will change by itself.
        case transient
        /// Connected with a current pulse: the goal of every scenario.
        case connectedCurrent
        /// Any state that waits for the user.
        case waiting
    }

    public struct Row: Codable, Equatable, Sendable {
        public var id: String
        public var role: String
        public var title: String
        public var detail: String?
        /// The app wires a click action to this row's role.
        public var enabled: Bool

        public init(id: String, role: String, title: String, detail: String? = nil, enabled: Bool) {
            self.id = id
            self.role = role
            self.title = title
            self.detail = detail
            self.enabled = enabled
        }
    }

    public var state: String
    public var kind: Kind
    public var statusTitle: String
    /// Nothing was running when this menu was shown.
    public var idle: Bool
    public var rows: [Row]

    public init(state: String, kind: Kind, statusTitle: String, idle: Bool, rows: [Row]) {
        self.state = state
        self.kind = kind
        self.statusTitle = statusTitle
        self.idle = idle
        self.rows = rows
    }

    /// Row roles that move the user toward a connection.
    public static let nextActionRoles: Set<String> = [
        "connectionSignIn", "connectionToken", "connectionCheck", "connectionDisconnect", "fetchRetry",
    ]

    public var offersSignIn: Bool { rows.contains { $0.role == "connectionSignIn" } }
    public var offersNextAction: Bool { rows.contains { $0.enabled && Self.nextActionRoles.contains($0.role) } }
    /// The first connection or fetch status row: what the menu says is going on.
    public var statusRow: Row? { rows.first { $0.role == "setupStatus" || $0.role == "fetchStatus" } }
    var namesAFailure: Bool { rows.contains { $0.role == "setupFailure" } }
}

/// One launch, relaunch, or click, with every menu it produced.
public struct AuthMeasureStep: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case launch, relaunch, signIn, checkAgain, fetchRetry, disconnect
    }

    public var action: Action
    /// A setup step puts the scenario in its starting state. It is shown, not scored.
    public var setup: Bool
    /// Clicks this step cost the simulated user. Scripted clicks and launches cost 0.
    public var clicks: Int
    /// After this step the user still expects to be connected: a credential was
    /// stored or a sign-in was approved, and they have not clicked Disconnect since.
    public var causeOwed: Bool
    /// The user approved a PDT sign-in in the browser during this step.
    public var approvedSignIn: Bool
    /// `401`, `invalid_grant`, and `INSUFFICIENT_SCOPE` replies PDT gave during this step.
    public var pdtRejections: Int
    public var screens: [AuthMeasureScreen]

    public init(
        action: Action, setup: Bool = false, clicks: Int = 0, causeOwed: Bool = false,
        approvedSignIn: Bool = false, pdtRejections: Int = 0, screens: [AuthMeasureScreen]
    ) {
        self.action = action
        self.setup = setup
        self.clicks = clicks
        self.causeOwed = causeOwed
        self.approvedSignIn = approvedSignIn
        self.pdtRejections = pdtRejections
        self.screens = screens
    }
}

public struct AuthMeasures: Codable, Equatable, Sendable {
    public static let unreachedClicks = 10

    public var clicks: Int
    public var silentSignOuts: Int
    public var deadEnds: Int
    public var osPrompts: Int
    public var unnamedStates: Int
    public var penalty: Int

    public init(clicks: Int, silentSignOuts: Int, deadEnds: Int, osPrompts: Int, unnamedStates: Int) {
        self.clicks = clicks
        self.silentSignOuts = silentSignOuts
        self.deadEnds = deadEnds
        self.osPrompts = osPrompts
        self.unnamedStates = unnamedStates
        penalty = clicks + 10 * silentSignOuts + 5 * deadEnds + 5 * osPrompts + 3 * unnamedStates
    }

    public static func total(_ all: [AuthMeasures]) -> AuthMeasures {
        AuthMeasures(
            clicks: all.map(\.clicks).reduce(0, +),
            silentSignOuts: all.map(\.silentSignOuts).reduce(0, +),
            deadEnds: all.map(\.deadEnds).reduce(0, +),
            osPrompts: all.map(\.osPrompts).reduce(0, +),
            unnamedStates: all.map(\.unnamedStates).reduce(0, +)
        )
    }
}

public struct AuthMeasureScenario: Codable, Equatable, Sendable {
    public var id: String
    public var goalReached: Bool
    public var measures: AuthMeasures
    /// One line per counted silent sign-out, dead end, OS prompt, and unnamed state.
    public var findings: [String]
    /// Set when the driver threw. The scenario is then scored as unreached.
    public var error: String?
    public var steps: [AuthMeasureStep]

    /// `silentDetail` is the status detail of a fresh, never connected menu: copy that names no reason.
    public init(
        id: String, steps: [AuthMeasureStep], goalReached: Bool, osPrompts: Int, silentDetail: String, error: String? = nil
    ) {
        self.id = id
        self.goalReached = goalReached
        self.error = error
        self.steps = steps

        var findings: [String] = []
        var silentSignOuts = 0
        var deadEnds = 0
        var unnamed: Set<String> = []
        var previous: AuthMeasureScreen?
        for step in steps {
            defer { previous = step.screens.last ?? previous }
            guard !step.setup else {
                continue
            }
            func namesNoReason(_ screen: AuthMeasureScreen) -> Bool {
                screen.statusRow?.detail == silentDetail && !screen.namesAFailure
            }
            if let settled = step.screens.last,
               step.causeOwed, step.action != .disconnect, step.pdtRejections == 0,
               settled.offersSignIn, namesNoReason(settled),
               step.approvedSignIn || previous?.offersSignIn != true
            {
                silentSignOuts += 1
                findings.append("silent sign-out after \(step.action.rawValue): \(settled.state) names no reason")
            }
            for screen in step.screens where screen.kind == .waiting {
                if screen.idle, !screen.offersNextAction {
                    deadEnds += 1
                    findings.append("dead end: \(screen.state) offers no next action")
                }
                let detail = screen.statusRow?.detail ?? ""
                let reason: String? = if !screen.offersNextAction {
                    "offers no next action"
                } else if detail.isEmpty || (step.causeOwed && namesNoReason(screen)) {
                    "names no cause"
                } else {
                    nil
                }
                if let reason, unnamed.insert([screen.state, screen.statusTitle, detail].joined(separator: "\u{1F}")).inserted {
                    findings.append("unnamed state: \(screen.state) \"\(screen.statusTitle)\" \(reason)")
                }
            }
        }
        if !goalReached {
            deadEnds += 1
            findings.append("goal unreached")
        }
        if osPrompts > 0 {
            findings.append("\(osPrompts) keychain call(s) would show an OS prompt")
        }
        measures = AuthMeasures(
            clicks: goalReached ? steps.filter { !$0.setup }.map(\.clicks).reduce(0, +) : AuthMeasures.unreachedClicks,
            silentSignOuts: silentSignOuts,
            deadEnds: deadEnds,
            osPrompts: osPrompts,
            unnamedStates: unnamed.count
        )
        self.findings = findings
    }
}

public struct AuthMeasureReport: Codable, Equatable, Sendable {
    public var name = "auth-measure"
    /// `passed` when no scenario's driver threw, else `errors`. The score is in `totals`.
    public var status: String
    public var scenarioCount: Int
    public var errorCount: Int
    public var totals: AuthMeasures
    public var scenarios: [AuthMeasureScenario]

    public init(scenarios: [AuthMeasureScenario]) {
        self.scenarios = scenarios
        scenarioCount = scenarios.count
        errorCount = scenarios.filter { $0.error != nil }.count
        status = errorCount == 0 ? "passed" : "errors"
        totals = AuthMeasures.total(scenarios.map(\.measures))
    }
}

/// The one PDT keychain item as two kinds of build see it, with no call to the real Keychain.
///
/// The data protection keychain answers are measured on an ad-hoc signed binary:
/// a read finds nothing and every write is `errSecMissingEntitlement`. The login
/// keychain answers are inferred from its ACL rules and were not probed: an item
/// trusts the code that wrote it, an ad-hoc build is a new identity after every
/// rebuild, and each rebuild's first use of an existing item shows one OS prompt.
public struct AuthMeasureKeychain: Equatable, Sendable {
    public enum Build: Sendable {
        /// Signed with the keychain access group entitlement and a stable identity.
        case entitled
        /// `make start`: ad-hoc signed, no entitlement, rebuilt before every launch.
        case adHoc
    }

    public enum Domain: Sendable {
        case dataProtection, login
    }

    public static let success: Int32 = 0
    public static let itemNotFound: Int32 = -25300
    public static let duplicateItem: Int32 = -25299
    public static let missingEntitlement: Int32 = -34018

    private struct Item: Equatable, Sendable {
        var data: Data
        var trustedBuilds: Set<Int>
    }

    public let build: Build
    public private(set) var osPrompts = 0
    private var items: [Domain: Item] = [:]
    private var buildNumber = 0

    public init(build: Build) {
        self.build = build
    }

    public mutating func relaunch() {
        if build == .adHoc {
            buildNumber += 1
        }
    }

    public mutating func copy(_ domain: Domain) -> (status: Int32, data: Data?) {
        guard touch(domain) else {
            return (Self.itemNotFound, nil)
        }
        return (Self.success, items[domain]?.data)
    }

    public mutating func add(_ domain: Domain, data: Data) -> Int32 {
        guard writable(domain) else {
            return Self.missingEntitlement
        }
        guard items[domain] == nil else {
            return Self.duplicateItem
        }
        items[domain] = Item(data: data, trustedBuilds: [buildNumber])
        return Self.success
    }

    public mutating func update(_ domain: Domain, data: Data) -> Int32 {
        guard writable(domain) else {
            return Self.missingEntitlement
        }
        guard touch(domain) else {
            return Self.itemNotFound
        }
        items[domain]?.data = data
        return Self.success
    }

    public mutating func delete(_ domain: Domain) -> Int32 {
        guard writable(domain) else {
            return Self.missingEntitlement
        }
        guard touch(domain) else {
            return Self.itemNotFound
        }
        items[domain] = nil
        return Self.success
    }

    private func writable(_ domain: Domain) -> Bool {
        domain == .login || build == .entitled
    }

    /// True when the item exists. A login item this build did not write prompts once.
    private mutating func touch(_ domain: Domain) -> Bool {
        guard let item = items[domain] else {
            return false
        }
        if domain == .login, !item.trustedBuilds.contains(buildNumber) {
            osPrompts += 1
            items[domain]?.trustedBuilds.insert(buildNumber)
        }
        return true
    }
}
