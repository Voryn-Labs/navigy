import Foundation

public enum SelectionConversion: Equatable, Sendable {
    case currency(amount: Double, source: String, target: String)
    case time(String)
    case cityTime(clock: String, city: String)
    case measurement(String)
    case color(InlineColor)

    public static func detect(
        _ selection: String, currency target: String = "INR",
        timeZone: TimeZone = .current, now: Date = Date(), locale: Locale = .current
    ) -> Self? {
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 160, !text.contains(where: \.isNewline) else { return nil }
        if let money = currency(in: text, target: target) { return money }
        if let token = soleCurrencyAmount(in: text), let money = currency(in: token, target: target) { return money }
        if let time = time(in: text, target: timeZone, now: now, locale: locale) { return .time(time) }
        if let clock = soleClock(in: text), let time = time(in: clock, target: timeZone, now: now, locale: locale) {
            return .time(time)
        }
        if let measure = measurement(in: text, locale: locale) { return .measurement(measure) }
        if let color = InlineColor(hex: text) { return .color(color) }
        if let fields = groups(cityTimePattern, in: text), !fields[1].isEmpty,
           time(in: fields[0] + " UTC", target: timeZone, now: now, locale: locale) != nil {
            return .cityTime(clock: fields[0], city: fields[1])
        }
        return nil
    }

    private static let number = #"[+−-]?[0-9]+(?:[.,’'\u00a0\u202f ][0-9]+)*"#
    private static let symbols = ["US$": "USD", "CA$": "CAD", "C$": "CAD", "A$": "AUD",
                                  "HK$": "HKD", "S$": "SGD", "NZ$": "NZD",
                                  "$": "USD", "₹": "INR", "€": "EUR", "£": "GBP",
                                  "¥": "JPY", "￥": "JPY", "₩": "KRW", "₽": "RUB", "฿": "THB"]
    private static let currencyCodes = Set(Locale.commonISOCurrencyCodes)
    private static let currencyToken = (symbols.keys.sorted { $0.count > $1.count }
        .map(NSRegularExpression.escapedPattern(for:)) + ["(?i:USD|INR|EUR|GBP|JPY|CAD|AUD|CHF|NZD|HKD|SGD|CNY)", "[A-Z]{3}"]).joined(separator: "|")
    private static let prefixCurrency = regex("^(\(currencyToken))\\s*(\(number))?(?:\\s*([A-Z]{3}))?$")
    private static let suffixCurrency = regex("^(\(number))\\s*(\(currencyToken))$")

    private static let embeddedCurrency = regex(
        "(?<![\\p{L}\\d])(?:(?:\(currencyToken))\\s*\(number)(?:\\s+[A-Z]{3})?|\(number)\\s*(?:\(currencyToken)))(?![\\p{L}\\d])"
    )

