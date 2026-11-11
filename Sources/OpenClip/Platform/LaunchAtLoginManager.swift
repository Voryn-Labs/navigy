// LaunchAtLoginManager.swift
// OpenClip
//
// Manages macOS login item registration using ServiceManagement SMAppService APIs.
// Persisted state goes through `SettingKey.startAtLogin` via the settings store — never raw
// `UserDefaults`. (Deployment target is macOS 14, so the pre-13 fallbacks are dead and dropped.)
import Foundation
import ServiceManagement
import AppKit
import Core

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public var isEnabled: Bool {
        didSet {
            guard !syncing else { return }
            apply(isEnabled)
            if Bundle.main.bundleIdentifier == "app.navigy.Navigy" { syncStatus() }
            self.requiresApproval = LaunchAtLoginManager.readRequiresApproval()
        }
    }
    
    @Published public var requiresApproval: Bool
    
    /// Injectable login-item updater. The default registers/unregisters via SMAppService; tests
    /// inject a recording no-op so toggling never touches the real login-items registry. Assigned
    /// before `isEnabled` (whose `didSet` calls it) — the observer does not fire during init.
    private let apply: (Bool) -> Void
    private var syncing = false

    private static var usesSystemLoginItem: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier?.hasSuffix(".dev") != true
            && NSClassFromString("XCTestCase") == nil
    }

    private init() {
        self.apply = LaunchAtLoginManager.updateServiceStatus
        self.requiresApproval = LaunchAtLoginManager.readRequiresApproval()
        self.isEnabled = LaunchAtLoginManager.readCurrentStatus()
    }

    internal init(apply: @escaping (Bool) -> Void,
                  initialStatus: Bool = LaunchAtLoginManager.readCurrentStatus(),
                  requiresApproval: Bool = LaunchAtLoginManager.readRequiresApproval()) {
        self.apply = apply
        self.requiresApproval = requiresApproval
        self.isEnabled = initialStatus
    }
    
    public func syncStatus() {
        syncing = true
        defer { syncing = false }
        let enabled = Self.readCurrentStatus()
        let approval = Self.readRequiresApproval()
        if isEnabled != enabled { isEnabled = enabled }
        if requiresApproval != approval { requiresApproval = approval }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
    
    private static func readCurrentStatus() -> Bool {
        guard usesSystemLoginItem else { return DefaultSettingsStore.shared.get(.startAtLogin) }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private static func readRequiresApproval() -> Bool {
        usesSystemLoginItem && SMAppService.mainApp.status == .requiresApproval
    }

    private static func updateServiceStatus(_ enabled: Bool) {
        guard usesSystemLoginItem else {
            DefaultSettingsStore.shared.set(.startAtLogin, value: enabled)
            return
        }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            DefaultSettingsStore.shared.set(.startAtLogin, value: enabled)
        } catch {
            Log.settings.error("SMAppService failed to update launch at login status: \(error.localizedDescription)")
        }
    }
}
