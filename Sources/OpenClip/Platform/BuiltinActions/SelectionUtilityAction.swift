import AppKit
import Foundation
import NaturalLanguage
import UniformTypeIdentifiers
import CoreLocation
import Core

struct SelectionUtilityAction: Action {
    let conversion: SelectionConversion
    let preview: InlineResultValue?

    @MainActor
    init(_ conversion: SelectionConversion) {
        self.conversion = conversion
        switch conversion {
        case .currency(let amount, let source, let target):
            self.preview = CurrencyRates.shared.cached(source: source, target: target)
                .map { .text(Self.money(amount * $0.rate, target: target)) }
        case .cityTime:
            self.preview = nil
        case .time(let value), .measurement(let value):
            self.preview = .text(value)
        case .color(let color):
            self.preview = .color(color)
        }
    }

    var id: String {
        switch conversion {
        case .currency: "builtin.convertCurrency"
        case .time, .cityTime: "builtin.convertTime"
        case .measurement: "builtin.convertMeasurement"
        case .color: "builtin.colorPreview"
        }
    }

    var title: String {
        switch conversion {
        case .currency(_, let source, let target): "\(source) → \(target)"
        case .time, .cityTime: String(localized: "Convert Time")
        case .measurement: String(localized: "Convert Units")
        case .color: String(localized: "Color Preview")
        }
    }

    var icon: ActionIcon {
        switch conversion {
        case .currency: .text(title)
        case .time, .cityTime: .symbol("clock")
        case .measurement: .symbol("ruler")
        case .color: .symbol("paintpalette")
        }
    }

    var chrome: ActionChrome {
        let kind: ActionOutputKind = if case .color = conversion { .color } else { .text }
        return ActionChrome(
            showsLoading: preview == nil,
            isInlineResult: true,
            outputKind: kind,
            recommendedResult: .preview,
            contextualOverride: true
        )
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        try await resolvedPreview().inlineActionResult
    }

    @MainActor func resolvedPreview() async throws -> InlineResultValue {
        if let preview { return preview }
        if case .cityTime(let clock, let city) = conversion {
            let matches = try await CLGeocoder().geocodeAddressString(city)
            let zones = Set(matches.compactMap { $0.timeZone?.identifier })
            guard zones.count == 1, let zone = zones.first,
                  case .time(let value) = SelectionConversion.detect(clock + " " + zone) else {
                throw URLError(.cannotDecodeContentData)
            }
            return .text(value)
        }
        guard case .currency(let amount, let source, let target) = conversion else {
            throw URLError(.cannotDecodeContentData)
        }
        let quote = try await CurrencyRates.shared.quote(source: source, target: target)
        return .text(Self.money(amount * quote.rate, target: target))
    }

    private static func money(_ amount: Double, target: String) -> String {
        "≈ " + amount.formatted(.currency(code: target))
    }
}

@MainActor
final class CurrencyRates {
    static let shared = CurrencyRates()

    struct Quote: Codable, Sendable {
        let rate: Double
        let fetched: Date
    }

    private let cacheKey = SettingKey<Data?>("currencyRateCache", defaultValue: nil)
    private let settings = DefaultSettingsStore.shared
    private var requests: [String: Task<Quote, Error>] = [:]
    private var quotes: [String: Quote] = [:]

    private init() {
        if let data = settings.get(cacheKey) {
            quotes = (try? JSONDecoder().decode([String: Quote].self, from: data)) ?? [:]
        }
    }

    func cached(source: String, target: String) -> Quote? {
        let quote = quotes["\(source)/\(target)"]
        guard let quote, Date().timeIntervalSince(quote.fetched) < 12 * 3600 else { return nil }
        return quote
    }

    func quote(source: String, target: String) async throws -> Quote {
        if let quote = cached(source: source, target: target) { return quote }
        let pair = "\(source)/\(target)"
        if let request = requests[pair] { return try await request.value }
        let request = Task {
            struct Response: Decodable {
                let base: String
                let quote: String
                let rate: Double
            }
            guard let url = URL(string: "https://api.frankfurter.dev/v2/rate/" + pair) else {
                throw URLError(.badURL)
            }
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 6))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard decoded.base == source, decoded.quote == target, decoded.rate.isFinite, decoded.rate > 0 else {
                throw URLError(.cannotDecodeContentData)
            }
            let quote = Quote(rate: decoded.rate, fetched: Date())
            quotes[pair] = quote
            quotes = quotes.filter { Date().timeIntervalSince($0.value.fetched) < 7 * 24 * 3600 }
            settings.set(cacheKey, value: try? JSONEncoder().encode(quotes))
            return quote
        }
        requests[pair] = request
        defer { requests[pair] = nil }
        return try await request.value
    }
}

struct SelectionContactAction: Action {
    enum Kind: String, Sendable {
        case call, chat, share
    }

    let kind: Kind
    let number: String?

    var id: String { "builtin.selectionContact." + kind.rawValue }
    var title: String {
        switch kind {
        case .call: String(localized: "Call Number")
        case .chat: String(localized: "Chat on WhatsApp")
        case .share: String(localized: "Share via WhatsApp")
        }
    }
    var icon: ActionIcon {
        switch kind {
        case .call: .symbol("phone")
        case .chat: .symbol("phone.bubble")
        case .share: .symbol("square.and.arrow.up")
        }
    }

