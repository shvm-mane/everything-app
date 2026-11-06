// SPDX-License-Identifier: GPL-3.0-or-later
// EVERYTHING's app delegate: starts the island, scratchpad, radial menu,
// spaces, mixer and brightness, and owns the one Settings window.
// EVERYTHING has no menu bar item: Settings opens from the island or by
// opening the app again.

import AppKit
import Combine
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var settingsWindow: NSWindow?
    private var settingsKeepsAppRegular = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppAppearanceController.shared.apply()
        GlobalShortcut.startObservingKeyboardLayout()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            // Everything: scratchpad reminders are gone; drop any still queued.
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        // Another app slow to answer an Accessibility question must not hold
        // this one still.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.35)
        LaunchAtLogin.repairAtStartup()
        BrightnessService.shared.restoreDisplaysLeftOff()
        installMainMenu()
        HorizontalWheelScrolling.install()

        // Only EVERYTHING's own features exist; each starts if it is on.
        FeatureRuntime.shared.syncAtLaunch()
        MainActor.assumeIsolated {
            SpaceSwitcher.shared.openSettings = { [weak self] in self?.openSettingsWindow() }
            SpaceSwitcher.shared.syncWithPreferences()
        }

        // A first launch opens Settings, where every permission is explained.
        if !UserDefaults.standard.bool(forKey: "everythingHasLaunched") {
            UserDefaults.standard.set(true, forKey: "everythingHasLaunched")
            DispatchQueue.main.async { [weak self] in self?.openSettingsWindow() }
        }

        // Opens the radial menu at the pointer, as the five-finger tap does;
        // for scripting and testing (`notifyutil`-style distributed post).
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.shvmane.everything.radialMenu"), object: nil, queue: .main) { _ in
            RadialMenuService.shared.toggleFromTrackpad()
        }

        // Launch reads logs, settings and images it then lets go of; give
        // those pages back once it has settled.
        MemoryRelief.soon(after: 10)

        // Accessibility granted while running brings the input features up.
        Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                MainActor.assumeIsolated { SpaceSwitcher.shared.syncWithPreferences() }
                PreciseVolumeRollerService.shared.syncWithPreferences()
                FeatureRuntime.shared.sync([.brightness, .radialMenu, .middleClick, .mixer, .notch])
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            WispIsland.shared.prepareToExit()
            SpaceSwitcher.shared.shutdown()
        }
        if AppFeature.notch.isAvailable { NotchService.shared.stop(restoreCapture: false) }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.restoreDisplaysBeforeTermination() }
        PreciseVolumeRollerService.shared.stop()
        AppVolumeMixer.shared.stopAll()
        AudioInputDeviceManager.shared.stop()
        MiddleClickService.shared.suspend()
        ScratchpadService.shared.suspend()
        SystemShortcutTakeover.restoreAll()
    }

    /// Opening the app again from Finder, Spotlight or Raycast shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettingsWindow() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Reminders and the island's notices may arrive while the app is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Compatibility with callers from Vorssaint's panel

    /// There is no menu bar popover; closing it only closes the island.
    func closePopover(animated: Bool = true, after delay: TimeInterval = 0,
                      preservingNotch: Bool = false, completion: (() -> Void)? = nil) {
        if !preservingNotch, NotchSupport.isEnabled() { NotchService.shared.collapse() }
        completion?()
    }

    var panelActivationSourcePID: pid_t? { nil }
    func isOverStatusItem(_ point: NSPoint) -> Bool { false }

    func relaunchApp() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Main menu

    /// An accessory app has no main menu, so the editing keys (⌘C, ⌘V, ⌘Z…)
    /// would do nothing in Settings and the scratchpad without this one.
    func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide EVERYTHING", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit EVERYTHING", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let window = NSMenu(title: "Window")
        windowItem.submenu = window
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = window
    }

    @objc private func menuOpenSettings() { openSettingsWindow() }

    // MARK: - Settings window

    private static let widthKey = "everythingSettingsWidth"
    private static let heightKey = "everythingSettingsHeight"

    func openSettingsWindow() {
        if settingsWindow == nil {
            // AppKit's sidebar split item: on macOS 26 and later it floats as
            // a Liquid Glass panel, and the page scrolls under the toolbar.
            let split = NSSplitViewController()
            let sidebarHost = NSHostingController(rootView: EverythingSettingsSidebar())
            sidebarHost.sizingOptions = []
            let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarHost)
            sidebar.minimumThickness = 180
            sidebar.maximumThickness = 230
            sidebar.canCollapse = false
            let detailHost = NSHostingController(rootView: EverythingSettingsDetail())
            detailHost.sizingOptions = []
            let detail = NSSplitViewItem(viewController: detailHost)
            detail.minimumThickness = 440
            split.addSplitViewItem(sidebar)
            split.addSplitViewItem(detail)
            let window = NSWindow(contentViewController: split)
            // A sidebar window: the sidebar runs under the title bar, as in
            // System Settings.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // A toolbar makes the window a modern sidebar window: the sidebar
            // floats as a Liquid Glass panel and the title sits in the bar.
            let toolbar = NSToolbar(identifier: "EverythingSettings")
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            let minimum = NSSize(width: EverythingSettingsView.minWidth, height: EverythingSettingsView.minHeight)
            window.contentMinSize = minimum
            let defaults = UserDefaults.standard
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let width = min(max(defaults.double(forKey: Self.widthKey), minimum.width + 60), visible.width - 40)
            let height = min(max(defaults.double(forKey: Self.heightKey), minimum.height + 80), visible.height - 40)
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.title = EverythingSettingsRouter.shared.pane.title
            EverythingSettingsRouter.shared.$pane
                .receive(on: DispatchQueue.main)
                .sink { [weak window] pane in window?.title = pane.title }
                .store(in: &cancellables)
            settingsWindow = window
        }
        if !settingsKeepsAppRegular {
            settingsKeepsAppRegular = true
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        MemoryRelief.soon()
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        if let size = window.contentView?.frame.size {
            UserDefaults.standard.set(Double(size.width), forKey: Self.widthKey)
            UserDefaults.standard.set(Double(size.height), forKey: Self.heightKey)
        }
        // Released on close: SwiftUI's settings pages hold no memory while shut.
        settingsWindow = nil
        if settingsKeepsAppRegular {
            settingsKeepsAppRegular = false
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
