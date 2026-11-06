// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics
import EventKit
import UserNotifications

final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    @Published private(set) var fullDiskAccess = false
    @Published private(set) var notifications: NotificationPermissionState = .unknown
    @Published private(set) var camera: CameraPermissionState = .unknown
    @Published private(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var requestingCalendar = false
    @Published private(set) var calendarRequestFailed = false
    private var calendarPermissionResolution: TimeInterval?

    var keepsCalendarPrompt: Bool {
        NotchSupport.keepsPermissionSurface(requesting: requestingCalendar,
                                            resolvedAt: calendarPermissionResolution,
                                            now: ProcessInfo.processInfo.systemUptime)
    }
    @Published private(set) var microphone: MicrophonePermissionState = .unknown

    enum NotificationPermissionState {
        case granted, denied, undetermined, unknown
    }

    enum CameraPermissionState {
        case granted, denied, undetermined, unknown
    }

    enum MicrophonePermissionState {
        case granted, denied, undetermined, unknown
    }

    private var activePermissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var permissionSurfaceDemands: Set<UUID> = []
    private var currentPollInterval: TimeInterval?

    private init() {
        refresh()
        scheduleActivePermissionPolling()
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
            self?.scheduleActivePermissionPolling()
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            self?.scheduleActivePermissionPolling()
        }
    }

    deinit {
        activePermissionTimer?.invalidate()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private var desiredPollInterval: TimeInterval? {
        let accessibilityIsNeeded = AppFeature.activeFeatures(using: .accessibility)
            .contains { $0.monitorsPermissionChanges }
        let screenRecordingIsNeeded = AppFeature.activeFeatures(using: .screenRecording)
            .contains { $0.monitorsPermissionChanges }
        return PermissionPollingSupport.interval(
            visibleSurfaceCount: permissionSurfaceDemands.count,
            accessibilityIsNeeded: accessibilityIsNeeded,
            screenRecordingIsNeeded: screenRecordingIsNeeded,
            accessibilityIsGranted: accessibility,
            screenRecordingIsGranted: screenRecording)
    }

    private func scheduleActivePermissionPolling() {
        let interval = desiredPollInterval
        guard interval != currentPollInterval else { return }
        currentPollInterval = interval
        activePermissionTimer?.invalidate()
        activePermissionTimer = nil
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshActivePermissions()
        }
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        activePermissionTimer = timer
    }

    func setActivePermissionSurface(_ id: UUID, visible: Bool) {
        if visible {
            permissionSurfaceDemands.insert(id)
            refreshActivePermissions()
        } else {
            permissionSurfaceDemands.remove(id)
        }
        scheduleActivePermissionPolling()
    }

    func refresh() {
        refreshActivePermissions()
        refreshNotificationPermission()
        refreshCameraPermission()
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        refreshMicrophonePermission()
        DispatchQueue.global(qos: .utility).async {
            let granted = Self.probeFullDiskAccess()
            DispatchQueue.main.async {
                if self.fullDiskAccess != granted { self.fullDiskAccess = granted }
            }
        }
    }

    private func refreshCameraPermission() {
        let state: CameraPermissionState
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: state = .granted
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .undetermined
        @unknown default: state = .unknown
        }
        DispatchQueue.main.async {
            if self.camera != state { self.camera = state }
        }
    }

    private func refreshMicrophonePermission() {
        let state: MicrophonePermissionState
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: state = .granted
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .undetermined
        @unknown default: state = .unknown
        }
        DispatchQueue.main.async {
            if self.microphone != state { self.microphone = state }
        }
    }

    private func refreshNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil,
              FileManager.default.fileExists(atPath: Bundle.main.bundlePath) else {
            if notifications != .unknown { notifications = .unknown }
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state: NotificationPermissionState
            switch settings.authorizationStatus {
            case .authorized, .provisional: state = .granted
            case .denied: state = .denied
            case .notDetermined: state = .undetermined
            @unknown default: state = .unknown
            }
            DispatchQueue.main.async {
                if self?.notifications != state { self?.notifications = state }
            }
        }
    }

    private func refreshActivePermissions() {
        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            if self.accessibility != ax { self.accessibility = ax }
            if self.screenRecording != sr { self.screenRecording = sr }
            self.scheduleActivePermissionPolling()
        }
    }

    private static let fdaGatedDirectories = [
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Cookies",
        "Library/Suggestions",
        "Library/Application Support/MobileSync",
    ]

    private static func probeFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        let tccDB = (home as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = FileHandle(forReadingAtPath: tccDB) {
            let ok = (try? handle.read(upToCount: 1)) != nil
            try? handle.close()
            if ok { return true }
        }

        let gatedDirs = fdaGatedDirectories.map { (home as NSString).appendingPathComponent($0) }
        return gatedDirs.contains { (try? fm.contentsOfDirectory(atPath: $0)) != nil }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshActivePermissions()
        if !accessibility {
            PermissionGuideOverlay.shared.show(for: .accessibility)
        }
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refreshActivePermissions()
        if !screenRecording {
            PermissionGuideOverlay.shared.show(for: .screenRecording)
        }
    }

    func startOver(_ kind: PermissionKind) {
        guard kind == .accessibility || kind == .screenRecording,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let service = kind == .accessibility ? "Accessibility" : "ScreenCapture"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Shell.run("/usr/bin/tccutil", ["reset", service, bundleID])
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshActivePermissions()
                if kind == .accessibility { self.requestAccessibility() } else { self.requestScreenRecording() }
            }
        }
    }

    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open(pane: "Privacy_ScreenCapture")
    }

    func openFullDiskAccessSettings() {
        open(pane: "Privacy_AllFiles")
    }

    func openFilesAndFoldersSettings() {
        open(pane: "Privacy_FilesAndFolders")
    }

    func requestFullDiskAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = NSHomeDirectory()
            let fm = FileManager.default
            let tccDB = (home as NSString)
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            _ = try? Data(contentsOf: URL(fileURLWithPath: tccDB), options: .mappedIfSafe)
            if let handle = FileHandle(forReadingAtPath: tccDB) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
            }
            let dirs = (["Library/Application Support/com.apple.TCC"] + Self.fdaGatedDirectories)
                .map { (home as NSString).appendingPathComponent($0) }
            for path in dirs { _ = try? fm.contentsOfDirectory(atPath: path) }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.openFullDiskAccessSettings()
            }
        }
    }

    func requestCalendar() {
        guard !requestingCalendar else { return }
        requestingCalendar = true
        calendarRequestFailed = false
        let store = EKEventStore()
        store.requestFullAccessToEvents { [weak self, store] _, error in
            _ = store
            DispatchQueue.main.async {
                self?.calendarPermissionResolution = ProcessInfo.processInfo.systemUptime
                self?.requestingCalendar = false
                let status = EKEventStore.authorizationStatus(for: .event)
                self?.calendarRequestFailed = NotchCalendarSupport.requestFailed(status: status, hasError: error != nil)
                self?.calendarAccess = status
            }
        }
    }

    func openCalendarSettings() {
        open(pane: "Privacy_Calendars")
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func requestMicrophone(completion: ((Bool) -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphone = granted ? .granted : .denied
                completion?(granted)
            }
        }
    }

    func openCameraSettings() {
        open(pane: "Privacy_Camera")
    }

    func openMicrophoneSettings() {
        open(pane: "Privacy_Microphone")
    }

    func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    func openAutomationSettings() {
        open(pane: "Privacy_Automation")
    }

    func openAudioCaptureSettings() {
        open(pane: "Privacy_AudioCapture")
    }

    func openAppManagementSettings() {
        let pane = URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles")!
        if NSWorkspace.shared.open(pane) { return }

        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(fallback)
    }

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Automation (Apple Events)

    enum AutomationTarget: String, CaseIterable {
        case finder = "com.apple.finder"
    }

    enum AutomationStatus {
        case granted, denied, undetermined, notDeterminable
    }

    static func automationStatus(for target: AutomationTarget) -> AutomationStatus {
        var descriptor = AEAddressDesc()
        let bundleID = target.rawValue
        let created = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &descriptor)
        }
        guard created == noErr else { return .notDeterminable }
        defer { AEDisposeDesc(&descriptor) }
        switch AEDeterminePermissionToAutomateTarget(&descriptor, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .undetermined
        default: return .notDeterminable
        }
    }
}
