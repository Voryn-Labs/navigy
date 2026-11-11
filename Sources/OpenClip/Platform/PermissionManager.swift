// PermissionManager.swift
// OpenClip
//
// Checks and prompts for required macOS Accessibility permissions necessary for text retrieval and event monitoring.
import AppKit
import ApplicationServices
import Core

@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    private var accessibilityRequest: Task<Void, Never>?

    private init() {
        self.isAccessibilityGranted = Self.queryAX()
    }

    // MARK: - Public API

    public func checkStatus() {
        let current = Self.queryAX()
        if isAccessibilityGranted != current {
            isAccessibilityGranted = current
            NotificationCenter.default.post(name: .openClipAccessibilityChanged, object: current)
        }
    }

    public func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func requestAccessibilityPermission() {
        promptAndOpenAccessibilitySettings()
        checkStatus()
        guard !isAccessibilityGranted, accessibilityRequest == nil else { return }
        accessibilityRequest = Task { @MainActor [weak self] in
            defer { self?.accessibilityRequest = nil }
            for _ in 0..<30 {
                do { try await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250)) }
                catch { return }
                guard let self else { return }
                self.checkStatus()
                if self.isAccessibilityGranted { return }
            }
        }
    }

    private func promptAndOpenAccessibilitySettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reset TCC permission database entry for OpenClip if macOS TCC is caching a stale signature.
    public func resetTCCAndRelaunch() {
        // Async: never `waitUntilExit` on the main actor. The app relaunches regardless.
        Task {
            do {
                _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
                    arguments: ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "app.navigy.Navigy"],
                    environment: [:]
                ))
            } catch {
                Log.permissions.error("Failed to run tccutil reset for Accessibility permission: \(error.localizedDescription)")
            }
            relaunchApp()
        }
    }

    /// Relaunch the app so macOS TCC registers the new permission for the running process.
    public func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Internal

    /// Direct TCC query — bypasses any in-process caching.
    private static func queryAX() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

}
