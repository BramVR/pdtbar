import PDTBarCore

extension Sequence {
    /// `allSatisfy` is true for an empty sequence, so `#expect(rows.nonEmptyAllSatisfy { … })`
    /// passes when the rows it checks are gone (#307). This one also needs an element.
    /// `pdtbar-checks` rejects a bare `allSatisfy` inside `#expect`.
    func nonEmptyAllSatisfy(_ predicate: (Element) throws -> Bool) rethrows -> Bool {
        var sawElement = false
        for element in self {
            guard try predicate(element) else {
                return false
            }
            sawElement = true
        }
        return sawElement
    }
}

extension PortfolioValueText {
    /// The text with portfolio values shown, as the menu renders it by default.
    var shown: String {
        rendered(settings: PortfolioValueDisplaySettings())
    }
}
