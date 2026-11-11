// AboutTabView.swift
// OpenClip
//
// The About preferences tab: app identity, upstream attribution, and diagnostics.
// Styled with inset SettingsCards (outside headers, rounded cards, inset hairline dividers).

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Core

@MainActor
struct AboutTab: View {
    @State private var isExporting = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Identity block
                identityBlock

                // Diagnostics
                SettingsCard("Diagnostics") {
                    SettingsRow(
                        title: "Logs",
                        subtitle: "Attach these when reporting a problem."
                    ) {
                        HStack(spacing: 10) {
                            Button(isExporting ? String(localized: "Exporting…") : String(localized: "Export…")) {
                                exportLogs()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                            .disabled(isExporting)

                            Button(String(localized: "Reveal")) {
                                LogExporter.showLogsInFinder()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                    }
                }

                Text("Open source under AGPL-3.0 License")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Pieces

    private var identityBlock: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 72, height: 72)

            Text("Navigy")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SettingsDesignTokens.primaryText)

            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Link("Based on OpenClip", destination: URL(string: "https://github.com/ganeshmshetty/openclip")!)
                .font(.callout)

        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func exportLogs() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let tempZipURL = try await LogExporter.exportLogs()
                defer {
                    try? FileManager.default.removeItem(at: tempZipURL)
                }

                let panel = NSSavePanel()
                panel.title = String(localized: "Export Logs")
                panel.nameFieldStringValue = tempZipURL.lastPathComponent
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true

                if panel.runModal() == .OK, let destinationURL = panel.url {
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: tempZipURL, to: destinationURL)
                }
            } catch {
                SettingsRouter.shared.notifyError(
                    title: String(localized: "Export Logs Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }
}

