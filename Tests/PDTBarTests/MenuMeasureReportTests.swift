import Foundation
import Testing
import PDTBarSmokeProof

@Suite("Menu measure report")
struct MenuMeasureReportTests {
    private let rows = [
        ("pdtbar.row.summary.performance", "Portfolio summary | Total portfolio value, EUR 64,000.00 | EUR 64,000.00"),
        ("pdtbar.row.allocation.concentration.9001.glance", "Nova Lithography concentration, 24.2%"),
        ("pdtbar.row.allocation.concentration.9001.allocation", "Nova Lithography concentration, 24.2%"),
        ("pdtbar.row.income.quote.9003.ex-dividend.2026-06-24", "Helix Pharma A/S, Ex-dividend date on 2026-06-24; EUR 78.00"),
        ("pdtbar.row.bigMovers.summary", "No big movers | No big movers - 0 price rows checked"),
        ("pdtbar.row.summary.performance", "Portfolio summary | Total portfolio value, EUR 0.00"),
        ("pdtbar.row.dataHealth", "Data health, Unknown price dates"),
        ("pdtbar.row.summary.performance", "Portfolio summary | Total portfolio value, EUR 10.00; 10 holdings"),
    ]

    private func report(includeText: Bool) -> MeasureReport {
        let salt = MeasureReport.newSalt()
        return MeasureReport(
            fixture: "concentration-pressure.json", menuWidth: 370, menuHeight: 1055, sensitiveText: includeText,
            rows: rows.map {
                MeasuredRow(
                    role: "AXMenuItem", identifier: $0.0, rawText: $0.1, salt: salt, includeText: includeText,
                    y: 0, height: 36, hasSubmenu: false, enabled: true
                )
            }
        )
    }

    @Test("Default report writes no amounts, holding names, quote ids, or dates")
    func defaultReportHasNoRawValues() throws {
        let json = String(decoding: try JSONEncoder().encode(report(includeText: false)), as: UTF8.self)

        for secret in ["64,000", "24.2", "78.00", "Nova", "Helix", "9001", "9003", "2026-06-24", "EUR"] {
            #expect(!json.contains(secret), "\(secret) leaked")
        }
    }

    @Test("Default report still carries what the layout metrics need")
    func defaultReportKeepsMetrics() {
        let measured = report(includeText: false).rows

        #expect(measured[1].text.primaryLabelDigest == measured[2].text.primaryLabelDigest)
        #expect(measured[1].text.primaryLabelDigest != measured[3].text.primaryLabelDigest)
        #expect(measured[4].text.flags == [.zeroChecked, .zeroCount])
        #expect(measured[5].text.flags == [.zeroAmount])
        #expect(measured[6].text.flags == [.unknown])
        #expect(measured[7].text.flags.isEmpty)
        #expect(measured[0].text.length == rows[0].1.count)
        #expect(measured[1].kind == "pdtbar.row.allocation.concentration.#.glance")
        #expect(measured.allSatisfy { $0.text.text == nil })
    }

    @Test("Raw text is written only on opt-in")
    func rawTextOnOptIn() {
        #expect(report(includeText: true).rows.map(\.text.text) == rows.map(\.1))
    }
}
