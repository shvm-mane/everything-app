// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    @Published private(set) var fullScreenShortcutRegistrationFailed = false
    @Published private(set) var lastCaptureShortcutRegistrationFailed = false
    @Published private(set) var clipboardShortcutRegistrationFailed = false

    @Published private(set) var uploadShortcutRegistrationFailed = false
    private let uploadHotkey = QuickToolHotkey(id: 61)
    private var uploadingCaptureID: UUID?
    private var latestCaptureID = UUID()
    private var latestCaptureToken = UUID()
    private var latestCaptureWithheld = false
    private var linkCopyRetry = ScreenshotLinkCopyRetry()

    private let lastCaptureHotkey = QuickToolHotkey(id: 22)
    private let fullScreenHotkey = QuickToolHotkey(id: 23)
    private let clipboardHotkey = QuickToolHotkey(id: 24)
    private var session: ScreenshotSelectionController?
    private var preview: ScreenshotQuickPreviewController?
    private var editors: [ScreenshotEditorController] = []
    private var countdown: DispatchWorkItem?
    private var countdownRemaining = 0
    private var countdownMode: CaptureMode = .standard
    private var directCaptureTask: Task<Void, Never>?
    private var autoCopyTask: Task<Void, Never>?
    private var autoCopyGeneration = 0
    private var autoShelfTasks: [UUID: Task<Void, Never>] = [:]
    private var autoShelvedItem: (capture: UUID, item: UUID)?
    private var scrollingTask: Task<Void, Never>?
    private var scrollingCaptureID: UUID?
    private var scrollingFinishSignal: ScreenshotScrollingCapture.FinishSignal?

    private enum CaptureMode {
        case standard
        case fullScreen
        case scrolling
    }

    private var hideVorssaintWindows: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.screenshotHideVorssaintWindows)
    }

    private var workflowWindowIDs: Set<CGWindowID> {
        var ids = session?.protectedWindowIDs ?? []
        if NotchSupport.isEnabled() { ids.formUnion(NotchService.shared.protectedWindowIDs) }
        ids.formUnion(preview?.protectedWindowIDs ?? [])
        ids.formUnion(ScreenCaptureService.shared.protectedWindowIDs)
        if let number = QuickToolHUD.currentWindowNumber, number > 0 {
            ids.insert(CGWindowID(number))
        }
        if let number = QuickToolHUD.currentScrollingWindowNumber, number > 0 {
            ids.insert(CGWindowID(number))
        }
        return ids
    }

    private var contentWindowIDs: Set<CGWindowID> {
        var ids: Set<CGWindowID> = []
        for editor in editors {
            ids.formUnion(editor.protectedWindowIDs)
        }
        ids.formUnion(ScreenshotPinController.shared.protectedWindowIDs)
        return ids
    }

    private var protectedWindowIDs: Set<CGWindowID> {
        protectedWindowIDsForCapture(honoursVisibilityPreference: true)
    }

    func protectedWindowIDsForCapture(honoursVisibilityPreference: Bool) -> Set<CGWindowID> {
        ScreenshotCapturePolicy.protectedWindowIDs(
            workflowWindowIDs: workflowWindowIDs,
            contentWindowIDs: contentWindowIDs,
            honoursVisibilityPreference: honoursVisibilityPreference)
    }

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    private init() {
        DispatchQueue.global(qos: .utility).async {
            ScreenshotSupport.removeTemporaryDragDirectories()
        }
        fullScreenHotkey.onPress = { [weak self] in self?.captureFullScreen() }
        lastCaptureHotkey.onPress = { [weak self] in self?.openLastCapture() }
        uploadHotkey.onPress = { [weak self] in
            Task { @MainActor [weak self] in self?.uploadLastCapture() }
        }
        clipboardHotkey.onPress = { [weak self] in self?.openClipboardImage() }
    }

    func syncWithPreferences() {
        guard AppFeature.screenshot.isAvailable else {
            fullScreenShortcutRegistrationFailed = false
            lastCaptureShortcutRegistrationFailed = false
            clipboardShortcutRegistrationFailed = false
            uploadShortcutRegistrationFailed = false
            fullScreenHotkey.unregister()
            lastCaptureHotkey.unregister()
            clipboardHotkey.unregister()
            uploadHotkey.unregister()
            ScreenshotLastCaptureStore.clear()
            teardownSurfaces()
            return
        }
        let defaults = UserDefaults.standard
        let fullScreenEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotFullScreenShortcutEnabled)
        let fullScreenShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotFullScreenShortcut,
            fallback: .screenshotFullScreenDefault)
        fullScreenShortcutRegistrationFailed = !fullScreenHotkey.sync(
            enabled: fullScreenEnabled,
            shortcut: fullScreenShortcut,
            storageKey: DefaultsKey.screenshotFullScreenShortcut)
        let lastCaptureEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
        let lastCaptureShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotLastCaptureShortcut,
            fallback: .screenshotLastCaptureDefault)
        lastCaptureShortcutRegistrationFailed = !lastCaptureHotkey.sync(
            enabled: lastCaptureEnabled,
            shortcut: lastCaptureShortcut,
            storageKey: DefaultsKey.screenshotLastCaptureShortcut)
        let clipboardEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotClipboardShortcutEnabled)
        let clipboardShortcut = GlobalShortcut.saved(
            for: DefaultsKey.screenshotClipboardShortcut,
            fallback: .screenshotClipboardDefault)
        clipboardShortcutRegistrationFailed = !clipboardHotkey.sync(
            enabled: clipboardEnabled,
            shortcut: clipboardShortcut,
            storageKey: DefaultsKey.screenshotClipboardShortcut)
        uploadShortcutRegistrationFailed = !uploadHotkey.sync(
            enabled: ScreenshotSharingSupport.uploadShortcutEnabled(in: defaults),
            shortcut: GlobalShortcut.saved(for: DefaultsKey.screenshotUploadShortcut,
                                           fallback: .screenshotUploadDefault),
            storageKey: DefaultsKey.screenshotUploadShortcut)
        syncLatestCapture(with: defaults)
    }

    private func syncLatestCapture(with defaults: UserDefaults) {
        if !ScreenshotSharingSupport.uploadShortcutEnabled(in: defaults) {
            invalidateLatestCaptureUploads()
        }
        if !ScreenshotSharingSupport.retainsLatestCapture(in: defaults) {
            ScreenshotLastCaptureStore.clear()
        }
    }

    func suspend() {
        fullScreenHotkey.unregister()
        lastCaptureHotkey.unregister()
        clipboardHotkey.unregister()
        uploadHotkey.unregister()
    }

    private func teardownSurfaces() {
        countdown?.cancel()
        countdown = nil
        directCaptureTask?.cancel()
        directCaptureTask = nil
        autoCopyTask?.cancel()
        autoCopyTask = nil
        autoCopyGeneration += 1
        cancelAutoShelf()
        scrollingTask?.cancel()
        scrollingTask = nil
        scrollingCaptureID = nil
        scrollingFinishSignal = nil
        QuickToolHUD.dismissScrollingCapture()
        session?.cancel()
        session = nil
        invalidateLatestCaptureUploads()
        preview?.close()
        preview = nil
        for editor in editors {
            editor.close()
        }
        editors.removeAll()
        ScreenshotPinController.shared.closeAll()
    }

    // MARK: - Entry

    func capture() {
        ScreenCaptureService.shared.capture(initial: .screenshot)
    }

    func captureScrolling() {
        startCapture(.scrolling)
    }

    func captureFullScreen() {
        startCapture(.fullScreen)
    }

    private func startCapture(_ mode: CaptureMode) {
        if scrollingTask != nil {
            QuickToolHUD.markScrollingCaptureFinishing()
            scrollingFinishSignal?.request()
            return
        }
        guard session == nil, directCaptureTask == nil,
              !ScreenshotSelectionController.isSessionOnScreen else { return }
        if countdown != nil {
            countdown?.cancel()
            countdown = nil
            return
        }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        let delay = ScreenshotSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.screenshotDelay))
        if delay > 0 {
            countdownMode = mode
            countdownRemaining = delay
            tickCountdown()
        } else {
            beginCapture(mode)
        }
    }

    private func tickCountdown() {
        guard countdownRemaining > 0 else {
            let mode = countdownMode
            countdown = nil
            beginCapture(mode)
            return
        }
        QuickToolHUD.showCountdown(countdownRemaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countdownRemaining -= 1
            self.tickCountdown()
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func beginCapture(_ mode: CaptureMode) {
        if mode == .fullScreen {
            beginFullScreenCapture()
        } else {
            beginSelection(mode)
        }
    }

    private func beginSelection(_ mode: CaptureMode) {
        guard session == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        preview?.close()
        preview = nil
        let defaults = UserDefaults.standard
        let controller = ScreenshotSelectionController(
            freeze: mode == .scrolling
                ? false
                : defaults.bool(forKey: DefaultsKey.screenshotFreeze),
            includePointer: defaults.bool(forKey: DefaultsKey.screenshotIncludePointer),
            showLastRegion: defaults.bool(forKey: DefaultsKey.screenshotShowLastRegion),
            hideVorssaintWindows: hideVorssaintWindows,
            protectedWindowIDs: { [weak self] in self?.protectedWindowIDs ?? [] },
            purpose: mode == .scrolling ? strings.scrollingCaptureTitle : nil,
            mode: mode == .scrolling ? .geometry : .image,
            supportsScrollingCapture: mode == .standard)
        session = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.session = nil
            switch outcome {
            case .captured(let capture):
                self.route(capture)
            case .region(let region):
                guard mode == .scrolling else { break }
                self.captureScrolling(region)
            case .scrollingRegion(let region):
                self.captureScrolling(region)
            case .color:
                break
            case .cancelled:
                break
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    func receiveUnifiedCapture(_ capture: ScreenshotSelectionController.Capture) {
        route(capture)
    }

    func receiveUnifiedScrollingRegion(_ region: RecorderSupport.Region) {
        captureScrolling(region)
    }

    private func beginFullScreenCapture() {
        guard directCaptureTask == nil, !ScreenshotSelectionController.isSessionOnScreen else {
            return
        }
        preview?.close()
        preview = nil
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                ?? NSScreen.main,
              screen.displayID != 0 else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.captureFailed)
            return
        }
        let displayID = screen.displayID
        let scale = screen.backingScaleFactor
        let frame = screen.frame
        let includePointer = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotIncludePointer)
        let hideWindows = hideVorssaintWindows
        let protectedIDs = protectedWindowIDs
        directCaptureTask = Task { @MainActor [weak self] in
            let image = await ScreenshotCaptureEngine.captureDisplay(
                displayID,
                includePointer: includePointer,
                hideVorssaintWindows: hideWindows,
                protectedWindowIDs: protectedIDs)
            guard let self, !Task.isCancelled else { return }
            self.directCaptureTask = nil
            guard let image else {
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
                return
            }
            self.route(ScreenshotSelectionController.Capture(
                image: image,
                scale: scale,
                anchorRect: frame))
        }
    }

    private func captureScrolling(_ region: RecorderSupport.Region) {
        guard scrollingTask == nil else { return }
        let finishSignal = ScreenshotScrollingCapture.FinishSignal()
        scrollingFinishSignal = finishSignal
        QuickToolHUD.showScrollingCapture(
            message: strings.scrollingCaptureProgressHUD,
            finishTitle: strings.done,
            cancelTitle: strings.cancel,
            onFinish: { finishSignal.request() },
            onCancel: { [weak self] in self?.scrollingTask?.cancel() })
        let hideWindows = hideVorssaintWindows
        let protectedIDs = protectedWindowIDs
        let captureID = UUID()
        scrollingCaptureID = captureID
        scrollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await ScreenshotScrollingCapture.capture(
                region: region,
                includePointer: false,
                hideVorssaintWindows: hideWindows,
                protectedWindowIDs: protectedIDs,
                finishSignal: finishSignal,
                onProgress: { height in
                    QuickToolHUD.updateScrollingCapture(height: height)
                })
            guard self.scrollingCaptureID == captureID else { return }
            self.scrollingCaptureID = nil
            self.scrollingTask = nil
            self.scrollingFinishSignal = nil
            QuickToolHUD.dismissScrollingCapture()
            switch result {
            case .success(let capture):
                self.route(capture)
            case .partial(let capture):
                self.route(capture)
                QuickToolHUD.show(icon: "rectangle.stack",
                                  message: self.strings.scrollingCapturePartialHUD)
            case .limited(let capture):
                self.route(capture)
                QuickToolHUD.show(icon: "rectangle.stack",
                                  message: self.strings.scrollingCaptureTooLongHUD)
            case .cancelled:
                QuickToolHUD.show(icon: "xmark", message: L10n.shared.s.mediaCancelled)
            case .failed:
                QuickToolHUD.show(icon: "camera.viewfinder", message: self.strings.captureFailed)
            }
        }
    }

    // MARK: - Routing

    private struct SaveOutcome {
        let url: URL
        let consumedNumber: Int?
    }

    private struct AutomaticActionResult {
        let performed: Set<ScreenshotQuickPreviewController.Action>
        let saved: SaveOutcome?
    }

    private func route(_ capture: ScreenshotSelectionController.Capture) {
        beginLatestCapture(capture)
        NotchService.shared.reactMascot(.flash, patience: 1)
        preview?.close()
        RecentCaptureService.shared.recordScreenshot(capture)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.screenshotCopyToClipboard) {
            autoCopy(capture)
        }
        let defaultAction = ScreenshotDefaultAction.current
        if defaultAction == .edit {
            openEditor(with: capture)
            return
        }
        let result = runDefaultAction(defaultAction, capture: capture)
        autoShelve(capture, saved: result.saved?.url)
        guard case .shown(let dismissInterval) = ScreenshotSupport.quickPreviewPresentation(
            defaultAction: defaultAction,
            saved: result.saved != nil,
            copied: result.performed.contains(.copy),
            defaults: defaults)
        else { return }
        presentPreview(capture,
                       defaultAction: defaultAction,
                       initialSaved: result.saved,
                       completedActions: result.performed,
                       dismissInterval: dismissInterval,
                       latestCapture: latestCaptureToken)
    }

    private func discardLatestCapture(_ latestCapture: UUID?) {
        guard let latestCapture, latestCapture == latestCaptureToken else { return }
        withholdLatestCapture()
    }

    private func unshelve(_ capture: UUID?) {
        guard let capture else { return }
        autoShelfTasks.removeValue(forKey: capture)?.cancel()
        if let shelved = autoShelvedItem, shelved.capture == capture {
            ShelfService.shared.removeItem(shelved.item)
            autoShelvedItem = nil
        }
    }

    private func editFromPreview(_ capture: ScreenshotSelectionController.Capture, latestCapture: UUID?) {
        unshelve(latestCapture)
        openEditor(with: capture)
    }

    private func cancelAutoShelf() {
        for task in autoShelfTasks.values { task.cancel() }
        autoShelfTasks.removeAll()
    }

    private func withholdLatestCapture() {
        invalidateLatestCaptureUploads()
        latestCaptureWithheld = true
        ScreenshotLastCaptureStore.withhold()
    }

    private func beginLatestCapture(_ capture: ScreenshotSelectionController.Capture) {
        invalidateLatestCaptureUploads()
        latestCaptureToken = UUID()
        latestCaptureWithheld = false
        if ScreenshotSharingSupport.retainsLatestCapture() {
            ScreenshotLastCaptureStore.save(capture)
        }
    }

    func restorePreview(_ capture: ScreenshotSelectionController.Capture) {
        preview?.close()
        presentPreview(capture,
                       defaultAction: .none,
                       initialSaved: nil,
                       completedActions: [],
                       dismissInterval: ScreenshotSupport.recoveryPreviewDismissInterval,
                       latestCapture: nil)
    }

    private func presentPreview(_ capture: ScreenshotSelectionController.Capture,
                                defaultAction: ScreenshotDefaultAction,
                                initialSaved: SaveOutcome?,
                                completedActions: Set<ScreenshotQuickPreviewController.Action>,
                                dismissInterval: TimeInterval?,
                                latestCapture: UUID?) {
        var saved = initialSaved
        let controller = ScreenshotQuickPreviewController(
            capture: capture,
            strings: strings,
            defaultAction: defaultAction,
            completedActions: completedActions,
            dismissInterval: dismissInterval,
            action: { [weak self] action in
                guard let self else { return [] }
                switch action {
                case .edit:
                    self.editFromPreview(capture, latestCapture: latestCapture)
                    return [.edit]
                case .pin:
                    ScreenshotPinController.shared.pin(image: capture.image, scale: capture.scale)
                    return [.pin]
                case .copy:
                    return self.copyDirect(capture) ? [.copy] : []
                case .save:
                    guard let outcome = self.saveDirect(capture) else { return [] }
                    saved = outcome
                    return [.save]
                case .saveAndCopy:
                    guard let result = self.saveAndCopyDirect(capture) else { return [] }
                    saved = result.outcome
                    return result.copied ? [.save, .copy] : [.save]
                case .discard:
                    if let saved {
                        try? FileManager.default.trashItem(at: saved.url,
                                                           resultingItemURL: nil)
                        if let consumed = saved.consumedNumber {
                            Self.rewindNumberSequence(toReuse: consumed)
                        }
                    }
                    self.unshelve(latestCapture)
                    self.discardLatestCapture(latestCapture)
                    return [.discard]
                }
            },
            share: { [weak self] duration, completion in
                guard let self else {
                    Task { @MainActor in completion(nil) }
                    return
                }
                self.shareDirect(capture, duration: duration, completion: completion)
            },
            shareFile: { [weak self] in
                guard let self, let export = self.flatten(capture) else { return nil }
                return Self.temporaryExportFile(image: export.image, scale: export.scale,
                                                strings: self.strings)
            },
            onClose: { [weak self] in self?.preview = nil })
        preview = controller
        controller.show()
    }

    private func runDefaultAction(_ defaultAction: ScreenshotDefaultAction,
                                  capture: ScreenshotSelectionController.Capture)
        -> AutomaticActionResult {
        switch defaultAction {
        case .none, .edit:
            return AutomaticActionResult(performed: [], saved: nil)
        case .copy:
            return AutomaticActionResult(
                performed: copyDirect(capture) ? [.copy] : [],
                saved: nil)
        case .save:
            guard let outcome = saveDirect(capture) else {
                return AutomaticActionResult(performed: [], saved: nil)
            }
            return AutomaticActionResult(performed: [.save], saved: outcome)
        case .saveAndCopy:
            guard let result = saveAndCopyDirect(capture) else {
                return AutomaticActionResult(performed: [], saved: nil)
            }
            return AutomaticActionResult(
                performed: result.copied ? [.save, .copy] : [.save],
                saved: result.outcome)
        }
    }

    func openEditor(with capture: ScreenshotSelectionController.Capture) {
        WindowActivationPolicy.retain()
        withholdLatestCapture()
        let editor = ScreenshotEditorController(capture: capture)
        editors.append(editor)
        editor.show()
    }

    @MainActor
    private func uploadLastCapture() {
        guard AppFeature.screenshot.isAvailable,
              ScreenshotSharingSupport.uploadShortcutEnabled() else { return }
        if let preview {
            preview.shareLink()
            return
        }
        guard editors.isEmpty, !latestCaptureWithheld, !ScreenshotLastCaptureStore.isWithheld else {
            NSSound.beep()
            return
        }
        guard uploadingCaptureID != latestCaptureID else { return }
        if let record = linkCopyRetry.record(for: latestCaptureID,
                                             availableRecords: ScreenshotShareService.shared.records) {
            copyUploadedLink(record, captureID: latestCaptureID)
            return
        }
        guard let capture = ScreenshotLastCaptureStore.load() else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.lastCaptureMissing)
            return
        }
        let captureID = latestCaptureID
        uploadingCaptureID = captureID
        QuickToolHUD.show(icon: "link", message: strings.sharingHUD)
        shareDirect(capture, duration: .saved()) { [weak self] record in
            if self?.uploadingCaptureID == captureID { self?.uploadingCaptureID = nil }
            guard let record else { return }
            guard let self,
                  self.latestCaptureID == captureID else {
                Task { @MainActor in
                    try? await ScreenshotShareService.shared.delete(record)
                }
                return
            }
            self.copyUploadedLink(record, captureID: captureID)
        }
    }

    private func invalidateLatestCaptureUploads() {
        latestCaptureID = UUID()
        linkCopyRetry.clear()
    }

    @MainActor
    private func copyUploadedLink(_ record: ScreenshotShareRecord, captureID: UUID) {
        let copied = ScreenshotSharingSupport.copyLink(
            record, using: ScreenshotShareService.shared.copy,
            dismiss: {})
        if captureID == latestCaptureID {
            if copied {
                linkCopyRetry.clear()
            } else {
                linkCopyRetry.remember(record, for: captureID)
            }
        }
        QuickToolHUD.show(icon: "link", message: copied
            ? strings.sharedHUD : strings.linkCopyFailedHUD)
    }

    private func openLastCapture() {
        guard let capture = ScreenshotLastCaptureStore.load() else {
            QuickToolHUD.show(icon: "camera.viewfinder", message: strings.lastCaptureMissing)
            return
        }
        preview?.close()
        preview = nil
        unshelve(latestCaptureToken)
        openEditor(with: capture)
    }

    private func openClipboardImage() {
        GeneralPasteboardAccess.shared.async { [weak self] in
            let capture = autoreleasepool {
                Self.clipboardCapture(from: NSPasteboard.general)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, AppFeature.screenshot.isAvailable else { return }
                guard let capture else {
                    QuickToolHUD.show(icon: "photo", message: self.strings.clipboardImageMissing)
                    return
                }
                self.openEditor(with: capture)
            }
        }
    }

    func editImage(at url: URL) {
        guard AppFeature.screenshot.isAvailable else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let capture = autoreleasepool {
                NSImage(contentsOf: url).flatMap { Self.imageCapture(from: $0) }
            }
            DispatchQueue.main.async {
                guard AppFeature.screenshot.isAvailable else { return }
                guard let capture else {
                    NSSound.beep()
                    return
                }
                NotchService.shared.perform {
                    ScreenshotService.shared.openEditor(with: capture)
                }
            }
        }
    }

    private static func clipboardCapture(
        from pasteboard: NSPasteboard
    ) -> ScreenshotSelectionController.Capture? {
        guard let image = clipboardImage(from: pasteboard) else { return nil }
        return imageCapture(from: image)
    }

    static func imageCapture(from image: NSImage) -> ScreenshotSelectionController.Capture? {
        guard image.size.width > 0, image.size.height > 0
        else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= ScreenshotSupport.scrollingCaptureMaximumPixels / cgImage.height
        else { return nil }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = ScreenshotSupport.clipboardImageScale(pixelSize: pixelSize,
                                                          pointSize: image.size)
        return ScreenshotSelectionController.Capture(image: cgImage,
                                                     scale: scale,
                                                     anchorRect: .zero)
    }

    static func clipboardImage(from pasteboard: NSPasteboard) -> NSImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: options) as? [NSURL])?.first as URL?,
           let image = NSImage(contentsOf: url),
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        return NSImage(pasteboard: pasteboard)
    }

    func editorDidClose(_ editor: ScreenshotEditorController) {
        guard editors.contains(where: { $0 === editor }) else { return }
        editors.removeAll { $0 === editor }
        WindowActivationPolicy.release()
    }

    private func autoCopy(_ capture: ScreenshotSelectionController.Capture) {
        let downscale = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale)
        let imageOnly = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotCopyImageOnly)
        let folder = imageOnly ? nil : ScreenshotSupport.copiedFilesDirectory()
        guard imageOnly || folder != nil else {
            NSSound.beep()
            return
        }
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        autoCopyTask?.cancel()
        autoCopyGeneration += 1
        let generation = autoCopyGeneration
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        autoCopyTask = Task { @MainActor [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
                guard let export = Self.flatten(capture, downscaleTo1x: downscale) else {
                    return nil as (URL?, ScreenshotEditorController.ClipboardPayload)?
                }
                let payload = ScreenshotEditorController.clipboardPayload(from: export)
                guard let png = payload.png else { return nil }
                if imageOnly { return (nil, payload) }
                guard let folder, let url = try? ScreenshotSupport.copiedFile(
                        data: png, name: name, directory: folder) else { return nil }
                return (url, payload)
            }.value
            guard let output else {
                if !Task.isCancelled { NSSound.beep() }
                return
            }
            guard let self, !Task.isCancelled,
                  generation == self.autoCopyGeneration,
                  pasteboardChangeCount == NSPasteboard.general.changeCount,
                  AppFeature.screenshot.isAvailable
            else {
                if let url = output.0 { try? FileManager.default.removeItem(at: url) }
                return
            }
            guard ScreenshotEditorController.copyFile(output.0, payload: output.1,
                                                       imageOnly: imageOnly)
            else {
                if let url = output.0 { try? FileManager.default.removeItem(at: url) }
                NSSound.beep()
                return
            }
            if let folder, let url = output.0 {
                ScreenshotSupport.pruneCopiedFiles(in: folder, preserving: url)
            }
            self.autoCopyTask = nil
        }
    }

    func afterAutoCopy(_ body: @escaping () -> Void) {
        guard let pending = autoCopyTask else {
            body()
            return
        }
        Task { @MainActor in
            await pending.value
            body()
        }
    }

    private func autoShelve(_ capture: ScreenshotSelectionController.Capture, saved: URL?) {
        autoShelvedItem = nil
        guard ScreenshotSupport.addsCapturesToShelf() else { return }
        let token = latestCaptureToken
        let downscale = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale)
        let name = saved?.lastPathComponent
            ?? ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        autoShelfTasks[token] = Task { @MainActor [weak self] in
            let work = Task.detached(priority: .userInitiated) { () -> Data? in
                guard !Task.isCancelled else { return nil }
                if let saved { return try? Data(contentsOf: saved) }
                guard let export = Self.flatten(capture, downscaleTo1x: downscale),
                      !Task.isCancelled else { return nil }
                return ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            }
            let png = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard let self else { return }
            self.autoShelfTasks[token] = nil
            guard !Task.isCancelled, AppFeature.screenshot.isAvailable,
                  ScreenshotSupport.addsCapturesToShelf() else { return }
            guard let png, let item = ShelfService.shared.shelveGeneratedFile(png, named: name) else {
                NSSound.beep()
                return
            }
            if self.latestCaptureToken == token {
                self.autoShelvedItem = (token, item)
            }
        }
    }

    private func shareDirect(_ capture: ScreenshotSelectionController.Capture,
                             duration: ScreenshotShareDuration,
                             completion: @escaping @MainActor (ScreenshotShareRecord?) -> Void) {
        let downscale = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale)
        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                guard let export = Self.flatten(capture, downscaleTo1x: downscale) else {
                    return nil as Data?
                }
                return ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            }.value
            guard let data else {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                completion(nil)
                return
            }
            do {
                let record = try await ScreenshotShareService.shared.createLink(
                    pngData: data, duration: duration)
                completion(record)
            } catch {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                NSSound.beep()
                completion(nil)
            }
        }
    }

    @discardableResult
    private func copyDirect(_ capture: ScreenshotSelectionController.Capture) -> Bool {
        guard let export = flatten(capture) else { return false }
        guard ScreenshotEditorController.copyImage(
            export, fileNamePrefix: strings.fileNamePrefix) else {
            NSSound.beep()
            return false
        }
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        return true
    }

    private func saveDirect(_ capture: ScreenshotSelectionController.Capture) -> SaveOutcome? {
        guard let export = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return nil }
        let (url, consumedNumber) = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            ScreenshotSupport.markAsScreenCapture(url)
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            return SaveOutcome(url: url, consumedNumber: consumedNumber)
        } catch {
            if let consumedNumber {
                Self.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
            return nil
        }
    }

    private func saveAndCopyDirect(_ capture: ScreenshotSelectionController.Capture)
        -> (outcome: SaveOutcome, copied: Bool)? {
        guard let export = flatten(capture),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return nil }
        let (url, consumedNumber) = Self.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            ScreenshotSupport.markAsScreenCapture(url)
        } catch {
            if let consumedNumber {
                Self.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
            return nil
        }

        let copied = ScreenshotEditorController.copyFile(
            url, payload: ScreenshotEditorController.clipboardPayload(from: export, png: data))
        let format = copied ? strings.savedAndCopiedHUDFormat : strings.savedHUDFormat
        QuickToolHUD.show(icon: "camera.viewfinder",
                          message: String(format: format,
                                          url.deletingLastPathComponent().lastPathComponent))
        return (SaveOutcome(url: url, consumedNumber: consumedNumber), copied)
    }

    private func flatten(_ capture: ScreenshotSelectionController.Capture)
        -> ScreenshotRenderer.Export? {
        Self.flatten(
            capture,
            downscaleTo1x: UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale))
    }

    private static func flatten(_ capture: ScreenshotSelectionController.Capture,
                                downscaleTo1x: Bool) -> ScreenshotRenderer.Export? {
        ScreenshotRenderer.renderExport(
            baseImage: capture.image,
            annotations: [],
            blurSources: .none,
            scale: capture.scale,
            annotationShadowsEnabled: false,
            watermark: ScreenshotSupport.WatermarkStyle(),
            watermarkImage: nil,
            style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
            fill: .none,
            downscaleTo1x: downscaleTo1x)
    }

    static func dragItemProvider(image: CGImage,
                                 scale: CGFloat,
                                 strings: ScreenshotFeatureStrings) -> NSItemProvider? {
        guard let url = temporaryExportFile(image: image, scale: scale, strings: strings) else {
            return nil
        }
        guard let provider = NSItemProvider(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            return nil
        }
        return provider
    }

    static func temporaryExportFile(image: CGImage,
                                    scale: CGFloat,
                                    strings: ScreenshotFeatureStrings) -> URL? {
        guard let data = ScreenshotRenderer.pngData(from: image, scale: scale) else {
            return nil
        }
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        guard let url = try? ScreenshotSupport.temporaryDragFile(data: data, name: name) else {
            return nil
        }
        let folder = url.deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60 * 60) {
            try? FileManager.default.removeItem(at: folder)
        }
        return url
    }

    // MARK: - Save location

    static func saveDestination(strings: ScreenshotFeatureStrings) -> (url: URL, consumedNumber: Int?) {
        let manager = FileManager.default
        var folder: URL?
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.screenshotSaveFolder) ?? ""
        if !stored.isEmpty {
            let expanded = (stored as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folder = URL(fileURLWithPath: expanded)
            }
        }
        var destination = folder
            ?? manager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
        let subfolderPattern = UserDefaults.standard.string(forKey: DefaultsKey.screenshotSaveSubfolder) ?? ""
        let subfolder = ScreenshotSupport.expandSaveSubfolder(subfolderPattern, date: Date())
        if !subfolder.isEmpty {
            let dated = destination.appendingPathComponent(subfolder, isDirectory: true)
            if (try? manager.createDirectory(at: dated, withIntermediateDirectories: true)) != nil {
                destination = dated
            }
        }
        let (name, consumedNumber) = Self.fileName(strings: strings)
        let unique = ScreenshotSupport.uniqueFileName(name) { candidate in
            manager.fileExists(atPath: destination.appendingPathComponent(candidate).path)
        }
        return (destination.appendingPathComponent(unique), consumedNumber)
    }

    private static func fileName(strings: ScreenshotFeatureStrings) -> (name: String, consumedNumber: Int?) {
        let defaults = UserDefaults.standard
        let pattern = (defaults.string(forKey: DefaultsKey.screenshotFileNamePattern) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return (ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date()), nil)
        }

        if ScreenshotSupport.fileNamePatternUsesNumber(pattern) {
            let number = defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext)
            let expanded = ScreenshotSupport.expandFileNamePattern(pattern, date: Date(), number: number)
            defaults.set(number + 1, forKey: DefaultsKey.screenshotFileNumberNext)
            return (expanded + ".png", number)
        } else {
            let expanded = ScreenshotSupport.expandFileNamePattern(pattern, date: Date(), number: 0)
            return (expanded + ".png", nil)
        }
    }

    static func rewindNumberSequence(toReuse consumed: Int) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: DefaultsKey.screenshotFileNumberNext) == consumed + 1 else {
            return
        }
        defaults.set(consumed, forKey: DefaultsKey.screenshotFileNumberNext)
    }
}

