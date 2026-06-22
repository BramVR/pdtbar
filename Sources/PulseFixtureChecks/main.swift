import Foundation
import PulseCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let quiet = PulseRenderer.render(.quietFixture)
expect(quiet.status.title == "Pulse", "quiet status title")
expect(quiet.status.badge == nil, "quiet status badge")
expect(quiet.card.title == "All quiet", "quiet card title")
expect(quiet.card.rows.isEmpty, "quiet card rows")

let pressure = PulseRenderer.render(.pressureFixture)
expect(pressure.status.title == "Pulse", "pressure status title")
expect(pressure.status.badge == "• 1", "pressure status badge")
expect(pressure.card.title == "1 pressure item", "pressure card title")
expect(pressure.card.rows.count == 1, "pressure card row count")
expect(pressure.card.rows.first?.title == "NVDA concentration climbing", "pressure row title")
expect(pressure.card.rows.first?.detail == "22% of portfolio; up from 18%", "pressure row detail")
expect(pressure.card.rows.first?.facet == .allocation, "pressure row facet")
