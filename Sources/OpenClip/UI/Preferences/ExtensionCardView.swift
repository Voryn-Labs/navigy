// ExtensionCardView.swift
// OpenClip
//
// Store list row for one extension listing.
import SwiftUI
import Core

struct ExtensionCardView: View {
    let item: ExtensionItem
    let isFeaturedExplicit: Bool?

    init(item: ExtensionItem, isFeatured: Bool? = nil) {
        self.item = item
        self.isFeaturedExplicit = isFeatured
    }

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared
    @State private var isInstalling = false
    @State private var isUninstalling = false
    @State private var isUpdating = false
    @State private var installError: String? = nil

    private var matchingInstalledAction: (any Action)? {
        coordinator.actions.first { action in
            let packageID = ActionIdentity.extensionPackageID(of: action) ?? action.id
            return packageID.caseInsensitiveCompare(item.id) == .orderedSame
        }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    /// SF Symbol name when the icon is one (bare or `symbol:`-prefixed); nil for file or remote references.
    private var bareSymbolName: String? {
        var icon = item.icon
        if icon.hasPrefix("symbol:") { icon = String(icon.dropFirst("symbol:".count)) }
        guard !icon.isEmpty else { return nil }
        let lowered = icon.lowercased()
        guard !lowered.hasSuffix(".svg")
            && !lowered.hasSuffix(".png")
            && !icon.contains("/")
            && !icon.contains(":") else { return nil }
        return icon
    }

    /// Deterministic letter tile (hue hashed from the id) — the last-resort icon.
    private var letterTile: some View {
        let hue = {
            var h = 0
            for b in item.id.utf8 { h = (h &* 31 &+ Int(b)) % 360 }
            return max(h, 0)
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hue: Double(hue), saturation: 0.55, brightness: 0.75))
            Text(String(item.name.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? "?"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var isFeatured: Bool {
        isFeaturedExplicit ?? ExtensionsStoreViewModel.isFeatured(item)
    }

    /// Byline, downloads and date; the last two are what the Store sorts by.
    private var metadataLine: String {
        var parts: [String] = []
        if !item.author.isEmpty {
            parts.append(item.author)
        }
        if item.downloadCount == 1 {
            parts.append(String(localized: "\(formattedDownloadCount(item.downloadCount)) download"))
        } else if item.downloadCount > 1 {
            parts.append(String(localized: "\(formattedDownloadCount(item.downloadCount)) downloads"))
        }
        // Prefer the stable first-added date; fall back to the last-release date for older snapshots.
        if let added = item.addedDate ?? item.publishedDate {
            parts.append(String(localized: "Added \(added.formatted(.dateTime.day().month(.abbreviated).year()))"))
        }
        return parts.joined(separator: " · ")
    }

    private func formattedDownloadCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM", millions)
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000.0
            return thousands.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(thousands))k" : String(format: "%.1fk", thousands)
        } else {
            return "\(count)"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Remote template icon, else a bare SF Symbol, else a letter tile.
            ZStack {
                if let urlString = item.iconURL, let url = URL(string: urlString) {
                    RemoteTemplateIcon(url: url)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.primary)
                } else if let symbolName = bareSymbolName {
                    ActionIconView(icon: .symbol(symbolName), size: 18)
                        .foregroundColor(.accentColor)
                } else {
                    letterTile
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(7)

            // Three levels: name (scanned), description (read), byline and downloads (secondary).
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if isFeatured {
                        Image(systemName: "rosette")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .help(String(localized: "Featured"))
                            .accessibilityLabel(String(localized: "Featured"))
                    }
                }

                if let err = installError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(item.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if isInstalled, updateManager.updatablePackageIDs.contains(item.id) {
                    if #available(macOS 26.0, *) {
                        Button(action: {
                            isUpdating = true
                            installError = nil
                            Task {
                                do {
                                    try await updateManager.update(packageID: item.id)
                                } catch {
                                    installError = error.localizedDescription
                                }
                                isUpdating = false
                                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                            }
                        }) {
                            Label(isUpdating ? String(localized: "Updating…") : String(localized: "Update"), systemImage: "arrow.down.circle")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(SettingsDesignTokens.glassButtonBlue)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                        }
                        .buttonStyle(.plain)
                        .background(.ultraThinMaterial, in: .capsule)
                        .glassEffect(.regular.tint(SettingsDesignTokens.glassButtonBlue.opacity(0.18)).interactive(), in: .capsule)
                        .contentShape(Capsule())
                        .disabled(isUpdating)
                    } else {
                        Button(action: {
                            isUpdating = true
                            installError = nil
                            Task {
                                do {
                                    try await updateManager.update(packageID: item.id)
                                } catch {
                                    installError = error.localizedDescription
                                }
                                isUpdating = false
                                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                            }
                        }) {
                            Label(isUpdating ? String(localized: "Updating…") : String(localized: "Update"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isUpdating)
                    }
                }

                StoreActionButton(
                    item: item,
                    isInstalled: isInstalled,
                    isInstalling: isInstalling,
                    isUninstalling: isUninstalling,
                    onInstall: {
                        performInstall()
                    },
                    onUninstall: {
                        performUninstall()
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func performInstall() {
        guard let url = URL(string: item.downloadURL) else {
            installError = String(localized: "Invalid download URL.")
            return
        }
        isInstalling = true
        installError = nil
        Task {
            defer { isInstalling = false }
            do {
                _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
            } catch {
                installError = error.localizedDescription
            }
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        }
    }

    private func performUninstall() {
        guard let action = matchingInstalledAction else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isUninstalling = true
        }
        installError = nil
        Task {
            let startTime = Date()
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
            } catch {
                installError = error.localizedDescription
                Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
            }
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.3 {
                try? await Task.sleep(nanoseconds: UInt64((0.3 - elapsed) * 1_000_000_000))
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                isUninstalling = false
            }
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        }
    }
}

// MARK: - Store Action Button

private struct StoreActionButton: View {
    let item: ExtensionItem
    let isInstalled: Bool
    let isInstalling: Bool
    let isUninstalling: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        if isInstalled {
            HStack(spacing: 8) {
                Label("Installed", systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onUninstall) {
                    if isUninstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .disabled(isUninstalling)
                .help(String(localized: "Remove \(item.name)"))
                .accessibilityLabel(String(localized: "Remove \(item.name)"))
            }
        } else {
            Button(action: onInstall) {
                HStack(spacing: 6) {
                    if isInstalling {
                        ProgressView().controlSize(.small)
                    }
                    Text(isInstalling ? "Installing…" : "Add")
                }
                .frame(minWidth: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling)
            .help(String(localized: "Install \(item.name)"))
            .accessibilityLabel(String(localized: "Install \(item.name)"))
        }
    }
}