    static func available(for selection: SelectionContext) -> [Self] {
        let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let numberPattern = #"^\+?[0-9(][0-9(). -]*[0-9)]$"#
        if text.range(of: numberPattern, options: .regularExpression) != nil {
            let digits = text.filter { $0.isASCII && $0.isNumber }
            let localIndia = Locale.current.region?.identifier == "IN"
                && digits.count == 10 && digits.first.map { "6789".contains($0) } == true
            if (7...15).contains(digits.count),
               localIndia || !selection.detectedContent(for: [.phone]).phones.isEmpty {
                let international = text.hasPrefix("+") || digits.hasPrefix("00")
                let normalized = digits.hasPrefix("00") ? String(digits.dropFirst(2)) : digits
                let dial = international ? "+" + normalized : normalized
                let chatNumber = international ? dial : (localIndia ? "+91" + normalized : normalized)
                return [Self(kind: .call, number: dial), Self(kind: .chat, number: chatNumber)]
            }
        }
        let hasText = !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || imageFlavor(in: selection) != nil else { return [] }
        return [Self(kind: .share, number: nil)]
    }

    static func imageFlavor(in selection: SelectionContext) -> RichPasteboardFlavor? {
        selection.flavors.first { UTType($0.type)?.conforms(to: .image) == true }
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        if kind == .call, let number, let url = URL(string: "tel:" + number) { return .openURL(url) }
        if kind == .share, let flavor = Self.imageFlavor(in: context.selection),
           let image = NSImage(data: flavor.data) {
            if let service = NSSharingService.sharingServices(forItems: [image]).first(where: {
                $0.title.localizedCaseInsensitiveContains("WhatsApp")
            }) {
                service.perform(withItems: [image])
                return .success
            }
            let destination = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp")
                ?? URL(string: "https://web.whatsapp.com")!
            return .sequence([
                .copyContent(RichPasteboardPayload(flavors: [flavor])),
                .openURL(destination)
            ])
        }
        let recipient: String
        if kind == .chat, let number {
            guard let confirmed = Self.internationalNumber(for: number) else { return .none }
            recipient = confirmed
        } else {
            recipient = ""
        }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "wa.me"
        url.path = "/" + recipient
        if kind == .share {
            url.queryItems = [URLQueryItem(name: "text", value: context.selection.text)]
        }
        return url.url.map { .openURL($0) } ?? .none
    }

    @MainActor private static func internationalNumber(for number: String) -> String? {
        if number.hasPrefix("+") { return String(number.dropFirst()) }

        let alert = NSAlert()
        alert.messageText = String(localized: "Chat on WhatsApp")
        alert.informativeText = String(localized: "Enter the full phone number with its country code, starting with +.")
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(string: number)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let validator = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: field, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                alert.buttons[0].isEnabled = Self.isInternational(field.stringValue)
            }
        }
        defer { NotificationCenter.default.removeObserver(validator) }
        alert.buttons[0].isEnabled = false
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, isInternational(field.stringValue) else { return nil }
        return field.stringValue.filter { $0.isASCII && $0.isNumber }
    }

    private static func isInternational(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespaces).range(
            of: #"^\+[1-9](?:[ ().-]*[0-9]){6,14}$"#, options: .regularExpression
        ) != nil
    }

}

struct SelectionSummaryAction: Action {
    static let actionID = "builtin.selectionSummary"
    let id = Self.actionID
    var title: String { String(localized: "Summarize") }
    var icon: ActionIcon { .symbol("text.alignleft") }
    var chrome: ActionChrome { ActionChrome(outputKind: .text, recommendedResult: .preview) }
    private let text: String

    init?(selection: SelectionContext) {
        let candidate = String(selection.text.prefix(20_000))
        guard candidate.utf8.count >= 140,
              candidate.prefix(256).filter(\.isLetter).count >= 75 else { return nil }
        text = candidate
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            .map { text[$0].trimmingCharacters(in: .whitespacesAndNewlines) }
        guard sentences.count > 1 else { return .text(text) }

        let words = sentences.map { sentence in
            Set(sentence.lowercased().split { !$0.isLetter }.filter { $0.count > 3 }.map(String.init))
        }
        let frequencies = words.reduce(into: [String: Int]()) { counts, sentence in
            for word in sentence { counts[word, default: 0] += 1 }
        }
        let scores = words.enumerated().map { index, sentence -> (index: Int, score: Double) in
            let matches = sentence.reduce(0) { $0 + (frequencies[$1, default: 1] - 1) }
            let overlap = Double(matches) / Double(max(1, sentence.count))
            let detail = Double(min(sentence.count, 22)) / 22
            return (index, overlap + detail)
        }
        let ranked = scores.sorted { left, right in
            if left.score == right.score { return left.index < right.index }
            return left.score > right.score
        }
        let limit = min(3, max(1, (sentences.count + 1) / 2))
        let selected = ranked.prefix(limit).map(\.index).sorted()
        return .text(selected.map { "• " + sentences[$0] }.joined(separator: "\n"))
    }
}
