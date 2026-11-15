import Foundation

/// An amount of money, in dollars and cents.
///
/// The server sends amounts as plain JSON numbers, and its sums carry float
/// noise (`7594.980000000001`). The app does no arithmetic of its own on
/// them (the server does the forecasting), so an amount is rounded to cents
/// once, when it's decoded, and kept as a `Decimal` from then on.
public struct Money: Sendable, Hashable, Comparable, Codable {
    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = Money.cents(amount)
    }

    public init(_ value: Double) {
        // Through the shortest text that round-trips, so 0.1 stays 0.1
        // rather than 0.1000000000000000055…
        self.init(Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value))
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Double.self)
        self.init(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode((amount as NSDecimalNumber).doubleValue)
    }

    public static let zero = Money(Decimal(0))

    public var isNegative: Bool { amount < 0 }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.amount < rhs.amount }

    public static func + (lhs: Money, rhs: Money) -> Money { Money(lhs.amount + rhs.amount) }

    /// "$1,234.56" or "-$1,234.56", as the web app writes them (US dollars,
    /// the only currency WalletWeather has).
    public var formatted: String {
        amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    /// "$1.2K", "$18K", "-$950": for chart axes, where room is short.
    public var short: String {
        let value = (amount as NSDecimalNumber).doubleValue
        let sign = value < 0 ? "-" : ""
        let size = abs(value)
        switch size {
        case 1_000_000...: return sign + "$" + Money.trim(size / 1_000_000) + "M"
        case 1_000...: return sign + "$" + Money.trim(size / 1_000) + "K"
        default: return sign + "$" + String(Int(size.rounded()))
        }
    }

    private static func trim(_ value: Double) -> String {
        value >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value)
            .replacingOccurrences(of: ".0", with: "")
    }

    private static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }
}
