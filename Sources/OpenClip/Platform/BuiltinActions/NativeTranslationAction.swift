import AppKit
import SwiftUI
import Translation
import Core

@available(macOS 15.0, *)
struct NativeTranslationAction: Action {
    let language: String
    let id = "builtin.nativeTranslate"
    var title: String { String(localized: "Translate") }
    var icon: ActionIcon { .symbol("character.book.closed") }

    @MainActor func isEnabled(for context: ActionContext) -> Bool {
        !context.selection.text.isEmpty
    }

    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        NativeTranslationWindow.shared.show(text: context.selection.text, source: language, at: context.selection.cursorPosition)
        return .success
    }
}

@available(macOS 15.0, *)
@MainActor
private final class NativeTranslationWindow: NSObject, NSWindowDelegate {
    static let shared = NativeTranslationWindow()
    private var panel: NSPanel?

    func show(text: String, source: String, at point: CGPoint) {
        panel?.close()
        let size = CGSize(width: 340, height: 168)
        let frame = (PopupPositioner.screen(containing: point) ?? NSScreen.main)?.visibleFrame
            ?? CGRect(origin: point, size: size)
        let x = min(max(frame.minX, point.x - 30), frame.maxX - size.width)
        let y = min(max(frame.minY, point.y - size.height - 12), frame.maxY - size.height)
        let window = NSPanel(
            contentRect: CGRect(origin: CGPoint(x: x, y: y), size: size),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        window.title = String(localized: "Translate")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: NativeTranslationResult(text: text, source: source))
        panel = window
        AppActivationPolicy.enter()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        AppActivationPolicy.leave()
    }
}

@available(macOS 15.0, *)
private struct NativeTranslationResult: View {
    let text: String
    let source: String
    @State private var translated: String?
    @State private var error: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("\(Locale.current.localizedString(forLanguageCode: source) ?? source) → \(String(localized: "English"))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                if let translated {
                    Text(translated)
                        .font(.system(size: 15))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error {
                    Text(error).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                Button(didCopy ? "Copied" : "Copy") {
                    guard let translated else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(translated, forType: .string)
                    didCopy = true
                }
                .disabled(translated == nil)
            }
        }
        .padding(14)
        .frame(width: 340, height: 168)
        .translationTask(source: Locale.Language(identifier: source), target: Locale.Language(identifier: "en")) { @Sendable [text] session in
            do {
                let response = try await session.translate(text)
                guard !Task.isCancelled else { return }
                let translatedText = response.targetText
                await MainActor.run { translated = translatedText }
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                await MainActor.run { self.error = message }
            }
        }
    }
}
