import Foundation

func display(_ money: Money) -> String {
    "\(money.currency) \(decimalString(money.value, places: 2))"
}

func fingerprintToken(_ value: String) -> String {
    value.lowercased()
        .map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        .reduce(into: "") { result, character in
            if character == "-", result.last == "-" {
                return
            }
            result.append(character)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func stableIDToken(_ value: String) -> String {
    let token = fingerprintToken(value)
    return token.isEmpty ? "unknown" : token
}

func distributionLabel(_ value: String) -> String {
    value
        .split(separator: "-")
        .map { part in
            if part.uppercased() == "ETF" {
                return "ETF"
            }
            guard let first = part.first else {
                return ""
            }
            return first.uppercased() + part.dropFirst()
        }
        .joined(separator: " ")
}

func moneyFingerprint(_ money: Money?) -> String {
    guard let money else {
        return "none"
    }
    let value = Decimal(string: money.value).map { canonicalDecimalString($0, places: 2) } ?? money.value
    return "\(money.currency):\(value)"
}

func fingerprintBasisPoints(_ value: Double?) -> String {
    guard let value else {
        return "missing"
    }
    return String(basisPoints(value))
}

func basisPoints(_ value: Double) -> Int {
    return saturatedBasisPointsInt((value * 10_000).rounded())
}

func bucketBasisPoints(_ value: Double?, bucketSize: Int) -> String {
    guard let value else {
        return "missing"
    }
    guard bucketSize > 0 else {
        return String(basisPoints(value))
    }
    let points = basisPoints(value)
    return String(saturatedBasisPointsInt((Double(points) / Double(bucketSize)).rounded() * Double(bucketSize)))
}

/// Converts an already-rounded Double to Int without trapping. Malformed source
/// data (for example a garbage price ratio driving `moveSize` toward 1e15+) can
/// scale past `Int.max` here; fingerprint rendering must degrade gracefully
/// instead of crashing the app, so out-of-range values saturate at the Int
/// bounds and NaN maps to 0. Every in-range value converts exactly as before.
private func saturatedBasisPointsInt(_ value: Double) -> Int {
    guard !value.isNaN else {
        return 0
    }
    // Double(Int.max) rounds up to 2^63, the first magnitude Int(_:) traps on.
    if value >= Double(Int.max) {
        return Int.max
    }
    // Double(Int.min) is exactly -2^63, which still converts; below it traps.
    if value < Double(Int.min) {
        return Int.min
    }
    return Int(value)
}

func percent(_ value: Double) -> String {
    "\(decimalString(String(value * 100), places: 1))%"
}

func signedPercent(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : ""
    return "\(sign)\(percent(value))"
}

func decimalString(_ value: String, places: Int) -> String {
    guard let decimal = Decimal(string: value) else { return value }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = places
    formatter.maximumFractionDigits = places
    return formatter.string(from: decimal as NSDecimalNumber) ?? value
}

func rounded(_ value: Double, places: Int) -> Double {
    let multiplier = pow(10.0, Double(places))
    return (value * multiplier).rounded() / multiplier
}

func canonicalDecimalString(_ value: Decimal, places: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = places
    formatter.maximumFractionDigits = places
    return formatter.string(from: value as NSDecimalNumber) ?? (value as NSDecimalNumber).stringValue
}
