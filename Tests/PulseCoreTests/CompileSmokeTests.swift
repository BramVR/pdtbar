@testable import PulseCore

struct CompileSmokeTests {
    let quiet = PulseRenderer.render(.quietFixture)
    let pressure = PulseRenderer.render(.pressureFixture)
}