enum ScreenshotLastCaptureStore {
    private static let writeQueue = DispatchQueue(
        label: "com.vorssaint.utils.latest-screenshot",
        qos: .utility)
    private static let stateLock = NSLock()
    private static var generation = 0
    private static var pendingCapture: ScreenshotSelectionController.Capture?

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("LatestScreenshot.png")
    }

    private static var withheldURL: URL? {
        fileURL?.deletingLastPathComponent().appendingPathComponent("LatestScreenshot.withheld")
    }

    static var isWithheld: Bool {
        guard let withheldURL else { return false }
        return FileManager.default.fileExists(atPath: withheldURL.path)
    }

    static func withhold() {
        guard let withheldURL else { return }
        try? FileManager.default.createDirectory(at: withheldURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: withheldURL.path, contents: nil)
    }

    static func save(_ capture: ScreenshotSelectionController.Capture) {
        guard let fileURL else { return }
        if let withheldURL { try? FileManager.default.removeItem(at: withheldURL) }
        stateLock.lock()
        generation += 1
        let operation = generation
        pendingCapture = capture
        stateLock.unlock()

        writeQueue.async {
            guard let data = ScreenshotRenderer.pngData(
                from: capture.image, scale: capture.scale)
            else {
                finish(operation, fileURL: fileURL, removeFile: true)
                return
            }
            guard isCurrent(operation) else { return }
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
                guard isCurrent(operation) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                finish(operation, fileURL: fileURL, removeFile: false)
            } catch {
                finish(operation, fileURL: fileURL, removeFile: true)
            }
        }
    }

    static func load() -> ScreenshotSelectionController.Capture? {
        stateLock.lock()
        let pending = pendingCapture
        stateLock.unlock()
        if let pending { return pending }

        guard let fileURL else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let dpi = properties[kCGImagePropertyDPIWidth] as? NSNumber,
              let scale = ScreenshotSupport.captureScale(fromDPI: dpi.doubleValue)
        else { return nil }
        let imageOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, imageOptions) else { return nil }
        return ScreenshotSelectionController.Capture(image: image, scale: scale, anchorRect: .zero)
    }

    static func clear() {
        stateLock.lock()
        generation += 1
        pendingCapture = nil
        stateLock.unlock()
        if let withheldURL { try? FileManager.default.removeItem(at: withheldURL) }
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func isCurrent(_ operation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == operation
    }

    private static func finish(_ operation: Int, fileURL: URL, removeFile: Bool) {
        guard isCurrent(operation) else { return }
        if removeFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
        stateLock.lock()
        if generation == operation {
            pendingCapture = nil
        }
        stateLock.unlock()
    }
}
