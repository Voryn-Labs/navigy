import Core
import XCTest

@MainActor
final class AdaptiveActionBarTests: XCTestCase {
    private let browser = AppIdentity(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
    private let proofread = CustomAction(id: "ai.preset.proofread", title: "Proofread", iconName: "text.alignleft", type: .textSnippet(template: ""))
    private let notes = CustomAction(id: "custom.notes", title: "Add to Notes", iconName: "text.alignleft", type: .textSnippet(template: ""))

    func testReadOnlyAndUnknownSelectionsKeepEditingActionsInSearch() {
        for editable: Bool? in [false, nil] {
            let selection = SelectionContext(text: "The article describes a new discovery.", sourceApp: browser, isEditable: editable)
            XCTAssertEqual(suggestions(for: selection, recent: [proofread.id, proofread.id]), ["builtin.copy", "builtin.search"])
        }
    }

    func testWritableFieldInsideSameBrowserOffersProofread() {
        let selection = SelectionContext(text: "Please send me the updated draft.", sourceApp: browser, isEditable: true)
        XCTAssertEqual(suggestions(for: selection), ["builtin.copy", proofread.id])
    }

    func testLearningStaysInTheSameAppAndReadingContext() {
        let store = ActionUsageStore(settingsStore: MemorySettingsStore())
        let reading = SelectionContext(text: "The article describes a new discovery.", sourceApp: browser, isEditable: false)
        let writing = SelectionContext(text: reading.text, sourceApp: browser, isEditable: true)
        let anotherApp = SelectionContext(text: reading.text, isEditable: false)

        store.record(notes.id, selection: reading)
        XCTAssertFalse(suggestions(for: reading, recent: store.recentUses(for: reading)).contains(notes.id))
        store.record(notes.id, selection: reading)
        XCTAssertEqual(suggestions(for: reading, recent: store.recentUses(for: reading)), ["builtin.copy", notes.id])
        XCTAssertTrue(store.recentUses(for: writing).isEmpty)
        XCTAssertTrue(store.recentUses(for: anotherApp).isEmpty)
    }

    func testMathTakesTheContextualSlot() {
        let selection = SelectionContext(text: "1250 + 340", sourceApp: browser, isEditable: false)
        let result = AdaptiveActionBar(selection: selection).suggestions(
            from: [CopyAction(), CalculateAction(), SearchAction(), proofread],
            recentUses: ["builtin.search", "builtin.search"],
            contextualActionsEnabled: true, disabledContextualIDs: []
        )
        XCTAssertEqual(result.map(\.id), ["builtin.calculate", "builtin.copy"])
    }

    func testLearnedLinkExtensionFollowsThePrimaryAction() {
        let selection = SelectionContext(text: "https://example.com", sourceApp: browser, isEditable: false)
        let open = CustomAction(id: "builtin.openurl", title: "Open Link", iconName: "link", type: .textSnippet(template: ""))
        let shorten = CustomAction(
            id: "extension.shorten", title: "Shorten Link", iconName: "link", type: .textSnippet(template: ""),
            chrome: ActionChrome(source: .extensionPkg(packageID: "test.links"))
        )
        let result = AdaptiveActionBar(selection: selection).suggestions(
            from: [open, shorten, CopyAction()], recentUses: [shorten.id, shorten.id],
            contextualActionsEnabled: true, disabledContextualIDs: []
        )
        XCTAssertEqual(result.map(\.id), [open.id, "builtin.copy", shorten.id])
    }

    private func suggestions(for selection: SelectionContext, recent: [String] = []) -> [String] {
        AdaptiveActionBar(selection: selection).suggestions(
            from: [CopyAction(), SearchAction(), CutAction(), PasteAction(), proofread, notes],
            recentUses: recent, contextualActionsEnabled: true, disabledContextualIDs: []
        ).map(\.id)
    }
}
