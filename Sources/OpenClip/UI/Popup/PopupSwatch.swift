// PopupSwatch.swift
// OpenClip
//
// The Appearance settings preview uses the same theme, color mode and scale as the live popup.

import SwiftUI
import AppKit
import Core

@MainActor
struct PopupSwatch: View {
    /// Fixed 13-action set, independent of the user's bar, so pagination is exercised.
    static let actions: [any Action] = [
        CalculateAction(),
        CustomAction(id: "swatch.search", title: "Search", iconName: "magnifyingglass", type: .textSnippet(template: "")),
        CopyAction(),
        CutAction(),
        PasteAction(),
        CustomAction(id: "swatch.define", title: "Define", iconName: "book.closed", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.calendar", title: "Add Event", iconName: "calendar.badge.plus", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.uppercase", title: "Uppercase", iconName: "textformat.size.larger", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.lowercase", title: "Lowercase", iconName: "textformat.size.smaller", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.share", title: "Share", iconName: "square.and.arrow.up", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.translate", title: "Translate", iconName: "character.book.closed", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.summarize", title: "Summarize", iconName: "doc.text.magnifyingglass", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.notes", title: "Add to Notes", iconName: "note.text.badge.plus", type: .textSnippet(template: ""))
    ]

    /// Resting hover state; the preview never observes it, so it can't leak into the real popup.
    private static let hoverState = PopupHoverState()

    var height: CGFloat = 116
    /// Extra headroom above the bar so the drop shadow doesn't make the preview look top-heavy.
    var topInset: CGFloat = 12

    @Setting(SettingKey.adaptiveActionBar) private var adaptiveActionBar
    @State private var previewMode = 0
    private var writing: Bool { previewMode == 1 }
    @Setting(SettingKey.popupTheme) private var storedTheme
    @Setting(SettingKey.popupThemeColor) private var storedColor
    @Environment(\.colorScheme) private var systemScheme

    private var category: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: storedTheme)
    }

    private var effectiveTheme: String {
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: storedColor, systemIsDark: systemScheme == .dark)
    }

    private var effectiveScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: storedColor, systemIsDark: systemScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 10) {
            if adaptiveActionBar {
                Picker("Popup Preview", selection: $previewMode) {
                    Text("Reading").tag(0)
                    Text("Writing").tag(1)
                    Text("Convert Units").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            preview
        }
    }

    private var preview: some View {
        let context = mockContext
        let utility = adaptiveActionBar ? previewUtility(for: context.selection.text) : nil
        let suggestions: [any Action]?
        if let utility {
            suggestions = [utility, CopyAction()]
        } else if adaptiveActionBar {
            suggestions = AdaptiveActionBar(selection: context.selection).suggestions(
                from: [CopyAction(), SearchAction(), PasteAction()],
                recentUses: [],
                contextualActionsEnabled: true,
                disabledContextualIDs: []
            )
        } else {
            suggestions = nil
        }
        let modeStore = PopupModeStore()
        modeStore.subBarAbove = true
        if let conversion = utility as? SelectionUtilityAction, let value = conversion.preview {
            modeStore.inlineResults[conversion.id] = value
        }
        // The stage owns its size; a wider popup must not enlarge the settings pane.
        return Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            PopupPreviewLayout {
                PopupView(
                    actions: Self.actions,
                    adaptiveActions: suggestions,
                    utilityAction: utility,
                    context: context,
                    hoverState: Self.hoverState,
                    presenter: PopupPreviewPresenter(),
                    isStatic: true,
                    modeStore: modeStore
                ) { _ in }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, topInset)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopupMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SettingsDesignTokens.sectionCardBorder, lineWidth: 0.5)
        )
        .environment(\.colorScheme, effectiveScheme)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: effectiveTheme)
        .animation(.easeInOut(duration: 0.15), value: effectiveScheme)
    }

    private func previewUtility(for text: String) -> (any Action)? {
        if let conversion = SelectionConversion.detect(text) { return SelectionUtilityAction(conversion) }
        if #available(macOS 15.0, *), let language = TextLanguageDetector.translationSource(for: text) {
            return NativeTranslationAction(language: language)
        }
        return nil
    }

    private var mockContext: ActionContext {
        let text = switch previewMode {
        case 1: "Please send me the updated draft."
        case 2: "5 × 7 in"
        default: "Bitte senden Sie mir den aktualisierten Entwurf."
        }
        let context = SelectionContext(
            text: text,
            sourceApp: AppIdentity(NSRunningApplication.current),
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default,
            isEditable: writing
        )
        return ActionContext(selection: context, modifiers: [])
    }
}

/// Preview glyphs are fixed samples rather than the user's saved action customizations.
@MainActor
private struct PopupPreviewPresenter: ActionPresenting {
    func displayTitle(for action: any Action) -> String { action.title }
    func popupIcon(for action: any Action) -> ActionIcon { action.icon }
    func tableIcon(for action: any Action) -> ActionIcon { action.icon }
}

/// Centers the popup when it fits; otherwise keeps a leading inset. Never changes the proposed size.
private struct PopupPreviewLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let popup = subviews.first else { return }
        let size = popup.sizeThatFits(.unspecified)
        popup.place(
            at: CGPoint(
                x: bounds.minX + max(16, (bounds.width - size.width) / 2),
                y: bounds.midY - size.height / 2
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }
}
