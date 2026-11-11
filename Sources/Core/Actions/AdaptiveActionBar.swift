import Foundation

public struct AdaptiveActionBar {
    private let selection: SelectionContext
    private let sample: String
    private let hasText: Bool
    private let isPassage: Bool
    private let isProse: Bool
    private let isCode: Bool

    public init(selection: SelectionContext) {
        self.selection = selection
        let sample = selection.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)
        let words = sample.split(whereSeparator: \.isWhitespace)
        let letters = sample.filter(\.isLetter).count
        self.sample = String(sample)
        self.hasText = !sample.isEmpty
        self.isPassage = words.count >= 24 || letters >= 120
        self.isCode = (sample.contains("{") && sample.contains("}") && (sample.contains("(") || sample.contains("=")))
            || (sample.contains("(") && sample.contains(")") && sample.contains("\n")
                && ["def ", "func ", "function ", "class ", "import "].contains { sample.hasPrefix($0) })
        self.isProse = letters >= 12 && letters * 2 >= sample.count && (words.count >= 3 || letters >= 24)
    }

    public var canEdit: Bool { selection.source == .selection && selection.isEditable == true }

    var usageKey: String {
        let source: String
        switch selection.source {
        case .selection: source = canEdit ? "writing" : "reading"
        case .clipboard: source = "clipboard"
        case .ocr: source = "capture"
        }
        let kind: String
        switch SelectionConversion.detect(sample) {
        case .currency: kind = "currency"
        case .time, .cityTime: kind = "time"
        case .measurement: kind = "measurement"
        case .color: kind = "color"
        case nil:
            if sample.hasPrefix("https://") || sample.hasPrefix("http://") || sample.hasPrefix("www.") {
                kind = "link"
            } else if isCode {
                kind = "code"
            } else if let language = selection.translationSource {
                kind = "language-\(language)"
            } else {
                kind = hasText ? (isPassage ? "passage" : "short") : "empty"
            }
        }
        return "\(source):\(kind):\(selection.sourceApp.bundleIdentifier ?? "")"
    }

    private static let editingPresets: Set<String> = [
        "ai.preset.proofread", "ai.preset.rewrite", "ai.preset.fix_code",
        "ai.preset.formal_tone", "ai.preset.make_shorter"
    ]

    public func isEditingAction(_ action: any Action) -> Bool {
        action is any PasteRequiringAction || Self.editingPresets.contains(action.id)
    }

    public func permits(_ action: any Action) -> Bool {
        if action is PasteAction {
            return selection.pasteTargetAvailable != false && (canEdit
                || (selection.source == .clipboard && selection.pasteTargetAvailable == true))
        }
        return canEdit || !isEditingAction(action)
    }

    /// `actions` is the registry's already applicable catalog, including enabled group members.
    @MainActor
    public func suggestions(
        from actions: [any Action],
        recentUses: [String],
        contextualActionsEnabled: Bool,
        disabledContextualIDs: Set<String>
    ) -> [any Action] {
        let applicable = actions.filter { action in
            !action.chrome.launchesAI && !ActionIdentity.isCompletionPseudoAction(action)
                && action.chrome.popupBehavior != .showSubActions
                && permits(action)
        }
        let byID = Dictionary(applicable.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if !hasText {
            return [byID["builtin.paste"]].compactMap { $0 }
        }

        let matches = contextualActionsEnabled && !isPassage && !isCode
            ? applicable.filter {
                $0.isContextual && ContextualActionClassifier.hasAutomaticTrigger($0)
                    && !disabledContextualIDs.contains($0.id)
            }
            : []
        let match = matches.first { $0.id != DefineAction.actionID } ?? matches.first
        let isStructured = match.map { $0.id != DefineAction.actionID } ?? false
        var actions = [match, byID["builtin.copy"]].compactMap { $0 }

        let usedIDs = Set(actions.map(\.id))
        let counts = recentUses.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let learned = recentUses.reversed()
            .filter { !usedIDs.contains($0) && (counts[$0] ?? 0) >= 2 }
            .compactMap { byID[$0] }
            .first { action in
                if !ActionIdentity.isBindable(action) || (isStructured && !ActionIdentity.isExtension(action)) { return false }
                if action.isContextual && disabledContextualIDs.contains(action.id) { return false }
                if action.id == "ai.preset.fix_code" { return isCode }
                if action.id == "ai.preset.summarize" { return !isCode && isPassage && isProse }
                if action.id == "builtin.search" { return !isCode && !isPassage }
                return true
            }

        if isStructured, let learned {
            actions.append(learned)
        }

        if !isStructured {
            let fallback: (any Action)?
            if isCode {
                fallback = byID[canEdit ? "ai.preset.fix_code" : "ai.preset.explain"]
            } else if canEdit {
                fallback = (isProse ? byID["ai.preset.proofread"] : nil) ?? byID["builtin.paste"]
            } else if let translate = byID["ai.preset.translate"], isProse, selection.translationSource != nil {
                fallback = translate
            } else if isPassage && isProse {
                fallback = byID["ai.preset.summarize"]
            } else {
                fallback = byID["builtin.search"]
            }
            if let extra = learned ?? fallback {
                actions.append(extra)
            }
        }

        return actions
    }
}
