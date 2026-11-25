import Foundation

enum ServingQuantity {
    static func isValid(_ value: Double) -> Bool { value.isFinite && value > 0 }

    // Accept a localized decimal or a pasted decimal point, without grouping or exponents.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let decimalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        // The decimal keyboard and formatter can both use localized digits.
        let normalized = decimalText.map { character in
            if character.unicodeScalars.count == 1, character.unicodeScalars.first?.properties.numericType == .decimal,
               let digit = character.wholeNumberValue { return String(digit) }
            return String(character)
        }.joined()
        guard normalized.wholeMatch(of: #/(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)/#) != nil,
              let value = Double(normalized), isValid(value) else { return nil }
        return value
    }

    static func formatted(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.significantDigits(1...17)))
    }
}

/// The numeric size of one serving, independent of the template's optional descriptive size.
struct ServingAmount: Equatable, Sendable {
    let value: Double
    let unit: ServingAmountUnit

    init(value: Double, unit: ServingAmountUnit) {
        self.value = value
        self.unit = unit
    }

    init?(size: String?) {
        guard let size = size?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let unit = ServingAmountUnit.allCases.first(where: { size.hasSuffix($0.rawValue) }),
              let value = ServingQuantity.parse(String(size.dropLast(unit.rawValue.count)),
                                                locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        // A simple metric label on an older template or Health entry can supply the amount.
        self.init(value: value, unit: unit)
    }

    func formatted(quantity: Double = 1, locale: Locale = .current) -> String {
        let total = (value * quantity).formatted(.number.locale(locale).precision(.significantDigits(1...12)))
        return "\(total) \(unit.rawValue)"
    }
}
