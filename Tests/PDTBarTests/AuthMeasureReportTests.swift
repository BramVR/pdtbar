import Foundation
import Testing
import PDTBarSmokeProof

@Suite("Auth measure report")
struct AuthMeasureReportTests {
    @Test("A first sign-in that connects costs two clicks and nothing else")
    func firstSignIn() {
        let scenario = scored([
            AuthMeasureStep(action: .launch, screens: [notConnected]),
            AuthMeasureStep(action: .signIn, clicks: 2, causeOwed: true, approvedSignIn: true, screens: [connected]),
        ], goalReached: true)

        #expect(scenario.measures == AuthMeasures(clicks: 2, silentSignOuts: 0, deadEnds: 0, osPrompts: 0, unnamedStates: 0))
        #expect(scenario.findings.isEmpty)
    }

    @Test("Check again that drops an approved sign-in without a reason is a silent sign-out (#301)")
    func checkAgainSignsOut() {
        let scenario = scored([
            AuthMeasureStep(action: .launch, setup: true, screens: [notConnected]),
            AuthMeasureStep(action: .signIn, setup: true, causeOwed: true, approvedSignIn: true, screens: [keychainUnavailable]),
            AuthMeasureStep(action: .checkAgain, causeOwed: true, screens: [notConnected]),
        ], goalReached: false)

        #expect(scenario.measures == AuthMeasures(
            clicks: AuthMeasures.unreachedClicks, silentSignOuts: 1, deadEnds: 1, osPrompts: 0, unnamedStates: 1
        ))
        #expect(scenario.measures.penalty == 10 + 10 + 5 + 3)
    }

    @Test("A sign-in that ends back on the silent not-connected menu is a silent sign-out")
    func approvedSignInLost() {
        let scenario = scored([
            AuthMeasureStep(action: .launch, screens: [notConnected]),
            AuthMeasureStep(action: .signIn, clicks: 2, causeOwed: true, approvedSignIn: true, screens: [notConnected]),
        ], goalReached: false)

        #expect(scenario.measures.silentSignOuts == 1)
    }

    @Test("A PDT rejection, a Disconnect, a named failure, or a repeat of the same menu is not a silent sign-out")
    func explainedSignOuts() {
        let failed = AuthMeasureScreen.Row(id: "pdtConnection.signInFailed", role: "setupFailure", title: "Sign-in failed", enabled: false)
        var named = notConnected
        named.rows.insert(failed, at: 1)
        let endings: [[AuthMeasureStep]] = [
            [AuthMeasureStep(action: .checkAgain, causeOwed: true, pdtRejections: 1, screens: [notConnected])],
            [AuthMeasureStep(action: .disconnect, screens: [notConnected])],
            [AuthMeasureStep(action: .checkAgain, causeOwed: true, screens: [named])],
            [
                AuthMeasureStep(action: .checkAgain, causeOwed: true, pdtRejections: 1, screens: [notConnected]),
                AuthMeasureStep(action: .checkAgain, causeOwed: true, screens: [notConnected]),
            ],
        ]
        for ending in endings {
            let setup = AuthMeasureStep(action: .signIn, setup: true, causeOwed: true, approvedSignIn: true, screens: [connected])
            #expect(scored([setup] + ending, goalReached: false).measures.silentSignOuts == 0)
        }
    }

    @Test("A resting menu with no next action is a dead end and an unnamed state, counted once per distinct menu")
    func deadEnd() {
        let stuck = AuthMeasureScreen(
            state: "keychainUnavailable(failed)", kind: .waiting, statusTitle: "Could not read the Keychain", idle: true,
            rows: [.init(id: "pdtConnection.status", role: "setupStatus", title: "Could not read the Keychain", detail: "d", enabled: false)]
        )
        let scenario = scored([
            AuthMeasureStep(action: .launch, screens: [stuck]),
            AuthMeasureStep(action: .relaunch, screens: [stuck]),
        ], goalReached: false)

        #expect(scenario.measures.deadEnds == 3)
        #expect(scenario.measures.unnamedStates == 1)
    }

    @Test("A driver error and scenario totals reach the report")
    func reportTotals() {
        let ok = scored([AuthMeasureStep(action: .signIn, clicks: 2, screens: [connected])], goalReached: true)
        let failed = AuthMeasureScenario(id: "b", steps: [], goalReached: false, osPrompts: 1, silentDetail: silentDetail, error: "boom")
        let report = AuthMeasureReport(scenarios: [ok, failed])

        #expect(report.status == "errors")
        #expect(report.errorCount == 1)
        #expect(report.totals == AuthMeasures(clicks: 12, silentSignOuts: 0, deadEnds: 1, osPrompts: 1, unnamedStates: 0))
        #expect(report.totals.penalty == 12 + 5 + 5)
        #expect(AuthMeasureReport(scenarios: [ok]).status == "passed")
    }

    @Test("An ad-hoc build reads nothing from the data protection keychain and cannot write it")
    func adHocDataProtectionKeychain() {
        var keychain = AuthMeasureKeychain(build: .adHoc)

        #expect(keychain.copy(.dataProtection).status == AuthMeasureKeychain.itemNotFound)
        #expect(keychain.update(.dataProtection, data: Data("a".utf8)) == AuthMeasureKeychain.missingEntitlement)
        #expect(keychain.add(.dataProtection, data: Data("a".utf8)) == AuthMeasureKeychain.missingEntitlement)
        #expect(keychain.delete(.dataProtection) == AuthMeasureKeychain.missingEntitlement)
        #expect(keychain.copy(.dataProtection).data == nil)
        #expect(keychain.osPrompts == 0)
    }

    @Test("An entitled build stores one item across launches and never prompts")
    func entitledKeychain() {
        var keychain = AuthMeasureKeychain(build: .entitled)

        #expect(keychain.update(.dataProtection, data: Data("a".utf8)) == AuthMeasureKeychain.itemNotFound)
        #expect(keychain.add(.dataProtection, data: Data("a".utf8)) == AuthMeasureKeychain.success)
        #expect(keychain.add(.dataProtection, data: Data("b".utf8)) == AuthMeasureKeychain.duplicateItem)
        #expect(keychain.update(.dataProtection, data: Data("b".utf8)) == AuthMeasureKeychain.success)
        keychain.relaunch()
        #expect(keychain.copy(.dataProtection).data == Data("b".utf8))
        #expect(keychain.delete(.dataProtection) == AuthMeasureKeychain.success)
        #expect(keychain.copy(.dataProtection).status == AuthMeasureKeychain.itemNotFound)
        #expect(keychain.osPrompts == 0)
    }

    @Test("A login keychain item prompts once for each rebuild of an ad-hoc build")
    func adHocLoginKeychainPrompts() {
        var keychain = AuthMeasureKeychain(build: .adHoc)

        #expect(keychain.add(.login, data: Data("a".utf8)) == AuthMeasureKeychain.success)
        #expect(keychain.copy(.login).data == Data("a".utf8))
        #expect(keychain.osPrompts == 0)
        keychain.relaunch()
        #expect(keychain.copy(.login).data == Data("a".utf8))
        #expect(keychain.update(.login, data: Data("b".utf8)) == AuthMeasureKeychain.success)
        #expect(keychain.osPrompts == 1)
        keychain.relaunch()
        #expect(keychain.copy(.login).data == Data("b".utf8))
        #expect(keychain.osPrompts == 2)
    }
}