    private static func soleCurrencyAmount(in text: String) -> String? {
        let matches = embeddedCurrency.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let match = matches.first, let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func currency(in text: String, target: String) -> Self? {
        let token: String
        let amount: Double
        var explicitCode: String?
        if let fields = groups(prefixCurrency, in: text) {
            token = fields[0]
            if fields[1].isEmpty { amount = 1 }
            else if let value = value(fields[1]) { amount = value }
            else { return nil }
            guard fields[2].isEmpty || !fields[1].isEmpty else { return nil }
            explicitCode = fields[2].isEmpty ? nil : fields[2]
        } else if let fields = groups(suffixCurrency, in: text), let value = value(fields[0]) {
            token = fields[1]
            amount = value
        } else {
            return nil
        }
        let code = explicitCode ?? symbols[token] ?? token.uppercased()
        guard currencyCodes.contains(code), abs(amount) < 1e12 else { return nil }
        let preferred = currencyCodes.contains(target) ? target : "INR"
        return .currency(amount: amount, source: code, target: preferred == code ? (code == "USD" ? "INR" : "USD") : preferred)
    }

    private struct UnitRule: Sendable {
        let factor: Double
        let symbol: String
        let offset: Double
        init(_ factor: Double, _ symbol: String, offset: Double = 0) {
            self.factor = factor
            self.symbol = symbol
            self.offset = offset
        }
    }

    private static let rules: [String: UnitRule] = [
        "mm": .init(1 / 25.4, "in"), "cm": .init(1 / 2.54, "in"), "m": .init(1 / 0.3048, "ft"),
        "km": .init(1 / 1.609344, "mi"), "in": .init(2.54, "cm"), "inch": .init(2.54, "cm"), "inches": .init(2.54, "cm"),
        "ft": .init(0.3048, "m"), "feet": .init(0.3048, "m"), "yd": .init(0.9144, "m"), "mi": .init(1.609344, "km"),
        "mg": .init(0.001, "g"), "g": .init(1 / 28.349523125, "oz"), "kg": .init(1 / 0.45359237, "lb"),
        "oz": .init(28.349523125, "g"), "lb": .init(0.45359237, "kg"), "lbs": .init(0.45359237, "kg"),
        "ml": .init(1 / 29.5735295625, "US fl oz"), "l": .init(1 / 3.785411784, "US gal"),
        "fl oz": .init(29.5735295625, "mL"), "us fl oz": .init(29.5735295625, "mL"), "us gal": .init(3.785411784, "L"),
        "°c": .init(1.8, "°F", offset: 32), "°f": .init(1 / 1.8, "°C", offset: -32 / 1.8),
        "mph": .init(1.609344, "km/h"), "km/h": .init(1 / 1.609344, "mph"),
        "m/s": .init(3.6, "km/h"), "kn": .init(1.852, "km/h"),
        "ft²": .init(0.09290304, "m²"), "sq ft": .init(0.09290304, "m²"), "m²": .init(1 / 0.09290304, "ft²"),
        "cm²": .init(1 / 6.4516, "in²"), "in²": .init(6.4516, "cm²"),
        "ha": .init(2.47105381, "ac"), "ac": .init(0.404685642, "ha"),
        "px": .init(0.75, "pt"), "pt": .init(4 / 3, "px"), "rem": .init(16, "px"), "em": .init(16, "px"),
        "ms": .init(0.001, "s"), "sec": .init(1 / 60, "min"), "min": .init(1 / 60, "h"),
        "hr": .init(60, "min"), "hrs": .init(60, "min")
    ]
    private static let dataRules: [String: UnitRule] = [
        "kB": .init(1_000 / 1_024, "KiB"), "KB": .init(1_000 / 1_024, "KiB"),
        "MB": .init(1_000_000 / 1_048_576, "MiB"), "GB": .init(1_000_000_000 / 1_073_741_824, "GiB"),
        "TB": .init(1_000_000_000_000 / 1_099_511_627_776, "TiB"),
        "KiB": .init(1_024 / 1_000, "kB"), "MiB": .init(1_048_576 / 1_000_000, "MB"),
        "GiB": .init(1_073_741_824 / 1_000_000_000, "GB"), "TiB": .init(1_099_511_627_776 / 1_000_000_000_000, "TB"),
        "B": .init(1 / 1_000, "kB"), "Mb": .init(0.125, "MB"), "Gb": .init(0.125, "GB")
    ]
    private static let unitAliases = [
        "millimeter": "mm", "millimeters": "mm", "millimetres": "mm",
        "centimeter": "cm", "centimeters": "cm", "centimetres": "cm",
        "meters": "m", "metres": "m", "kilometer": "km", "kilometers": "km", "kilometres": "km",
        "kilograms": "kg", "pounds": "lb", "liters": "l", "litres": "l", "square feet": "ft²"
    ]
    private static let feetAndInches = regex(#"^(\d+)\s*(?:ft|['′])\s*(\d+(?:[.,]\d+)?)\s*(?:in|["″])$"#)
    private static let measurePattern = regex("^(\(number))\\s*([a-zA-Z°²/][a-zA-Z°²/ ]{0,13})$")
    private static let dimensionSplit = regex(#"\s*[×xX]\s*(?=[0-9])"#)

    private static func measurement(in text: String, locale: Locale) -> String? {
        if let parts = groups(feetAndInches, in: text),
           let feet = Double(parts[0]), let inches = value(parts[1]), inches < 12 {
            let result = (feet * 12 + inches) * 2.54
            return result.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + " cm"
        }
        let delimiter = dimensionSplit.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var parts: [String] = []
        var start = text.startIndex
        for match in delimiter {
            guard let range = Range(match.range, in: text) else { return nil }
            parts.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        parts.append(String(text[start...]))
        guard parts.count <= 3, let last = parts.last, let fields = groups(measurePattern, in: last),
              let lastValue = value(fields[0]),
              let rule = dataRules[fields[1]] ?? rules[unitAliases[fields[1].lowercased()] ?? fields[1].lowercased()] else { return nil }
        let leading = parts.dropLast().compactMap { part -> Double? in
            if let number = value(part) { return number }
            guard let item = groups(measurePattern, in: part),
                  item[1].lowercased() == fields[1].lowercased() else { return nil }
            return value(item[0])
        }
        guard leading.count == parts.count - 1, parts.count == 1 || rule.offset == 0 else { return nil }
        let converted = (leading + [lastValue]).map { $0 * rule.factor + rule.offset }
        guard converted.allSatisfy({ $0.isFinite && abs($0) < 1e15 }) else { return nil }
        return converted.map { $0.formatted(.number.precision(.fractionLength(0...3)).locale(locale)) }
            .joined(separator: " × ") + " " + rule.symbol
    }

    private static let zonePattern = regex(#"^(?:(\d{4})-(\d{2})-(\d{2})\s+)?(\d{1,2})(?::(\d{2}))?\s*(?i:(am|pm))?\s+(.+)$"#)
    private static let embeddedClock = regex(#"(?<![0-9:])\d{1,2}:\d{2}\s*(?:(?i:am|pm)\s*)?(?:[A-Z]{1,4}(?:[+-]\d{1,2}(?::?\d{2})?)?|[A-Za-z]+/[A-Za-z_]+)(?![A-Za-z0-9])"#)

    private static func soleClock(in text: String) -> String? {
        let matches = embeddedClock.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let match = matches.first, let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static let offsetPattern = regex(#"^(?:UTC|GMT)?([+-])(\d{1,2})(?::?(\d{2}))?$"#)
    private static let zones = ["ET": "America/New_York", "PT": "America/Los_Angeles",
                                "CT": "America/Chicago", "MT": "America/Denver", "IST": "Asia/Kolkata",
                                "JST": "Asia/Tokyo", "SGT": "Asia/Singapore", "HKT": "Asia/Hong_Kong",
                                "KST": "Asia/Seoul", "DELHI": "Asia/Kolkata"]
    private static let cityTimePattern = regex(#"(?i)^([0-9]{1,2}:[0-9]{2}(?:\s*[ap]m)?)\s+([\p{L}][\p{L} .,'’\-]{1,65})\s+time$"#)

    private static func cityKey(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
    }

    private static let zoneCities: [String: String] = {
        let grouped = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers) { identifier in
            cityKey(identifier.split(separator: "/").last.map(String.init) ?? identifier)
        }
        return grouped.compactMapValues { $0.count == 1 ? $0.first : nil }
    }()

    private static let fixedZones = ["UTC": 0, "GMT": 0, "Z": 0, "PST": -8, "PDT": -7, "MST": -7, "MDT": -6,
                                     "CST": -6, "CDT": -5, "EST": -5, "EDT": -4, "CET": 1, "CEST": 2,
                                     "EET": 2, "EEST": 3, "BST": 1, "AEST": 10, "AEDT": 11]
    private static let namedTimeZones = Dictionary(
        TimeZone.knownTimeZoneIdentifiers.map { ($0.uppercased(), $0) }, uniquingKeysWith: { first, _ in first }
    )

    private static func zone(_ text: String) -> TimeZone? {
        var key = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if key.hasSuffix(" TIME") { key = String(key.dropLast(5)) }
        if let hours = fixedZones[key] { return TimeZone(secondsFromGMT: hours * 3600) }
        if let id = zones[key] ?? namedTimeZones[key] ?? zoneCities[cityKey(key)] { return TimeZone(identifier: id) }
        guard let parts = groups(offsetPattern, in: key), let hour = Int(parts[1]),
              hour <= 14, (Int(parts[2]) ?? 0) < 60 else { return nil }
        let minutes = Int(parts[2]) ?? 0
        guard hour < 14 || minutes == 0 else { return nil }
        return TimeZone(secondsFromGMT: (parts[0] == "-" ? -1 : 1) * (hour * 3600 + minutes * 60))
    }

    private static func time(in text: String, target: TimeZone, now: Date, locale: Locale) -> String? {
        if let source = zone(text), text == text.uppercased() || text.contains("/") || text.lowercased().hasSuffix(" time") {
            return formatTime(now, in: source, locale: locale)
        }
        guard let parts = groups(zonePattern, in: text), let source = zone(parts[6]),
              var hour = Int(parts[3]), hour < 24 else { return nil }
        let minute = Int(parts[4]) ?? 0
        guard minute < 60 else { return nil }
        if parts[4].isEmpty, parts[5].isEmpty, rules[parts[6]] != nil { return nil }
        if !parts[5].isEmpty {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (parts[5].lowercased() == "pm" ? 12 : 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source
        var dateParts = calendar.dateComponents([.year, .month, .day], from: now)
        if let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            dateParts.year = year
            dateParts.month = month
            dateParts.day = day
        }
        dateParts.hour = hour
        dateParts.minute = minute
        guard let date = calendar.date(from: dateParts) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard verified.year == dateParts.year, verified.month == dateParts.month, verified.day == dateParts.day,
              verified.hour == hour, verified.minute == minute else { return nil }
        let sourceDay = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = target
        let targetDay = calendar.dateComponents([.year, .month, .day], from: date)
        return formatTime(date, in: target, locale: locale, showDate: !parts[0].isEmpty || sourceDay != targetDay)
    }

    private static func formatTime(_ date: Date, in zone: TimeZone, locale: Locale, showDate: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(showDate ? "MMM d j:mm" : "j:mm")
        let zoneLabel = zone.identifier == "Asia/Kolkata" || zone.identifier == "Asia/Calcutta"
            ? "IST" : (zone.abbreviation(for: date) ?? zone.identifier)
        return formatter.string(from: date) + " " + zoneLabel
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are static and contain no user input.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func groups(_ regex: NSRegularExpression, in text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func value(_ input: String) -> Double? {
        var token = input.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }.replacingOccurrences(of: "−", with: "-")
        let separators = token.indices.filter { token[$0] == "." || token[$0] == "," }
        if let last = separators.last {
            let after = token.distance(from: token.index(after: last), to: token.endIndex)
            if token.contains(".") && token.contains(",") || separators.count == 1 && (token[last] == "." || after != 3) {
                let head = token[..<last].filter { $0 != "." && $0 != "," }
                token = head + "." + token[token.index(after: last)...]
            } else {
                token.removeAll { $0 == "." || $0 == "," }
            }
        }
        guard let result = Double(token), result.isFinite else { return nil }
        return result
    }
}