private let silentDetail = "PDTBar reads your PDT portfolio read-only"

private func scored(_ steps: [AuthMeasureStep], goalReached: Bool) -> AuthMeasureScenario {
    AuthMeasureScenario(id: "a", steps: steps, goalReached: goalReached, osPrompts: 0, silentDetail: silentDetail)
}

private let notConnected = AuthMeasureScreen(
    state: "notConnected", kind: .waiting, statusTitle: "Not connected", idle: true,
    rows: [
        .init(id: "pdtConnection.status", role: "setupStatus", title: "Not connected", detail: silentDetail, enabled: false),
        .init(id: "pdtConnection.signIn", role: "connectionSignIn", title: "Sign in with PDT", enabled: true),
    ]
)

private let keychainUnavailable = AuthMeasureScreen(
    state: "keychainUnavailable(missingEntitlement)", kind: .waiting, statusTitle: "Keychain unavailable", idle: true,
    rows: [
        .init(id: "pdtConnection.status", role: "setupStatus", title: "Keychain unavailable", detail: "This build can't", enabled: false),
        .init(id: "pdtConnection.check", role: "connectionCheck", title: "Check again", enabled: true),
    ]
)

private let connected = AuthMeasureScreen(
    state: "connected(current)", kind: .connectedCurrent, statusTitle: "Quiet", idle: true,
    rows: [.init(id: "actions.refreshNow", role: "fetchRetry", title: "Refresh now", enabled: true)]
)
