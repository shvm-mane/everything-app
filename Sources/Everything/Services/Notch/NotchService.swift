// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import SwiftUI

struct NotchNotice: Equatable {
    let event: NotchEvent
    let title: String
    let detail: String
    let symbol: String
    var level: Double? = nil
    var notification: NotchNotificationContent? = nil
    var notificationID: UUID? = nil
    var agent: AgentProvider? = nil
    var mascot: NotchMascotReaction? = nil
    var minimumWings = NotchNoticeWings.zero

    var preferredWings: NotchNoticeWings { preferredWings(wrapsMessage: false) }

    func wings(in geometry: NotchGeometry) -> NotchNoticeWings {
        geometry.noticeWings(preferredWings(
            wrapsMessage: NotchNotificationBannerLayout.messageLines(stripHeight: geometry.stripHeight) > 1))
    }

    func preferredWings(wrapsMessage: Bool) -> NotchNoticeWings {
        if let notification {
            let fitted = NotchNotificationBannerLayout.wings(for: notification, wrapsMessage: wrapsMessage)
            return NotchNoticeWings(leading: max(minimumWings.leading, fitted.leading),
                                    trailing: max(minimumWings.trailing, fitted.trailing))
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        func measured(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let leading = measured(level == nil ? title : detail)
        if level != nil, event != .accessory {
            let wing = ceil(Self.levelInset + 18 + 8 + max(leading, measured("100%")))
            return NotchNoticeWings(leading: wing, trailing: wing)
        }
        let maximum: CGFloat = event == .accessory && level == nil ? 160 : 240
        func fitted(_ content: CGFloat) -> CGFloat { min(maximum, max(Self.minimumWing, ceil(content) + 16 + cameraGap)) }
        let mark = fitted(leading > 0 ? leading + 18 + 8 : 18)
        guard level == nil else { return NotchNoticeWings(leading: mark, trailing: mark) }
        let trailing = fitted((detail as NSString).size(withAttributes: [.font: font]).width)
        if event == .track || event == .battery {
            let side = event == .battery ? (title == "Low Power Mode" ? max(mark, trailing)
                                            : min(100, max(mark, trailing) - 12))
                : min(Self.trackWingLimit, max(mark, trailing))
            return NotchNoticeWings(leading: side, trailing: side)
        }
        return NotchNoticeWings(leading: mark, trailing: trailing)
    }

    var preferredWingWidth: CGFloat { preferredWings.widest }

    static let minimumWing: CGFloat = 36

    static let trackWingLimit: CGFloat = 170

    static let levelInset: CGFloat = 13

    var readsFromEnds: Bool { level == nil && notification == nil }

    var cameraGap: CGFloat { event == .battery ? 16 : readsFromEnds ? 6 : 0 }

    var accessibilityText: String {
        notification?.accessibilityText ?? [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func inset(wing: CGFloat) -> CGFloat {
        level != nil && event != .accessory ? Self.levelInset : min(NotchNotificationBannerLayout.inset, wing / 2)
    }

    func mascotOffset(in geometry: NotchGeometry) -> CGFloat {
        let wing = wings(in: geometry).leading
        return -(geometry.noticeCameraGap / 2 + wing) + inset(wing: wing) + NotchMascotSupport.noticeSize / 2
    }

    func previewContentHeight(width: CGFloat) -> CGFloat {
        guard let notification else { return 0 }
        return NotchNotificationPreviewLayout.contentHeight(for: notification, width: width)
    }
}

final class NotchService: ObservableObject {
    static let shared = NotchService()
    static let fullscreenVisibilityDidChange = Notification.Name("NotchFullscreenVisibilityDidChange")

    @Published private(set) var geometry = NotchGeometry(
        screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0, cameraWidth: 0)
    @Published private(set) var expanded = false
    @Published private(set) var showsKeyboardFocus = false
    @Published private(set) var shortcutRegistrationFailed = false
    private let hotkey = QuickToolHotkey(id: 81)
    private let claudeHotkey = QuickToolHotkey(id: 90)
    @Published private(set) var peeking = false
    @Published private(set) var dragPlaceholder = false
    @Published private(set) var choosingFileDropDestination = false
    @Published private(set) var targetsMediaDrop = false
    @Published private(set) var selectedMetric: MetricDetailKind?
    @Published private(set) var captureControls: ScreenCaptureSelectionOptions?
    @Published private(set) var captureControlsCollapsed = false
    @Published private(set) var captureSelectionInProgress = false
    @Published var pinned = false
    @Published private(set) var selected: NotchModule = .music
    @Published private(set) var showingAppPanel = false
    @Published private(set) var showingSections = false
    @Published private(set) var sectionQuery = ""
    @Published var highlightedSection: NotchModule? { didSet { revealHighlightedSection() } }
    @Published private(set) var sectionRow = 0
    @Published private(set) var modules: [NotchModule] = []
    @Published private(set) var notice: NotchNotice?
    @Published private(set) var noticeExpanded = false
    @Published private(set) var departingNotice: NotchNotice?
    @Published private(set) var departingMusic: NotchCompactMusicSnapshot?
    @Published private(set) var heldMusic: NotchCompactMusicSnapshot?
    @Published private(set) var captureActions: AnyView?
    @Published var clipboardPinnedOnly = false
    @Published private(set) var clipboardSearchRequest = 0
    func requestClipboardSearch() { clipboardSearchRequest += 1 }
    @Published private(set) var captureContent: AnyView?
    @Published private(set) var scratchpadCloseSerial = 0
    @Published private(set) var scratchpadFindSerial = 0
    private(set) var scratchpadFindAction = NSTextFinder.Action.showFindInterface
    @Published private(set) var clipboardPastePress: NotchClipboardPastePress?
    @Published private(set) var panelIsKey = false
    @Published private var captureContentHeight: CGFloat?
    @Published private var fanDetailHeight: CGFloat?
    @Published private(set) var power = PowerReading()
    @Published private var musicDetailVisible = false

    private var windowHost: NotchWindowHost?
    private var panel: NotchPanel? { windowHost?.panel }
    private var captureControlsCancel: (() -> Void)?
    private var captureControlsSubscription: AnyCancellable?
    private var captureControlsWork: DispatchWorkItem?
    private var heldDrag = false
    private var shelfDragExitWork: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var screenEdgeClickMonitors: [Any] = []
    private var screenEdgePressArea: CGRect?
    private var captureControlsMonitors: [Any] = []
    private var hiddenHoverMonitors: [Any] = []
    private var hoverExitMonitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var noticeFitsInPlace = false
    private var noticeWork: DispatchWorkItem?
    private var departureWork: DispatchWorkItem?
    private var musicDepartureWork: DispatchWorkItem?
    private var presentedMusic: NotchCompactMusicSnapshot?
    private var trackWork: DispatchWorkItem?
    private var awaitsTrackNotice = false
    private var powerSource: CFRunLoopSource?
    private var powerSampler: PowerSampler?
    private var captureID: UUID?
    private var captureFallback: (() -> Void)?
    private var captureClose: (() -> Void)?
    private var captureDismiss: (() -> Void)?
    private var captureHover: ((Bool) -> Void)?
    private var captureClosesOnCollapse = false
    private var inside = false
    private var hoverEmphasized = false
    private var activitySelection = NotchActivitySelection()
    private var activityPickerMenuOpen = false
    private var hoverState = NotchHoverState()
    private var openedByHover = false
    private var clickedSinceOpening = false
    private var detailHasPage = false
    private var pageLayers: [NotchModule: () -> Void] = [:]
    private var trackingMenu = false
    private var homeControls: [NotchControlItem] = []
    private var fileInteractionActive = false
    private var keepsWorkingSurface: Bool { keepsSurfaceOnClick || showsCapturePreview }
    private var keepsSurfaceOnClick: Bool {
        pinned || trackingMenu || NSApp.modalWindow != nil || panel?.attachedSheet != nil
            || NotchLyricsService.shared.isImporting
            || (expanded && MediaWorkspaceView.panelModalActive)
            || (expanded && selected == .downloads && NotchDownloadService.shared.isChoosingFolder)
            || (expanded && selected == .scratchpad && ScratchpadService.shared.modalInteractionActive)
            || (expanded && showingAppPanel && WallpaperService.shared.isChoosingSource)
            || (expanded && !showingSections && selected == .calendar && Permissions.shared.keepsCalendarPrompt)
            || (expanded && !showingSections && selected == .files && fileInteractionActive)
            || CameraPreviewService.shared.keepsNotchPermissionPrompt
            || (expanded && !showingSections && selected == .tools && (QuickLauncherService.shared.activeUtility != nil || QuickLauncherService.shared.isEditing))
    }
    private var showsCapturePreview: Bool {
        expanded && !showingSections && selected == .captures && captureContent != nil
    }
    private(set) var running = false
    private var session = NotchSessionState()
    private var suspended: Bool { !session.canPresent }
    @Published private(set) var hiddenInFullscreen = false {
        didSet {
            guard hiddenInFullscreen != oldValue else { return }
            NotificationCenter.default.post(name: Self.fullscreenVisibilityDidChange, object: self,
                                            userInfo: ["hidden": hiddenInFullscreen])
        }
    }
    private var settingsSignature = ""
    private var gesture = NotchGestureSupport()
    private var sectionScroll = NotchSectionScroll()
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    private var volumeDeviceUID: String?
    private var ownLevelAdjustmentUntil: [NotchEvent: TimeInterval] = [:]
    private var lastVolumeRide: TimeInterval = -.infinity
    private var inputSourceID: String?
    private var ownInputSourceID: String?
    private var notchNeedsMonitor = false
    private var menuSpaceTimer: Timer?
    private var appFullscreenTimer: Timer?
    private var appFullscreenDisplays: Set<CGDirectDisplayID> = []
    private var menuSpaceReading = false
    private var menuSpaceGeneration = 0
    private var menuBarMeasurements = NotchMenuBarMeasurements()
    private var screenRefreshWork: DispatchWorkItem?
    private var preferenceSyncWork: DispatchWorkItem?
    private let menuSpaceQueue = DispatchQueue(label: "com.vorssaint.notch-menu-space", qos: .utility)
    private var mirrorHeldForArrival: CGDirectDisplayID?
    private var relocationTicket = 0
    private var displayID: CGDirectDisplayID?
    private var followsPointer = false
    private var showsOnAllDisplays = false
    @Published private(set) var capsuleMusicTitleShown = false
    @Published private(set) var musicStripPointer: NotchMusicStripPart?
    @Published private(set) var musicStripNamed = false
    @Published private(set) var musicStripRequest: Bool?
    private var musicStripHeldSong: NotchPlaybackContext?
    private var musicStripHeldMusic: NotchCompactMusicSnapshot?
    private var musicNamingWork: DispatchWorkItem?
    private var musicRequestWork: DispatchWorkItem?
    private var musicStripFitsInPlace = false
    @Published private(set) var mascotVisit: NotchMascotVisit? {
        didSet { noteMascotStirred() }
    }
    @Published private(set) var mascotStepsAside = false
    private var mascotStepBackWork: DispatchWorkItem?
    private var mascotVisitWork: DispatchWorkItem?
    private var nextMascotVisitWork: DispatchWorkItem?
    private var mascotVisitsWereOn = false
    private var mascotFrequencyAtSync: NotchMascotVisitFrequency?
    private var mascotWasEnabled: Bool?
    private var mascotSideAtSync: NotchMascotSide?
    private var mascotHidesAtSync: Bool?
    @Published private(set) var mascotTucked = false
    private var mascotStirred: CFTimeInterval = -.infinity
    private var mascotTuckWork: DispatchWorkItem?
    @Published private(set) var mascotReaction: NotchMascotReactionEvent? {
        didSet { noteMascotStirred() }
    }
    private var pendingMascotReaction: (reaction: NotchMascotReaction, deadline: CFTimeInterval,
                                        notBefore: CFTimeInterval)?
    private var mascotReactionFlushWork: DispatchWorkItem?
    private var mascotReactionGate = NotchMascotReactionGate()
    private var lastMascotGroove: CFTimeInterval = -.infinity
    private var mascotSawKeepAwake: Bool?
    private var mascotSawAgents: Bool?
    private var mascotSawCountdown: NotchCalendarCountdown?
    private var lastMascotAgentStart: CFTimeInterval = -.infinity
    @Published private(set) var mascotInBar = false
    @Published private(set) var mascotBridging = false
    private var mascotBridgeWork: DispatchWorkItem?
    private enum MascotBridgeTarget: Equatable { case rest, notice(NotchNotice) }
    private var mascotBridgeTarget: MascotBridgeTarget?
    private var mascotBridgeLift: CGFloat = 0
    private(set) var mascotRestedInView = false {
        didSet {
            if oldValue, !mascotRestedInView { mascotLeftRest = CACurrentMediaTime() }
            if !oldValue, mascotRestedInView {
                mascotBackAtRest = CACurrentMediaTime()
                noteMascotStirred()
                mascotReturnedToRest()
                if pendingMascotReaction != nil { flushMascotReaction() }
            }
        }
    }
    private var mascotLeftRest: CFTimeInterval = -.infinity
    private var mascotBackAtRest: CFTimeInterval = -.infinity
    var mascotJustRested: Bool { mascotRestedInView || CACurrentMediaTime() - mascotLeftRest < 0.35 }

    var mascotLingers: Bool {
        if case .linger = mascotVisit?.kind { return true }
        return false
    }
    @Published private(set) var showingCommandBar = false
    @Published private var commandBarHeight: CGFloat?
    private var measuredCommandBarHeight: CGFloat?
    private var musicTitleWork: DispatchWorkItem?
    private static let musicTitleDuration: TimeInterval = 4
    private var mirrors: [CGDirectDisplayID: NotchMirror] = [:]
    private var fullscreenDisplays: Set<CGDirectDisplayID> = []
    private var pointerMonitors: [Any] = []
    private var pointerFollowWork: DispatchWorkItem?
    private static let pointerFollowDelay: TimeInterval = 0.2

    private init() {
        hotkey.onPress = { [weak self] in self?.toggleFromShortcut() }
        claudeHotkey.onPress = { [weak self] in self?.toggleClaudeUsage() }
    }

    private var hiddenUntilHover: Bool {
        !hiddenInFullscreen && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover)
            && !expanded && !peeking && !dragPlaceholder && captureControls == nil
            && !(NotchSupport.hiddenShowsActivity() && (notice != nil
                || compactActivity != nil && (geometry.isNotched || geometry.compactSideRoom != nil)))
    }

    var fullscreenCompact: Bool {
        hiddenInFullscreen && !expanded && !peeking
    }

    private var hiddenAtRestInFullscreen: Bool {
        fullscreenCompact && !geometry.isNotched
    }

    private var hoverOpeningEnabled: Bool {
        hiddenInFullscreen ? UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverInFullscreen)
            : UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover)
    }

    private var watchesHiddenHover: Bool {
        hiddenUntilHover || (hiddenAtRestInFullscreen && !dragPlaceholder && captureControls == nil
            && hoverOpeningEnabled)
    }

    var idleContent: NotchIdleContent {
        let content = NotchSupport.visibleIdleContent(isPlaying: !awaitsTrackNotice && NotchMusicService.shared.playback?.isPlaying == true)
        return content == .battery && !PowerSampler.hasInternalBattery ? .none : content
    }

    var mascotOn: Bool { mascotWasEnabled ?? false }

    var mascotSide: NotchMascotSide { mascotSideAtSync ?? NotchMascotSupport.side() }

    var mascotAtRest: Bool { mascotOn && idleContent == .none && !mascotInBar && !mascotTucked }

    var mascotRestingMood: NotchMascotMood { KeepAwakeManager.shared.isActive ? .alert : .idle }

    func mascotShows(on geometry: NotchGeometry) -> Bool {
        (mascotRestsInView || mascotVisit != nil) && (geometry.floats || geometry.restingWingWidth > 0)
    }

    private var mascotWantsRoom: Bool { NotchMascotSupport.isEnabled() }

    var hasTimerActivity: Bool {
        NotchTimerSupport.showsActivity(NotchTimerService.shared.session)
    }

    var hasWatchActivity: Bool {
        NotchWatchSupport.isEnabled() && NotchWatchService.shared.isActive
    }

    var hasDownloadActivity: Bool {
        NotchSupport.routes(.download)
            && NotchDownloadService.shared.items.contains { $0.active && !$0.completed }
    }

    var hasMusicActivity: Bool {
        let playback = NotchMusicService.shared.playback
        let held = playback.map { musicStripHolds(context: $0.commandContext, player: $0.track.appPID) } ?? false
        return NotchSupport.showsMusicActivity(isPlaying: held || playback?.isPlaying == true)
    }

    var hasAgentActivity: Bool {
        NotchAgentSupport.showsLiveActivity() && !AgentUsageService.shared.snapshot.live.isEmpty
    }

    var hasCalendarActivity: Bool {
        let calendar = NotchCalendarService.shared
        guard let countdown = calendar.countdown,
              countdown.ongoing ? NotchCalendarSupport.showsTimeLeft()
                : NotchCalendarSupport.showsCountdown(chosen: calendar.isChosen(countdown.event))
        else { return false }
        return countdown.isShown(at: Date(), leadTime: calendar.countdownLeadTime)
    }

    var hasKeepAwakeActivity: Bool {
        NotchKeepAwakeSupport.showsActivity() && KeepAwakeManager.shared.isActive
    }

    var compactActivity: NotchCompactActivity? {
        let available = awaitsTrackNotice ? compactActivities.filter { $0 != .music } : compactActivities
        return activitySelection.current(available: available)
    }

    var compactActivities: [NotchCompactActivity] {
        NotchSupport.compactActivities(timer: hasTimerActivity, watch: hasWatchActivity, downloads: hasDownloadActivity,
                                      agents: hasAgentActivity, calendar: hasCalendarActivity,
                                      music: hasMusicActivity, keepAwake: hasKeepAwakeActivity)
    }

    var showsCompactActivityPicker: Bool {
        (inside && !hoverState.suppressed || activityPickerMenuOpen) && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking
            && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivities.count > 1
    }

    var compactActivityPickerLayout: NotchActivityPickerLayout {
        let activities = compactActivities
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let labelWidth = activities.map {
            ($0.title(L10n.shared.language) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let combinations = compactActivityCombinations
        let sizes = activities.map { compactStripSize(for: $0) }
            + combinations.map { compactStripSize(for: $0.primary, companion: $0.companion) }
        let strip = CGSize(width: sizes.map(\.width).max() ?? geometry.cameraWidth,
                           height: sizes.map(\.height).max() ?? geometry.stripHeight)
        return NotchActivityPickerLayout(count: activities.count, labelWidth: labelWidth,
                                         stripSize: strip, screenWidth: geometry.screen.width,
                                         hasCombinations: !combinations.isEmpty)
    }

    func selectCompactActivity(_ activity: NotchCompactActivity) {
        guard compactActivities.contains(activity) else { return }
        hoverWork?.cancel(); hoverWork = nil
        switchCompactSelection {
            activitySelection.select(activity, available: compactActivities)
        }
    }

    private func switchCompactSelection(_ change: () -> Void) {
        let animation: Animation? = PerformanceMode.reduceMotion
            ? nil : .smooth(duration: 0.2)
        withAnimation(animation) {
            objectWillChange.send()
            change()
        }
        presentedMusic = nil
        refreshPresentation()
    }

    func selectCompactCombination(_ combination: NotchActivityCombination) {
        let companions = compactCompanions(of: combination.primary)
        guard companions.contains(combination.companion) else { return }
        hoverWork?.cancel(); hoverWork = nil
        switchCompactSelection {
            activitySelection.select(combination.primary, companion: combination.companion,
                                     available: compactActivities, companions: companions)
        }
    }

    func compactCompanions(of primary: NotchCompactActivity) -> [NotchCompactActivity] {
        []
    }

    var compactActivityCombinations: [NotchActivityCombination] {
        compactActivities.flatMap { primary in
            compactCompanions(of: primary).map { NotchActivityCombination(primary: primary, companion: $0) }
        }
    }

    var compactCompanion: NotchCompactActivity? {
        guard let activity = compactActivity else { return nil }
        let companions = compactCompanions(of: activity)
        if activity == activitySelection.preferred, let chosen = activitySelection.companion(available: companions) {
            return chosen
        }
        return companions.first
    }

    private var compactActivityIsVisible: Bool {
        !fullscreenCompact && !expanded && !peeking && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivity != nil
    }

    private var compactMusicIsVisible: Bool { compactActivityIsVisible && compactActivity == .music }

    var lingeringMusic: NotchCompactMusicSnapshot? {
        guard let presentedMusic, departingMusic == nil, compactActivity == nil, !expanded, !peeking,
              notice == nil, !dragPlaceholder, captureControls == nil else { return nil }
        return heldMusic ?? presentedMusic
    }

    var compactActivityGeometry: NotchGeometry {
        compactGeometry(for: compactActivity, companion: compactCompanion)
    }

    private func compactGeometry(for activity: NotchCompactActivity?, companion: NotchCompactActivity? = nil,
                                 base: NotchGeometry? = nil) -> NotchGeometry {
        var geometry = base ?? self.geometry
        if base == nil, showsCompactActivityPicker {
            let room = max(0, (geometry.screen.width - 24 - NotchActivityPickerLayout.horizontalInset * 2
                               - geometry.cameraWidth) / 2)
            geometry.compactSideRoom = min(geometry.compactSideRoom ?? 0, room)
        }
        switch activity {
        case .music: return geometry.compactMusicGeometry
        case .timer:
            return geometry.compactTimerGeometry(showsDownloads: companion == .downloads,
                                                 wing: timerStripWing(for: companion, in: geometry))
        case .downloads:
            let name = NotchDownloadService.shared.items.first { $0.active && !$0.completed }?.name
            return geometry.compactDownloadGeometry(wing: NotchDownloadSupport.compactWing(for: name, in: geometry))
        case .agents: return geometry.compactAgentGeometry(wing: agentStripWing(in: geometry))
        case .watch: return geometry.compactWatchGeometry(wing: watchStripWing(in: geometry))
        case .calendar:
            return geometry.compactCalendarGeometry(wing: calendarStripWing(for: companion, in: geometry),
                                                    paired: companion != nil)
        case .keepAwake: return geometry.compactTimerGeometry(showsDownloads: false, wing: keepAwakeStripWing(in: geometry))
        default: return geometry
        }
    }

    private func watchStripWing(in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactWatchGeometry(wing: NotchWatchSupport.stripWingRange.lowerBound)
        let watch = NotchWatchService.shared
        let size = NotchTimerSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let reading = watch.showsThumbnail ? NotchWatchSupport.thumbnailWidth
            : (watch.headline as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            ]).width.rounded(.up)
        let inset = provisional.compactActivityEdgeInset(boxHeight: size * 0.72, radius: 0)
        return reading + inset + NotchTimerSupport.stripCameraGap
    }

    private func keepAwakeStripWing(in geometry: NotchGeometry) -> CGFloat {
        NotchKeepAwakeSupport.stripWing(until: KeepAwakeManager.shared.endDate, now: Date(),
                                        locale: Locale(identifier: L10n.shared.language.rawValue), in: geometry)
    }

    private func calendarStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        guard let countdown = NotchCalendarService.shared.countdown else {
            return NotchGeometry.calendarWingRange.upperBound
        }
        let provisional = geometry.compactCalendarGeometry(wing: 0, paired: companion != nil)
        let inset = provisional.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        if let companion {
            let sides = max(inset + calendarClockWidth, companionMarkWidth(companion, in: provisional))
                + NotchTimerSupport.stripCameraGap
            return companion == .downloads ? max(80, sides) : sides
        }
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let language = L10n.shared.language
        let trimmed = countdown.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? FeatureStrings.notchCalendar(language).untitled : trimmed
        let titleSide = NotchCalendarSupport.stripDotWidth + NotchCalendarSupport.stripTitleSpacing
            + width(title, .systemFont(ofSize: 11, weight: .semibold))
        let clockSide = width(calendarClockShape, .monospacedDigitSystemFont(ofSize: 13, weight: .medium))
            + NotchCalendarSupport.stripClockSpacing
            + width(NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                    .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        return inset + max(titleSide, clockSide)
    }

    private func timerStripWing(for companion: NotchCompactActivity?, in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactTimerGeometry(showsDownloads: false,
                                                        wing: NotchTimerSupport.stripWingRange.lowerBound)
        let height = provisional.compactActivityContentHeight
        let timer = NotchTimerService.shared
        let size = NotchTimerSupport.stripTextSize(height: height)
        let text = NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                 locale: Locale(identifier: L10n.shared.language.rawValue))
        let reading = (NotchAgentSupport.readingShape(text) as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width.rounded(.up) + NotchTimerSupport.readingInset(provisional)
        let bar = companion == nil && !timer.session.countsUp && !timer.session.completed
            ? NotchTimerSupport.barMinimumWidth + NotchTimerSupport.readingInset(provisional) : 0
        return max(reading, bar, companionMarkWidth(companion, in: provisional)) + NotchTimerSupport.stripCameraGap
    }

    private func companionMarkWidth(_ companion: NotchCompactActivity?, in provisional: NotchGeometry) -> CGFloat {
        let height = provisional.compactActivityContentHeight
        switch companion {
        case .music:
            return provisional.compactMusicArtworkSide + provisional.compactMusicArtworkInset
        case .agents:
            let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
            let side = NotchTimerSupport.stripAgentMarkSize(height: height, working: working)
            return CGFloat(max(1, working)) * (side * 1.45 + 1) + CGFloat(max(0, working - 1))
                + provisional.compactActivityEdgeInset(boxHeight: side + 4, radius: (side + 4) / 2)
        case .calendar:
            return provisional.compactActivityEdgeInset(boxHeight: 9, radius: 0) + calendarClockWidth
        default:
            let side = NotchTimerSupport.stripIconSize(height: height)
            return side + provisional.compactActivityEdgeInset(boxHeight: side, radius: side / 2)
        }
    }

    private var calendarClockShape: String {
        NotchCalendarSupport.countdownShape(leadTime: NotchCalendarService.shared.countdownLeadTime)
    }

    private var calendarClockWidth: CGFloat {
        NotchCalendarSupport.stripDotWidth + NotchCalendarSupport.stripClockSpacing
            + (calendarClockShape as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            ]).width.rounded(.up)
    }

    private func agentStripWing(in geometry: NotchGeometry) -> CGFloat {
        let provisional = geometry.compactAgentGeometry(wing: NotchAgentSupport.stripWingRange.lowerBound)
        let size = NotchAgentSupport.stripTextSize(height: provisional.compactActivityContentHeight)
        let shape = NotchAgentSupport.readingShape(NotchAgentSupport.stripReading(
            AgentUsageService.shared.snapshot, readout: NotchAgentSupport.readout(),
            display: NotchAgentSupport.limitDisplay(), focus: NotchAgentSupport.limitFocus(), now: Date()))
        let width = (shape as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        ]).width
        let reading = width.rounded(.up) + NotchAgentSupport.readingInset(provisional)
        let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
        let mark = CGFloat(working > 1 ? 11 : 14)
        let frame = mark * 1.45 + 1
        let marks = CGFloat(max(1, working)) * frame + CGFloat(max(0, working - 1))
            + provisional.compactActivityEdgeInset(boxHeight: mark + 4, radius: (mark + 4) / 2)
        return max(reading, marks) + NotchAgentSupport.stripCameraGap
    }

    var musicShowsVolume: Bool { NotchSupport.showsMusicVolume() }

    var expandedSize: CGSize {
        if showingSections {
            return geometry.sectionPickerSize(count: filteredSections.count)
        }
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        let launcher = QuickLauncherService.shared
        return pageSize(in: expandedGeometry, module: showingAppPanel ? .tools : selected,
                        detail: selectedMetric != nil, panel: showingAppPanel,
                        detailHeight: selectedMetric == .fan ? fanDetailHeight : nil,
                        musicExtraHeight: musicExtras && musicDetailVisible ? geometry.musicExtrasHeight : 0,
                        fileMediaHeight: !choosingFileDropDestination && AppFeature.mediaTools.isAvailable
                            && NotchFileToolsService.shared.mediaPresented ? NotchFileToolsService.shared.mediaContentHeight : nil,
                        toolCount: launcher.isEditing || launcher.activeUtility != nil ? nil : launcher.visibleItems.count,
                        capturePreviewHeight: captureContent == nil ? nil : captureContentHeight)
    }

    func previewSize(for module: NotchModule) -> CGSize {
        pageSize(in: previewGeometry(for: module), module: module, detail: false, panel: false, detailHeight: nil, musicExtraHeight: 0,
                 fileMediaHeight: nil, toolCount: QuickLauncherService.shared.visibleItems.count, capturePreviewHeight: nil)
    }

    func previewGeometry(for module: NotchModule) -> NotchGeometry {
        var result = geometry.page(module, controls: NotchSupport.controls(),
                                   sectionsButton: false)
        if result.pageTop == .wrapsCamera { result.pageTrailingControls = playerToggleCount }
        return result
    }

    private var playerToggleCount: Int {
        guard NotchMusicService.shared.playback != nil else { return 0 }
        let defaults = UserDefaults.standard
        var count = 0
        if defaults.bool(forKey: DefaultsKey.notchLyricsEnabled), AppFeature.notchLyrics.isAvailable { count += 1 }
        if defaults.bool(forKey: DefaultsKey.notchQueueEnabled), AppFeature.notchQueue.isAvailable { count += 1 }
        return count
    }

    var previewLargestSize: CGSize { previewGeometry(for: .calendar).expandedSize(module: .calendar) }

    private func pageSize(in geometry: NotchGeometry, module: NotchModule, detail: Bool, panel: Bool,
                          detailHeight: CGFloat?, musicExtraHeight: CGFloat, fileMediaHeight: CGFloat?, toolCount: Int?,
                          capturePreviewHeight: CGFloat?) -> CGSize {
        let controls = NotchSupport.controls()
        let sliders = controls.filter(\.isLevel).count
        let shortcuts = controls.filter { !$0.isLevel && $0 != .music }.count
        return geometry.expandedSize(module: module, detail: detail, panel: panel, detailHeight: detailHeight,
                                     shortcutCount: shortcuts,
                                     sliderCount: sliders, controlsHaveMusic: controls.contains(.music), musicHasContent: NotchMusicService.shared.playback != nil,
                                     musicShowsVolume: musicShowsVolume,
                                     musicExtraHeight: musicExtraHeight, fileMediaHeight: fileMediaHeight,
                                     systemCards: NotchSupport.systemCardCount(hasBattery: PowerSampler.hasInternalBattery,
                                                                               fans: SystemMonitor.shared.snapshot.fanSpeeds.count),
                                     toolCount: toolCount, capturePreviewHeight: capturePreviewHeight,
                                     timerHasSession: NotchTimerService.shared.session.hasSession,
                                     timerMode: NotchTimerService.shared.session.hasSession
                                        ? NotchTimerService.shared.session.mode : NotchTimerSupport.savedMode(),
                                     agentsHeight: module == .agents && !detail && !panel
                                        ? agentsContentHeight(width: geometry.contentWidth) : nil)
    }

    private func agentsContentHeight(width: CGFloat) -> CGFloat? {
        let usage = AgentUsageService.shared.snapshot
        let enabled = NotchAgentSupport.providers()
        let accounts = NotchAgentSupport.showsCodexAccounts() ? CodexProfileLimitsService.shared.states.map(\.id) : []
        let claudeProfile = AgentUsageService.shared.claudeProfile
        let claudeAccount = claudeProfile.isDefault ? nil : claudeProfile.id
        guard usage.loaded || !accounts.isEmpty else { return nil }
        let providers = enabled.filter { usage.seen.contains($0) || ($0 == .codex && !accounts.isEmpty)
            || ($0 == .claude && claudeAccount != nil) }
        guard !providers.isEmpty else { return 0 }
        return NotchAgentSupport.contentHeight(NotchAgentSupport.rows(
            NotchAgentSupport.tiles(cards: NotchAgentSupport.cards(), providers: providers, codexAccounts: accounts,
                                    claudeAccount: claudeAccount),
            width: width))
    }
    var expandedGeometry: NotchGeometry {
        var result = geometry
        result.requiresFullWidthHeader = selected == .captures && captureActions != nil
            && !showingSections && !showingAppPanel && selectedMetric == nil
        result.pageTop = expandedPageTop
        if result.pageTop == .wrapsCamera { result.pageTrailingControls = playerToggleCount }
        if !showingSections, !showingAppPanel, selectedMetric == nil, !modules.isEmpty {
            result.pageContentWidth = NotchLayout.naturalContentWidth(selected, controls: homeControls,
                                                                      within: geometry.contentWidth)
        } else {
            result.sectionsButtonInRow = false
        }
        return result
    }
    private var expandedPageTop: NotchPageTop {
        if showingSections || showingAppPanel || selectedMetric != nil { return .row }
        return modules.isEmpty ? .none : selected.pageTop
    }
    var detailTitle: String {
        if showingAppPanel { return "EVERYTHING" }
        let language = L10n.shared.language
        guard let metric = selectedMetric else { return FeatureStrings.notch(language).title }
        return metric.rawValue.capitalized
    }
    var contentSize: CGSize { expandedGeometry.contentSize(for: expandedSize) }
    var usesGlassSurface: Bool {
        (expanded && !showingCommandBar) || peeking || dragPlaceholder || noticeExpanded
            || (captureControls != nil && !captureControlsCollapsed)
    }

    var captureControlsLayout: NotchCaptureControlsLayout {
        NotchCaptureControlsLayout(
            geometry: geometry,
            titleWidth: NotchCaptureControlsLayout.titleWidth(FeatureStrings.screenshot(L10n.shared.language).screenCaptureTitle),
            capturesAudio: captureControls?.selectedTool.capturesAudio == true)
    }

    var surfaceSize: CGSize {
        if let capsule = capsuleSurfaceSize { return capsule }
        if fullscreenCompact { return geometry.bareCutout }
        if captureControls != nil {
            if captureControlsCollapsed {
                return CGSize(width: geometry.cameraWidth + 56, height: geometry.stripHeight)
            }
            return captureControlsLayout.size
        }
        if expanded { return showingCommandBar ? commandBarSurfaceSize : expandedSize }
        if dragPlaceholder { return CGSize(width: geometry.peek.width, height: geometry.safeContentTop + 66) }
        if let notice {
            guard noticeExpanded else { return geometry.noticeSize(wings: notice.wings(in: geometry)) }
            return geometry.notificationPreviewSize(
                contentHeight: notice.previewContentHeight(width: geometry.notificationPreviewContentWidth))
        }
        if peeking { return geometry.peek }
        if showsCompactActivityPicker { return compactActivityPickerLayout.size }
        if compactActivity != nil {
            var resting = compactActivityGeometry.compactActivitySize
            let named = namedMusicWings
            if let named { resting.width += named.leading - named.trailing }
            return hoverEmphasized
                ? NotchHoverEmphasis.size(from: resting, geometry: geometry,
                                          reach: named.map { ($0.leading - $0.trailing) / 2 } ?? 0)
                : resting
        }
        let resting = geometry.restingSize(showsContent: idleContent != .none || mascotShows(on: geometry))
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    var surfaceShift: CGFloat {
        guard !geometry.floats, !fullscreenCompact, captureControls == nil, !expanded, !dragPlaceholder else { return 0 }
        if let notice { return noticeExpanded ? 0 : geometry.noticeShift(notice.wings(in: geometry)) }
        return namedMusicWings.map { ($0.trailing - $0.leading) / 2 } ?? 0
    }

    var commandBarSurfaceSize: CGSize {
        let width = max(geometry.cameraWidth + 80, 560 + NotchLayout.horizontalInset * 2)
        let height = geometry.safeContentTop + (commandBarHeight ?? 52) + NotchLayout.bottomInset
        return CGSize(width: min(geometry.screen.width - 24, width), height: min(geometry.screen.height - 48, height))
    }

    private var capsuleSurfaceSize: CGSize? {
        guard geometry.floats, !fullscreenCompact, !expanded, !dragPlaceholder else { return nil }
        if captureControls != nil { return captureControlsCollapsed ? NotchCapsuleLayout.captureSurface(geometry: geometry) : nil }
        if let notice { return noticeExpanded ? nil : capsuleNoticeSize(notice) }
        if peeking || showsCompactActivityPicker { return nil }
        let resting = compactActivity.map { capsuleStripSize(for: $0, companion: compactCompanion) }
            ?? geometry.restingSize(showsContent: false)
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    private var bannerCapsuleWidth: CGFloat = 0

    private func capsuleNoticeSize(_ notice: NotchNotice) -> CGSize {
        var size = capsuleNoticeSurface(notice)
        guard notice.notification != nil else { return size }
        if notice.minimumWings != .zero { size.width = max(size.width, bannerCapsuleWidth) }
        bannerCapsuleWidth = size.width
        return size
    }

    func capsuleNoticeSurface(_ notice: NotchNotice) -> CGSize {
        let layout = NotchCapsuleLayout.self
        guard let content = notice.notification else {
            return layout.surface(content: layout.noticeContent(title: notice.title, detail: notice.detail,
                                                                level: notice.level != nil),
                                  maximum: layout.Maximum.notice, geometry: geometry)
        }
        return layout.surface(content: layout.notificationContent(title: content.compactTitle, message: content.compactDetail,
                                                                 geometry: geometry),
                              maximum: layout.Maximum.notification, geometry: geometry)
    }

    func compactStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity? = nil) -> CGSize {
        geometry.floats ? capsuleStripSize(for: activity, companion: companion)
            : compactGeometry(for: activity, companion: companion).compactActivitySize
    }

    private func capsuleStripSize(for activity: NotchCompactActivity, companion: NotchCompactActivity?,
                                  geometry: NotchGeometry? = nil) -> CGSize {
        let ownDisplay = geometry == nil
        let named = capsuleMusicTitleShown || ownDisplay && musicStripNamesSong
        let geometry = geometry ?? self.geometry
        let layout = NotchCapsuleLayout.self
        let language = L10n.shared.language
        let download = NotchDownloadService.shared.items.first { $0.active && !$0.completed }
        let working = Set(AgentUsageService.shared.snapshot.live.map(\.provider)).count
        switch activity {
        case .music:
            let live = NotchMusicService.shared.playback
            let shown = heldMusic ?? (ownDisplay ? musicStripStandIn(for: live) : nil)
            let playback = shown?.playback ?? live
            return layout.musicSurface(title: named
                                        ? playback?.track.title ?? FeatureStrings.radialMenu(language).mediaNowPlaying : nil,
                                       geometry: geometry)
        case .timer:
            let timer = NotchTimerService.shared
            return layout.timerSurface(reading: NotchTimerSupport.compactText(for: timer.session, at: timer.now,
                                                                              locale: Locale(identifier: language.rawValue)),
                                       companion: companion, workingAgents: working,
                                       downloadPercent: download?.fraction != nil, geometry: geometry, language: language,
                                       calendarLeadTime: NotchCalendarService.shared.countdownLeadTime)
        case .downloads:
            return layout.downloadSurface(name: download?.name ?? FeatureStrings.notchFiles(language).downloadsTitle,
                                          hasProgress: download?.fraction != nil, geometry: geometry, language: language)
        case .agents:
            let reading = NotchAgentSupport.stripReading(AgentUsageService.shared.snapshot, readout: NotchAgentSupport.readout(),
                                                         display: NotchAgentSupport.limitDisplay(),
                                                         focus: NotchAgentSupport.limitFocus(), now: Date())
            return layout.agentSurface(reading: reading, working: working, geometry: geometry)
        case .calendar:
            guard let countdown = NotchCalendarService.shared.countdown else { return geometry.restingSize(showsContent: false) }
            if let companion {
                return layout.calendarPairSurface(companion: companion, workingAgents: working,
                                                  downloadPercent: download?.fraction != nil, geometry: geometry,
                                                  language: language, calendarLeadTime: NotchCalendarService.shared.countdownLeadTime)
            }
            return layout.calendarSurface(title: layout.calendarTitle(countdown, language: language),
                                          time: NotchCalendarSupport.timeText(countdown, locale: language.formattingLocale()),
                                          geometry: geometry, calendarLeadTime: NotchCalendarService.shared.countdownLeadTime)
        case .watch:
            let watch = NotchWatchService.shared
            return layout.watchSurface(reading: watch.headline, thumbnail: watch.showsThumbnail, geometry: geometry)
        case .keepAwake:
            let reading = KeepAwakeManager.shared.endDate.map {
                NotchKeepAwakeSupport.compactText(until: $0, now: Date(), locale: Locale(identifier: language.rawValue))
            }
            return layout.keepAwakeSurface(reading: reading, geometry: geometry)
        }
    }

    var presentationWindow: NSPanel? { panel }
    var acceptsUserInteraction: Bool {
        running && !suspended && panel != nil
            && windowHost?.isConcealedForMissionControl != true
    }
    var acceptsSystemFeedback: Bool {
        acceptsUserInteraction && !hiddenInFullscreen
    }
    var showsSystemFeedback: Bool {
        acceptsSystemFeedback && (!hiddenUntilHover || NotchSupport.hiddenShowsActivity())
    }

    var protectedWindowIDs: Set<CGWindowID> {
        islandWindowIDs.subtracting(captureVisibleWindowIDs)
    }

    var captureVisibleWindowIDs: Set<CGWindowID> {
        ScreenshotCapturePolicy.islandCaptureWindowIDs(
            islandWindowIDs: islandWindowIDs,
            mainWindowID: panel.flatMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil },
            showsInCaptures: NotchSupport.showsInCaptures(),
            showsCaptureTool: captureControls != nil || captureID.map(isCaptureVisible(id:)) == true)
    }

    private var islandWindowIDs: Set<CGWindowID> {
        let panels: [NotchPanel?] = [panel] + mirrors.values.map { $0.host.panel }
        return Set(panels.compactMap { panel -> CGWindowID? in
            guard let panel, panel.isVisible, panel.windowNumber > 0 else { return nil }
            return CGWindowID(panel.windowNumber)
        })
    }

    var captureChromeWindowIDs: Set<CGWindowID> {
        running ? islandWindowIDs : []
    }

    func syncWithPreferences() {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
        guard NotchSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        syncShortcut()
        if !NotchTimerSupport.isEnabled() { NotchTimerService.shared.stop() }
        NotchWatchService.shared.syncWithPreferences()
        NotchFileToolsService.shared.syncWithPreferences()
        if !NotchFileToolsService.shared.offersMediaDrop { endFileDrop() }
        if !NotchAgentSupport.isEnabled() { AgentUsageService.shared.stop() }
        guard !suspended else {
            if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
            else { NotchTimerService.shared.suspend() }
            NotchLockScreenService.shared.sync(session)
            return
        }
        guard screenIndex(in: NSScreen.screens) != nil else { withdrawFromMissingScreen(); return }
        refreshModules()
        homeControls = NotchSupport.controls()
        NotchDownloadService.shared.syncWithPreferences()
        NotchCalendarService.shared.syncWithPreferences()
        NotchNotificationService.shared.syncWithPreferences()
        NotchAudioLevelService.shared.syncWithPreferences()
        AgentUsageService.shared.syncWithPreferences()
        followsPointer = displayPreference == .pointer || displayPreference == .all
        showsOnAllDisplays = displayPreference == .all
        updateFullscreenDisplays()
        updateScreen()
        syncAppFullscreenMonitoring()
        syncPointerFollowing()
        syncGestures()
        NotchTimerService.shared.syncWithPreferences()
        NotchAccessoryService.shared.syncWithPreferences()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0)) }.joined()
            + NotchSupport.idleContent().rawValue + String(NotchSupport.watchesMusicActivity())
            + String(NotchKeepAwakeSupport.showsActivity())
            + modules.map(\.rawValue).joined()
            + String(AppFeature.fanControl.isAvailable)
            + String(NotchSupport.routesShelf()) + String(NotchSupport.revealsShelfDrag())
            + String(NotchSupport.routesCaptureControls())
            + String(NotchMascotSupport.isEnabled())
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        }
        if !NotchSupport.routes(.capture), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls() { cancelCaptureControls() }
        syncNoticeWithPreferences()
        syncVisibleConsumers()
        let mascotEnabled = NotchMascotSupport.isEnabled()
        let mascotToggled = mascotWasEnabled.map { $0 != mascotEnabled } ?? false
        mascotWasEnabled = mascotEnabled
        let hidingToggled = syncMascotHiding(switchedOn: mascotToggled && mascotEnabled)
        if mascotToggled, !expanded { stageMascotEntrance(arriving: mascotEnabled) }
        refreshPresentation(animated: (mascotToggled || hidingToggled) && !expanded)
        syncMascotVisits()
        syncMascotSide()
        objectWillChange.send()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    func toggleFromShortcut() {
        guard acceptsUserInteraction else { return }
        if captureControls != nil { expandCaptureControls(); return }
        toggle()
    }

    private func syncShortcut() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.notchShortcut, fallback: .notchDefault)
        let failed = !hotkey.sync(enabled: NotchSupport.holdsShortcut() && !ShortcutCapture.isCapturing,
                                  shortcut: shortcut, storageKey: DefaultsKey.notchShortcut)
        if failed != shortcutRegistrationFailed { shortcutRegistrationFailed = failed }
        let defaults = UserDefaults.standard
        _ = claudeHotkey.sync(enabled: NotchAgentSupport.isEnabled() && !ShortcutCapture.isCapturing
                                  && defaults.bool(forKey: DefaultsKey.claudeUsageShortcutEnabled),
                              shortcut: GlobalShortcut.saved(for: DefaultsKey.claudeUsageShortcut, fallback: .claudeUsageDefault),
                              storageKey: DefaultsKey.claudeUsageShortcut)
    }

    private func toggleClaudeUsage() {
        guard acceptsUserInteraction, NotchAgentSupport.isEnabled() else { return }
        if expanded, selected == .agents, !showingAppPanel, !showingSections, !showingCommandBar { collapse() }
        else { open(.agents) }
    }

    private func refreshModules() {
        let updated = NotchSupport.modules()
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .music
        if selected != selection { selected = selection }
        if let selectedMetric, !metricIsAvailable(selectedMetric) { self.selectedMetric = nil }
    }

    private func metricIsAvailable(_ metric: MetricDetailKind) -> Bool {
        false
    }

    func stop(restoreCapture: Bool = true) {
        preferenceSyncWork?.cancel(); preferenceSyncWork = nil
        hotkey.unregister()
        claudeHotkey.unregister()
        if shortcutRegistrationFailed { shortcutRegistrationFailed = false }
        NotchLyricsService.shared.stop()
        NotchFileToolsService.shared.stop()
        AgentUsageService.shared.stop()
        guard running else { return }
        running = false
        NotchTimerService.shared.stop()
        NotchAccessoryService.shared.stop()
        NotchWatchService.shared.stop()
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        NotchLockScreenService.shared.close()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        session = NotchSessionState()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        fallback?()
    }

    private func tearDownPresentation() {
        cancelRelocation()
        screenRefreshWork?.cancel(); screenRefreshWork = nil
        stopAppFullscreenMonitoring()
        nextMascotVisitWork?.cancel(); nextMascotVisitWork = nil
        mascotVisitWork?.cancel(); mascotVisitWork = nil
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = nil
        mascotTuckWork?.cancel(); mascotTuckWork = nil
        mascotStepsAside = false
        mascotInBar = false
        commandBarHeight = nil
        if showingCommandBar {
            showingCommandBar = false
            commandBarDidClose()
        }
        captureControlsWork?.cancel(); captureControlsWork = nil
        musicDetailVisible = false
        pageLayers.removeAll()
        clipboardPinnedOnly = false
        panel?.handleScroll = nil
        gesture = NotchGestureSupport()
        sectionScroll = NotchSectionScroll()
        stopMenuSpaceMonitoring()
        geometry.compactSideRoom = nil
        hoverWork?.cancel(); hoverWork = nil
        noticeWork?.cancel(); noticeWork = nil
        endDeparture()
        finishMusicDeparture()
        presentedMusic = nil
        trackWork?.cancel(); trackWork = nil
        heldMusic = nil
        awaitsTrackNotice = false
        subscriptions.removeAll()
        stopPower()
        NotchMusicService.shared.stop()
        NotchAudioLevelService.shared.stop()
        CameraPreviewService.shared.hideEmbedded()
        NotchAccessoryService.shared.suspend()
        NotchDownloadService.shared.stop()
        NotchCalendarService.shared.stop()
        NotchNotificationService.shared.stop()
        AgentUsageService.shared.pause()
        settingsSignature = ""
        expanded = false
        peeking = false
        dragPlaceholder = false
        endFileDrop()
        fileInteractionActive = false
        heldDrag = false
        shelfDragExitWork?.cancel(); shelfDragExitWork = nil
        selectedMetric = nil
        pinned = false
        notice = nil
        noticeExpanded = false
        showingAppPanel = false
        showingSections = false
        sectionQuery = ""
        highlightedSection = nil
        sectionRow = 0
        inside = false
        _ = endMusicStripHover(leaving: true)
        endMusicStripRequest()
        hoverEmphasized = false
        activitySelection = NotchActivitySelection()
        activityPickerMenuOpen = false
        hoverState = NotchHoverState()
        openedByHover = false
        removeEventMonitors()
        removeScreenEdgeClickMonitors()
        removeCaptureControlsClickThrough()
        removeHiddenHoverMonitors()
        removeHoverExitMonitors()
        removePointerMonitors()
        releaseMonitor()
        musicTitleWork?.cancel(); musicTitleWork = nil
        capsuleMusicTitleShown = false
        closeMirrors()
        windowHost?.close()
        windowHost = nil
        displayID = nil
        syncPanelKey()
        hiddenInFullscreen = false
    }

    var reopeningDestination: (module: NotchModule, appPanel: Bool, sections: Bool) {
        if !expanded {
            let opensActivity = UserDefaults.standard.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
            let activity = notice?.notificationID != nil ? NotchModule.notifications
                : opensActivity ? compactActivity?.module : nil
            if let activity, modules.contains(activity) { return (activity, false, false) }
            if UserDefaults.standard.bool(forKey: DefaultsKey.notchReturnHome) {
                let saved = UserDefaults.standard.string(forKey: DefaultsKey.notchHomeModule) ?? ""
                switch NotchReopeningDestination(rawValue: saved) {
                case .appPanel: return (.music, false, false)
                case nil:
                    let home = NotchModule(rawValue: saved) ?? .music
                    return (modules.contains(home) ? home : modules.first ?? .music, false, false)
                }
            }
        }
        return (selected, false, false)
    }

    var reopeningModule: NotchModule {
        reopeningDestination.module
    }

    func openActivity(_ module: NotchModule) {
        let opensActivity = UserDefaults.standard.object(forKey: DefaultsKey.notchOpensActivity) as? Bool ?? true
        if opensActivity { open(module) } else { open() }
    }

    func openCountdownEvent() {
        let calendar = NotchCalendarService.shared
        calendar.revealing = calendar.countdown?.event.id
        openActivity(.calendar)
        if !expanded || selected != .calendar || showingSections || showingAppPanel { calendar.revealing = nil }
    }

    func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true, sections: Bool = false) {
        guard NotchSupport.isEnabled(), !suspended else { return }
        if captureControls != nil { expandCaptureControls(); return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard let panel else { return }
        let reopening = reopeningDestination
        let useReopeningSurface = module == nil && !expanded && !appPanel && !sections && metric == nil
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? reopening.module
        let appPanel = appPanel || (useReopeningSurface && reopening.appPanel)
        let sections = sections || (useReopeningSurface && reopening.sections)
        if useReopeningSurface && reopening.sections {
            sectionQuery = ""
            sectionRow = 0
            highlightedSection = destination
        }
        let metric = metric.flatMap { metricIsAvailable($0) ? $0 : nil }
        let closesCommandBar = showingCommandBar
        let changesPresentation = !expanded || selected != destination || closesCommandBar
            || showingAppPanel != appPanel || selectedMetric != metric || showingSections != sections
        if changesPresentation, destination == .tools, !appPanel, !sections, metric == nil {
            QuickLauncherService.shared.prepareForPresentation()
        }
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        if !expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        panel.acceptsKeyFocus = true
        hoverState.open()
        hoverWork?.cancel()
        if !expanded {
            detailHasPage = false
            showsKeyboardFocus = false
        }
        else if appPanel || metric != nil, !showingAppPanel, selectedMetric == nil { detailHasPage = true }
        if !expanded { removeHoverExitMonitors() }
        mutatePresentation(transitionContent: changesPresentation ? (expanded ? .replace : .reveal) : .none) {
            showingCommandBar = false
            showingAppPanel = appPanel
            showingSections = sections
            if selected != destination { selected = destination }
            if pinned { self.pinned = true }
            selectedMetric = metric
            peeking = false
            openedByHover = !takeFocus
            expanded = true
            if notice?.notificationID != nil { noticeWork?.cancel(); noticeWork = nil; notice = nil; noticeExpanded = false }
        }
        inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
        if closesCommandBar { commandBarDidClose() }
    }

    func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        let closesCommandBar = showingCommandBar
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        pinned = false
        clipboardPinnedOnly = false
        hoverWork?.cancel(); hoverWork = nil
        if noticeExpanded { noticeWork?.cancel(); noticeWork = nil }
        mutatePresentation(transitionContent: expanded || peeking || noticeExpanded ? .dismiss : .none) {
            if noticeExpanded { notice = nil; noticeExpanded = false }
            expanded = false
            openedByHover = false
            peeking = false
            selectedMetric = nil
            showingAppPanel = false
            showingSections = false
            showingCommandBar = false
            sectionQuery = ""
            highlightedSection = nil
            sectionRow = 0
        }
        panel?.acceptsKeyFocus = false
        resignPanelKey()
        if closesCommandBar { commandBarDidClose() }
        removeEventMonitors()
        syncVisibleConsumers()
        closeCapture?()
        MemoryRelief.soon()
    }

    func toggle() { expanded ? collapse() : open() }

    func resignPanelKey() {
        guard let panel else { return }
        panel.resignKey()
        guard NSApp.keyWindow === panel,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
              let next = NSApp.orderedWindows.first(where: {
                  $0 !== panel && $0.isVisible && $0.isOnActiveSpace && $0.canBecomeMain
              })
        else { return }
        next.makeKey()
    }

    func setMusicDetailsVisible(_ visible: Bool) {
        guard visible != musicDetailVisible else { return }
        mutatePresentation { musicDetailVisible = visible }
    }

    func selectTimerMode(_ mode: NotchTimerMode) {
        guard mode != NotchTimerSupport.savedMode() else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.notchTimerMode)
        refreshPresentation(transitionContent: .replace)
    }

    @discardableResult
    func showClipboard(toggle: Bool = false) -> Bool {
        guard acceptsUserInteraction, NotchSupport.routesClipboardWindow() else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel, !showingSections, !showingCommandBar { collapse() }
        else { open(.clipboard) }
        return true
    }

    func hover(_ entered: Bool) {
        guard running, !suspended, !hiddenAtRestInFullscreen || watchesHiddenHover else { removeHoverExitMonitors(); return }
        let point = NSEvent.mouseLocation
        let wasInside = inside
        let showedPicker = showsCompactActivityPicker
        inside = watchesHiddenHover ? geometry.contains(point, in: geometry.collapsed)
            && windowHost?.isConcealedForMissionControl == false
            : windowHost?.containsHover(point) == true || pointerOverChildWindow(point)
        hoverState.update(pointerInside: inside)
        let unnamesMusic = inside != wasInside && endMusicStripHover(leaving: !inside)
        let opensOnHover = hoverOpeningEnabled
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) && !showsCompactActivityPicker
        let emphasize = inside && !hiddenInFullscreen && !hiddenUntilHover && !expanded && !peeking && !dragPlaceholder
            && notice == nil && captureControls == nil && !opensOnHover
            && !PerformanceMode.reduceMotion
        if hoverEmphasized != emphasize || showedPicker != showsCompactActivityPicker || unnamesMusic {
            hoverEmphasized = emphasize
            if unnamesMusic { syncMenuSpaceMonitoring() }
            refreshPresentation()
        }
        defer { syncHoverExitMonitoring(entered: entered, point: point) }
        if !watchesHiddenHover { captureHover?(entered) }
        else if inside != wasInside { captureHover?(inside) }
        if captureControls != nil {
            updateCaptureControlsHover(wasInside: wasInside)
            return
        }
        guard !pinned, !heldDrag, !keepsWorkingSurface else {
            hoverWork?.cancel(); hoverWork = nil
            if !inside { releaseNotification() }
            return
        }
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        if showsCompactActivityPicker { return }
        if inside {
            if holdsNotification, let id = notice?.notificationID { holdNotification(id); return }
            guard !hoverState.suppressed, (notice == nil || hiddenUntilHover), !expanded, !peeking, !dragPlaceholder,
                  hoverOpeningEnabled else { return }
            if !hiddenInFullscreen, compactActivity != nil, compactActivityGeometry.compactActivityWingWidth > 0,
               !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed,
                      !self.expanded, !self.peeking, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      !self.showsCompactActivityPicker,
                      self.captureControls == nil, (self.notice == nil || self.hiddenUntilHover), !self.dragPlaceholder,
                      self.hoverOpeningEnabled,
                      self.windowHost?.blocksHoverReveal() == false,
                      self.geometry.contains(NSEvent.mouseLocation, in: self.watchesHiddenHover ? self.geometry.collapsed : self.surfaceSize) else { return }
                self.removeHoverExitMonitors()
                if UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else if holdsNotification
                    || NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, !self.inside,
                      self.windowHost?.containsHover(NSEvent.mouseLocation) != true,
                      !self.pointerOverChildWindow(NSEvent.mouseLocation) else { return }
                self.releaseNotification()
                guard !self.pinned, !self.heldDrag, !self.keepsWorkingSurface, self.captureControls == nil,
                      !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation),
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            let delay = NotchSupport.closeDelay()
            DispatchQueue.main.asyncAfter(deadline: .now() + (expanded || noticeExpanded ? delay : 0.12), execute: work)
        }
    }

    private func syncHoverExitMonitoring(entered: Bool, point: CGPoint) {
        let followsClosedHover = inside && !expanded && !peeking && notice == nil
            && (hoverWork?.isCancelled == false
                || hoverState.suppressed && hoverOpeningEnabled)
        let keepsMusicStrip = musicStripNamed || musicStripHeldSong != nil
        let watching = ((hoverEmphasized || followsClosedHover || keepsMusicStrip) && captureHover == nil
                || !entered && NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover))
            && captureControls == nil && !pinned && !heldDrag && !hiddenUntilHover && !keepsWorkingSurface
            && (!hoverExitMonitors.isEmpty || windowHost?.containsHover(point) == true)
        guard watching else { removeHoverExitMonitors(); return }
        guard hoverExitMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.hover(false)
        }) { hoverExitMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.hover(false)
            return event
        }) { hoverExitMonitors.append(token) }
    }

    private func removeHoverExitMonitors() {
        hoverExitMonitors.forEach(NSEvent.removeMonitor)
        hoverExitMonitors.removeAll()
    }

    private var holdsNotification: Bool {
        notice?.notificationID != nil && noticeCanPresent && !hiddenUntilHover
    }

    private func holdNotification(_ id: UUID) {
        noticeWork?.cancel(); noticeWork = nil
        guard !noticeExpanded, !hoverState.suppressed,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed, !self.pinned, !self.heldDrag,
                  !self.keepsWorkingSurface, self.holdsNotification, self.notice?.notificationID == id, !self.noticeExpanded,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                  self.geometry.contains(NSEvent.mouseLocation, in: self.surfaceSize) else { return }
            self.mutatePresentation(transitionContent: .reveal) { self.peeking = false; self.noticeExpanded = true }
            self.provideHapticFeedback()
        }
        hoverWork = work
        let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func releaseNotification() {
        guard let notice, notice.notificationID != nil else { return }
        if noticeExpanded { dismissNotice() }
        else if noticeWork == nil { scheduleNoticeDismissal(after: notice.event.duration) }
    }

    private func syncNoticeWithPreferences() {
        guard let notice else { return }
        if !NotchSupport.routes(notice.event) || (notice.notificationID != nil && hiddenUntilHover) {
            dismissNotice()
        }
    }

    private func scheduleNoticeDismissal(after duration: TimeInterval) {
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    var filteredSections: [NotchModule] {
        NotchSupport.filteredModules(modules, query: sectionQuery) { module in
            let language = L10n.shared.language
            let music = module == .music ? FeatureStrings.notch(language).music : ""
            return [module.title(language), module.rawValue, music].joined(separator: " ")
        }
    }

    func searchSections(_ query: String) {
        guard sectionQuery != query else { return }
        mutatePresentation {
            sectionQuery = query
            highlightedSection = filteredSections.first
        }
    }

    func toggleSections() {
        guard captureControls == nil, !heldDrag else { return }
        if showingSections {
            open(appPanel: showingAppPanel, metric: selectedMetric)
        } else {
            sectionQuery = ""
            sectionRow = 0
            highlightedSection = selected
            open(appPanel: showingAppPanel, metric: selectedMetric, sections: true)
        }
    }

    private var sectionRowLimits: (rows: Int, visible: Int) {
        let count = filteredSections.count
        return (NotchSectionPaging.rows(count: count, columns: geometry.sectionColumns), geometry.sectionRows(count: count))
    }

    private func revealHighlightedSection() {
        guard let target = highlightedSection, let index = filteredSections.firstIndex(of: target) else { return }
        let limits = sectionRowLimits
        let row = NotchSectionPaging.revealing(row: index / max(1, geometry.sectionColumns), first: sectionRow,
                                               rows: limits.rows, visible: limits.visible)
        if row != sectionRow { sectionRow = row }
    }

    func showSectionRow(_ row: Int) {
        let limits = sectionRowLimits
        let next = NotchSectionPaging.clamped(row, rows: limits.rows, visible: limits.visible)
        guard next != sectionRow else { return }
        sectionRow = next
        provideHapticFeedback()
    }

    func scrollSections(by rows: Int) { showSectionRow(sectionRow + rows) }

    private func handleScratchpadKey(_ event: NSEvent) -> Bool {
        guard selected == .scratchpad, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        return MainActor.assumeIsolated { WispIsland.shared.handleKey(event, in: panel) }
    }

    private func handleClipboardPasteKey(_ event: NSEvent) -> Bool {
        guard selected == .clipboard, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
        guard let index = NotchClipboardPastePress.index(keyCode: event.keyCode, commandOnly: commandOnly)
        else { return false }
        clipboardPastePress = NotchClipboardPastePress(serial: (clipboardPastePress?.serial ?? 0) &+ 1, index: index)
        return true
    }

    func activateQuickAction(_ action: NotchQuickAction) {
        guard NotchSupport.isEnabled(), action.isAvailable() else { return }
        switch action {
        case .settings: openSettings()
        case .pin: pinned.toggle()
        case .module(let module): select(module)
        case .control(let item):
            switch item {
            case .keepAwake: KeepAwakeManager.shared.toggle()
            case .microphone: MicMuteService.shared.toggle()
            case .screenshot: perform { ScreenshotService.shared.capture() }
            case .recording: perform { ScreenRecorderService.shared.toggle() }
            case .speedTest: showMetric(.network)
            case .panel: openAppPanel()
            case .mixer: select(.mixer)
            case .music: select(.music)
            case .timer: select(.timer)
            case .calendar: select(.calendar)
            case .commandBar: break
            case .scratchpad: openScratchpad()
            case .volume, .brightness, .keyboardLight: select(.music)
            }
        }
    }

    func select(_ module: NotchModule) {
        guard modules.contains(module) else { return }
        open(module)
    }

    func openScratchpad() {
        if !showScratchpad() { perform { ScratchpadService.shared.show() } }
    }

    @discardableResult
    func showScratchpad(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesScratchpad(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .scratchpad, !showingAppPanel, !showingSections, !showingCommandBar,
           selectedMetric == nil, let panel, panel.isKeyWindow || NSApp.keyWindow === panel { collapse() }
        else { open(.scratchpad) }
        return true
    }

    func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel, !showingSections, !showingCommandBar { collapse(); return }
        open(.music)
        return ()
    }

    func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .tools, !showingSections, !showingCommandBar { collapse() }
        else { open(.tools) }
        return true
    }

    func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(), acceptsUserInteraction else { return false }
        if toggle, expanded, selected == .files, !showingSections, !showingCommandBar { collapse() }
        else { open(.files) }
        return true
    }

    func showMetric(_ metric: MetricDetailKind, toggle: Bool = false) {
        guard metricIsAvailable(metric) else { return }
        if toggle, expanded, selectedMetric == metric, !showingSections, !showingCommandBar { collapse(); return }
        open(.system, metric: metric)
        if toggle { detailHasPage = false }
    }

    func updateFanDetailHeight(_ height: CGFloat) {
        guard expanded, selectedMetric == .fan, !showingAppPanel, !showingSections,
              height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        guard fanDetailHeight != measured else { return }
        fanDetailHeight = measured
        refreshPresentation()
    }

    func goBack() {
        let changesPresentation = selectedMetric != nil || showingAppPanel
        mutatePresentation(transitionContent: changesPresentation ? .replace : .none) { selectedMetric = nil; showingAppPanel = false }
        syncVisibleConsumers()
        if changesPresentation { provideHapticFeedback() }
    }

    private func stepBack() {
        guard captureControls == nil, !heldDrag else { return }
        if showingAppPanel || selectedMetric != nil {
            if detailHasPage { goBack() } else { collapse() }
        } else if let close = pageLayers[selected] {
            close()
        } else {
            collapse()
        }
    }

    func setPageLayer(_ module: NotchModule, close: (() -> Void)?) {
        pageLayers[module] = close
    }

    func provideHapticFeedback() {
        guard acceptsUserInteraction, panel?.isVisible == true, NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, internalDrag || NotchSupport.routesShelf() else { return }
        heldDrag = active && internalDrag
        if !heldDrag { shelfDragExitWork?.cancel(); shelfDragExitWork = nil }
        if active, !internalDrag, NotchSupport.revealsShelfDrag(), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
            if !inside, !pinned { hover(false) }
        }
        if active, dragPlaceholder, NotchMascotSupport.isEnabled() {
            NotificationCenter.default.post(name: .notchMascotDragMoved, object: nil)
        }
    }

    func shelfDragMoved(to point: CGPoint) {
        guard heldDrag, expanded, !pinned, windowHost?.containsHover(point) != true,
              !pointerOverChildWindow(point), !keepsWorkingSurface else {
            shelfDragExitWork?.cancel(); shelfDragExitWork = nil
            return
        }
        guard shelfDragExitWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.shelfDragExitWork = nil
            guard self.heldDrag, self.expanded, !self.pinned, !self.keepsWorkingSurface,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) != true,
                  !self.pointerOverChildWindow(NSEvent.mouseLocation) else { return }
            self.heldDrag = false
            self.collapse()
        }
        shelfDragExitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchSupport.closeDelay(), execute: work)
    }

    func presentCaptureControls(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        guard acceptsSystemFeedback else { cancel(); return }
        let closeCapture = detachCaptureIfClosingOnCollapse()
        pinned = false
        captureControlsCancel = cancel
        captureControls = options
        captureControlsCollapsed = true
        captureSelectionInProgress = false
        options.onSelectionProgressChange = { [weak self, weak options] active in
            guard let self, let options, self.captureControls === options else { return }
            self.setCaptureSelectionInProgress(active)
        }
        captureControlsSubscription = options.$selectedTool.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshPresentation()
                self?.updateCaptureControlsClickThrough()
                self?.scheduleCaptureControlsCollapse()
            }
        let closesCommandBar = showingCommandBar
        showingCommandBar = false
        expanded = false
        showingSections = false
        peeking = false
        notice = nil
        noticeExpanded = false
        hoverWork?.cancel()
        if closesCommandBar { commandBarDidClose() }
        removeEventMonitors()
        panel?.acceptsKeyFocus = true
        panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        refreshPresentation()
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installCaptureControlsClickThrough()
        syncVisibleConsumers()
        closeCapture?()
    }

    func collapseCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        captureControls?.hasFocusedControl = false
        captureControlsCollapsed = true
        refreshPresentation(animated: !captureSelectionInProgress)
        updateCaptureControlsClickThrough()
    }

    func expandCaptureControls() {
        guard captureControls != nil, !captureSelectionInProgress else { return }
        hoverWork?.cancel(); hoverWork = nil
        hoverState.open()
        captureControlsCollapsed = false
        refreshPresentation()
        panel?.makeKey()
        updateCaptureControlsClickThrough()
    }

    private func setCaptureSelectionInProgress(_ active: Bool) {
        guard captureControls != nil else { return }
        captureSelectionInProgress = active
        if active { collapseCaptureControls() }
        else {
            refreshPresentation()
            updateCaptureControlsClickThrough()
        }
    }

    func scheduleCaptureControlsCollapse(after delay: TimeInterval = 3) {
        captureControlsWork?.cancel(); captureControlsWork = nil
        guard let options = captureControls, !captureControlsCollapsed, !captureSelectionInProgress,
              !options.hasFocusedControl, !inside else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.captureControlsWork = nil
            guard !self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !options.hasFocusedControl, !self.trackingMenu,
                  self.panel?.attachedSheet == nil,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) != true else { return }
            self.collapseCaptureControls()
        }
        captureControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateCaptureControlsHover(wasInside: Bool) {
        guard let options = captureControls, !captureSelectionInProgress else { return }
        if !captureControlsCollapsed {
            if inside {
                captureControlsWork?.cancel(); captureControlsWork = nil
            } else if wasInside {
                scheduleCaptureControlsCollapse(after: NotchQuickAccessLayout.hoverExitDelay)
            } else if captureControlsWork == nil {
                scheduleCaptureControlsCollapse()
            }
            return
        }
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        guard inside, !hoverState.suppressed else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.hoverWork = nil
            guard self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !self.hoverState.suppressed,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) == true else { return }
            self.expandCaptureControls()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func updateCaptureControlsClickThrough() {
        guard let panel, captureControls != nil else { return }
        let point = NSEvent.mouseLocation
        let overControls = !captureSelectionInProgress && windowHost?.contains(point) == true
            && (!captureControlsCollapsed || windowHost?.containsHover(point) == true)
        windowHost?.setMouseEventsIgnored(!overControls)
        if panel.acceptsMouseMovedEvents != overControls { panel.acceptsMouseMovedEvents = overControls }
        hover(overControls)
    }

    private func installCaptureControlsClickThrough() {
        guard captureControlsMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                            .rightMouseDragged, .otherMouseDragged]
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.updateCaptureControlsClickThrough(); return event
        }) { captureControlsMonitors.append(token) }
        updateCaptureControlsClickThrough()
    }

    private func removeCaptureControlsClickThrough() {
        captureControlsMonitors.forEach(NSEvent.removeMonitor)
        captureControlsMonitors.removeAll()
        windowHost?.setMouseEventsIgnored(false)
        panel?.acceptsMouseMovedEvents = false
    }

    private func missionControlDidRestore() {
        if captureControls != nil { updateCaptureControlsClickThrough() }
        else { hover(windowHost?.containsHover(NSEvent.mouseLocation) == true) }
        schedulePointerFollow()
    }

    func endCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        captureControls?.onSelectionProgressChange = nil
        geometry.compactSideRoom = nil
        captureControls = nil
        captureControlsCollapsed = false
        captureSelectionInProgress = false
        captureControlsSubscription = nil
        captureControlsCancel = nil
        removeCaptureControlsClickThrough()
        panel?.level = NotchPanel.normalLevel
        panel?.acceptsKeyFocus = false
        resignPanelKey()
        refreshPresentation()
        syncVisibleConsumers()
    }

    func cancelCaptureControls() { captureControlsCancel?() }

    func openSettings() {
        collapse()
        EverythingSettingsRouter.shared.tab = .island
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    func openSettings(showing module: NotchModule) {
        openSettings()
    }

    func perform(_ action: @escaping () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async(execute: action) }
    }

    var canAcceptFileDrop: Bool {
        acceptsUserInteraction && captureControls == nil && modules.contains(.files)
            && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
    }

    func beginFileDrop(_ pasteboard: NSPasteboard) {
        guard canAcceptFileDrop else { return }
        choosingFileDropDestination = NotchFileToolsService.shared.mediaDropContent(for: pasteboard) != nil
        targetsMediaDrop = false
        open(.files, takeFocus: false)
    }

    @discardableResult
    func updateFileDrop(at point: CGPoint) -> Bool {
        let targeted = choosingFileDropDestination
            && NotchFileToolsSupport.mediaDropArea(in: expandedGeometry, size: surfaceSize).contains(point)
        if targetsMediaDrop != targeted { targetsMediaDrop = targeted }
        return !targeted || NotchFileToolsService.shared.canAcceptMediaDrop
    }

    func endFileDrop() {
        let changed = choosingFileDropDestination
        if changed { choosingFileDropDestination = false }
        if targetsMediaDrop { targetsMediaDrop = false }
        if changed, acceptsUserInteraction { refreshPresentation() }
    }

    func keepFileInteractionOpen(_ active: Bool) {
        fileInteractionActive = active
        hover(false)
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        defer { endFileDrop() }
        guard canAcceptFileDrop else { return false }
        let optimize = choosingFileDropDestination && targetsMediaDrop
        let accepted = optimize
            ? NotchFileToolsService.shared.openMediaDrop(pasteboard)
            : ShelfService.shared.acceptDrop(pasteboard: pasteboard)
        if accepted {
            heldDrag = false
            dragPlaceholder = false
            if !optimize { NotchFileToolsService.shared.hideMedia() }
            open(.files)
            reactMascot(.celebrate, patience: 30)
        }
        return accepted
    }

    @discardableResult
    func show(_ incoming: NotchNotice) -> Bool {
        guard showsSystemFeedback, NotchSupport.routes(incoming.event),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event, held: noticeExpanded) else { return false }
        noticeWork?.cancel(); noticeWork = nil
        var incoming = incoming
        if incoming.notification != nil, let shown = notice, shown.notification != nil, noticeCanPresent, !noticeExpanded {
            incoming.minimumWings = shown.wings(in: geometry)
        }
        let keepsPreview = noticeExpanded && incoming.notificationID != nil
            && windowHost?.containsHover(NSEvent.mouseLocation) == true
        let transition: NotchContentTransition = !noticeCanPresent ? .none
            : incoming.event == .track ? (notice?.event == .track && !noticeExpanded ? .none : .replace)
            : notice == nil ? .reveal : notice?.event != incoming.event || noticeExpanded ? .replace : .none
        let mascotFrom = mascotNoticeBridgeStart(for: incoming)
        noticeFitsInPlace = noticeCanPresent && !noticeExpanded && !keepsPreview && notice?.event == incoming.event
        mutatePresentation(transitionContent: transition) {
            notice = incoming
            noticeExpanded = keepsPreview
        }
        if let mascotFrom { bridgeMascotIntoNotice(incoming, from: mascotFrom) }
        if let id = incoming.notificationID, holdsNotification, windowHost?.containsHover(NSEvent.mouseLocation) == true {
            hoverWork?.cancel(); hoverWork = nil
            inside = true
            holdNotification(id)
        } else {
            scheduleNoticeDismissal(after: incoming.event.duration)
        }
        return true
    }

    func activateNotice(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice else { return }
        if let id = selectedNotice.notificationID {
            guard NotchNotificationService.shared.openingID == nil else { return }
            settleNotificationHover()
            NotchNotificationService.shared.open(id) { [weak self] result in
                guard let self else { return }
                if self.notice?.notificationID == id { self.dismissNotice() }
                if result == .unavailable || result == .uncertain { self.open(.notifications) }
            }
            return
        }
        open(selectedNotice.event == .download ? .downloads : selectedNotice.event == .timer ? .timer
             : selectedNotice.event == .accessory ? .system : selectedNotice.event == .systemNotification ? .notifications
             : selectedNotice.event == .clipboard ? .clipboard : selectedNotice.event == .agents ? .agents
             : selectedNotice.event == .track ? .music : selectedNotice.event == .microphone ? .mixer
             : selectedNotice.event == .watch ? .watch : .music)
    }

    private func scheduleTrackNotice() {
        trackWork?.cancel()
        if heldMusic == nil, let presentedMusic { heldMusic = presentedMusic }
        if heldMusic == nil { awaitsTrackNotice = true }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.trackWork = nil
            defer { self.releaseTrackHold() }
            guard !self.expanded, !self.peeking, !self.dragPlaceholder, self.captureControls == nil,
                  let playback = NotchMusicService.shared.playback, playback.isPlaying,
                  let title = playback.track.title, !title.isEmpty else { return }
            self.show(NotchNotice(event: .track, title: title, detail: playback.track.artist ?? "",
                                  symbol: "music.note"))
        }
        trackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func holdEndingTrack() {
        if heldMusic == nil, let presentedMusic { heldMusic = presentedMusic }
    }

    private func releaseTrackHold() {
        if heldMusic != nil {
            heldMusic = nil
            fitNamedMusicStrip()
        }
        guard awaitsTrackNotice else { return }
        awaitsTrackNotice = false
        syncMenuSpaceMonitoring()
        if notice == nil { refreshPresentation() }
    }

    func showBrightness(_ level: Double) -> Bool {
        let text = FeatureStrings.notch(L10n.shared.language)
        return show(NotchNotice(event: .brightness, title: text.brightness,
                                detail: "",
                                symbol: level < 0.5 ? "sun.min.fill" : "sun.max.fill", level: level))
    }

    @discardableResult
    func showKeyboardLight(_ level: Double) -> Bool {
        guard level.isFinite, (0...1).contains(level) else { return false }
        if ownsLevelAdjustment(.keyboardLight) { return true }
        return show(NotchNotice(event: .keyboardLight,
                                title: FeatureStrings.brightness(L10n.shared.language).keyboardLight,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "keyboard", level: level))
    }

    @discardableResult
    func showMicrophone(muted: Bool) -> Bool {
        guard noticeCanPresent else { return false }
        let text = L10n.shared.s
        return show(NotchNotice(event: .microphone, title: "",
                                detail: muted ? text.micMutedHUD : text.micUnmutedHUD,
                                symbol: muted ? "mic.slash.fill" : "mic.fill", mascot: muted ? .hush : .perk))
    }

    func retractMicrophoneNotice() {
        guard notice?.event == .microphone else { return }
        dismissNotice()
    }

    func dismissNotification(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice, let id = selectedNotice.notificationID else { return }
        settleNotificationHover()
        NotchNotificationService.shared.dismiss(id)
        dismissNotice()
    }

    private func settleNotificationHover() {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
    }

    private func dismissNotice() {
        noticeWork?.cancel(); noticeWork = nil
        endDeparture()
        let transition: NotchContentTransition = notice == nil || !noticeCanPresent ? .none
            : notice?.event == .track ? .replace
            : noticeExpanded ? .dismiss : .depart
        let departing = transition == .depart ? notice : nil
        let mascotBack = mascotNoticeBridgeBackStart(from: departing)
        mutatePresentation(transitionContent: transition) {
            departingNotice = departing
            notice = nil
            noticeExpanded = false
        }
        if let mascotBack { bridgeMascotHome(from: mascotBack) }
        guard departingNotice != nil else { return }
        guard windowHost?.departsContent == true else { endDeparture(); return }
        let work = DispatchWorkItem { [weak self] in self?.endDeparture() }
        departureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.departureHidden, execute: work)
    }

    private func endDeparture() {
        departureWork?.cancel(); departureWork = nil
        guard departingNotice != nil else { return }
        departingNotice = nil
        windowHost?.finishDeparture()
    }

    private var noticeCanPresent: Bool {
        !expanded && !dragPlaceholder && captureControls == nil
    }

    func presentCapture(id: UUID, content: AnyView, actions: AnyView? = nil, height: CGFloat,
                        takeFocus: Bool, closeOnCollapse: Bool, fallback: @escaping () -> Void,
                        close: @escaping () -> Void, dismiss: @escaping () -> Void,
                        hover: @escaping (Bool) -> Void) -> Bool {
        guard acceptsSystemFeedback, NotchSupport.routes(.capture) else { return false }
        let keepOpen = expanded && pinned
        captureID = id
        captureContentHeight = height
        captureContent = content
        captureActions = actions
        captureFallback = fallback
        captureClose = close
        captureDismiss = dismiss
        captureHover = hover
        captureClosesOnCollapse = closeOnCollapse
        open(.captures, pinned: keepOpen,
             takeFocus: takeFocus, feedback: false)
        captureHover?(inside)
        return true
    }

    func updateCaptureHeight(id: UUID, height: CGFloat) {
        guard captureID == id, captureContent != nil, height.isFinite, height > 0,
              captureContentHeight != height else { return }
        captureContentHeight = height
        refreshPresentation()
    }

    func isCaptureVisible(id: UUID) -> Bool {
        acceptsSystemFeedback && expanded && selected == .captures
            && !showingAppPanel && !showingSections && !showingCommandBar && selectedMetric == nil
            && captureControls == nil && captureID == id && captureContent != nil
    }

    func removeCapture(id: UUID) {
        guard captureID == id else { return }
        clearCapture()
        if expanded, selected == .captures, !showingSections, !showingCommandBar {
            if pinned { refreshPresentation() }
            else { collapse() }
        }
    }

    private func clearCapture() {
        captureID = nil
        captureContent = nil
        captureActions = nil
        captureContentHeight = nil
        captureFallback = nil
        captureClose = nil
        captureDismiss = nil
        captureHover = nil
        captureClosesOnCollapse = false
    }

    private func detachCaptureIfClosingOnCollapse() -> (() -> Void)? {
        guard captureClosesOnCollapse else { return nil }
        let close = captureClose
        clearCapture()
        return close
    }

    private func mutatePresentation(transitionContent: NotchContentTransition = .none, _ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        refreshPresentation(transitionContent: transitionContent)
    }

    private func finishMusicDeparture() {
        musicDepartureWork?.cancel(); musicDepartureWork = nil
        guard departingMusic != nil else { return }
        departingMusic = nil
        if windowHost?.departsContent == true { windowHost?.finishDeparture() }
    }

    private func compactMusicTransition(_ requested: NotchContentTransition, animated: Bool) -> NotchContentTransition {
        let musicVisible = compactMusicIsVisible
        let canKeepDeparting = !musicVisible && compactActivity == nil && !expanded && !peeking
            && notice == nil && !dragPlaceholder && captureControls == nil
        if departingMusic != nil {
            if canKeepDeparting && requested == .none && animated
                && !PerformanceMode.reduceMotion { return .none }
            musicDepartureWork?.cancel(); musicDepartureWork = nil
            departingMusic = nil
            return requested == .none ? (animated ? .reveal : .replace) : requested
        }
        guard requested == .none, animated, !PerformanceMode.reduceMotion,
              panel?.isVisible == true, let presentedMusic, !musicVisible else { return requested }
        if canKeepDeparting {
            departingMusic = heldMusic ?? presentedMusic
            return .depart
        }
        return !expanded && !peeking && compactActivity != nil && notice == nil ? .replace : requested
    }

    private func rememberPresentedMusic(playback: NotchPlayback?, artwork: NSImage?, tint: NotchArtworkTint?) {
        guard compactMusicIsVisible, panel?.isVisible == true, let playback else {
            presentedMusic = nil
            if heldMusic != nil { heldMusic = nil }
            return
        }
        var shown = musicStripSnapshot(for: NotchCompactMusicSnapshot(playback: playback, artwork: artwork,
                                                                      tint: tint, geometry: compactActivityGeometry))
        shown.namedWing = namedMusicWings?.leading
        shown.namesSong = musicStripNamesSong
        presentedMusic = shown
    }

    func refreshPresentation(animated: Bool = true, transitionContent: NotchContentTransition = .none) {
        let fitsInPlace = noticeFitsInPlace && notice != nil && !noticeExpanded
            || musicStripFitsInPlace && compactMusicIsVisible
        noticeFitsInPlace = false
        musicStripFitsInPlace = false
        var releasedMusicStrip = false
        if !compactMusicIsVisible {
            musicNamingWork?.cancel(); musicNamingWork = nil
            if musicStripPointer != nil { musicStripPointer = nil }
            if !(inside && windowHost?.containsHover(NSEvent.mouseLocation) == true) {
                releasedMusicStrip = endMusicStripHover(leaving: true)
            }
        }
        defer { if releasedMusicStrip { syncMenuSpaceMonitoring() } }
        syncMascotKeepAwake()
        syncMascotAgents()
        activitySelection.reconcile(available: compactActivities)
        if fullscreenCompact {
            finishMusicDeparture()
            presentedMusic = nil
        }
        syncHiddenHoverMonitoring()
        defer {
            schedulePointerFollow()
            syncMirrors()
            flushMascotReaction()
            mascotRestedInView = mascotRestsInView && !expanded && !hiddenUntilHover
        }
        if hiddenUntilHover || (captureControls != nil && captureSelectionInProgress) {
            finishMusicDeparture()
            presentedMusic = nil
            if heldMusic != nil { heldMusic = nil }
            if hiddenUntilHover { windowHost?.hide(animated: animated, transitionContent: transitionContent) }
            else { windowHost?.hide(animated: false) }
            removeScreenEdgeClickMonitors()
            return
        }
        let open = expanded || peeking || notice != nil || dragPlaceholder || captureControls != nil
        guard open || (!hiddenAtRestInFullscreen && (geometry.isNotched || geometry.compactSideRoom != nil)) else {
            finishMusicDeparture()
            presentedMusic = nil
            if heldMusic != nil { heldMusic = nil }
            windowHost?.hide(animated: animated, transitionContent: transitionContent)
            removeScreenEdgeClickMonitors()
            return
        }
        let access = NotchQuickAccessConfiguration.current()
        let size = surfaceSize
        let contentTransition = compactMusicTransition(transitionContent, animated: animated)
        if captureControls == nil {
            panel?.level = hiddenInFullscreen && !geometry.isNotched && !NotchSupport.coversMenus()
                ? NotchPanel.fullscreenLevel : NotchPanel.normalLevel
        }
        if let windowHost, windowHost.targetSize != size { objectWillChange.send() }
        windowHost?.setOutline(enabled: !fullscreenCompact && UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled),
                               color: compactActivityIsVisible && compactActivity == .timer ? .systemOrange : .white)
        if mascotBridging, !mascotBridgeTargetShows { endMascotBridgeNow(fading: true) }
        if mascotRestedInView, compactActivity != nil, !mascotLingers,
           !PerformanceMode.reduceMotion {
            NotificationCenter.default.post(name: .notchMascotRestYields, object: nil)
        }
        var presented = expanded ? expandedGeometry : geometry
        presented.surfaceShift = surfaceShift
        windowHost?.present(size: size, geometry: presented, animated: animated,
                            transitionContent: contentTransition,
                            quickAccess: expanded && captureControls == nil && !showingCommandBar && !access.buttons.isEmpty
                                ? access : nil,
                            revealFromHidden: !hiddenInFullscreen && captureControls == nil
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                            usesGlass: !fullscreenCompact && usesGlassSurface,
                            steady: fitsInPlace)
        captureControls?.onCaptureControlsSurfaceChange?(
            geometry.screen, geometry.floatingDrop + size.height)
        if windowHost?.containsHover(NSEvent.mouseLocation) != true { hoverState.update(pointerInside: false) }
        let activationRect: CGRect
        if captureControls != nil {
            activationRect = captureControlsCollapsed ? CGRect(origin: .zero, size: size) : .zero
        } else if notice != nil || dragPlaceholder {
            activationRect = .zero
        } else if showsCompactActivityPicker {
            let strip = compactActivityGeometry.compactActivitySize
            activationRect = compactActivityGeometry.activationArea(
                in: strip, hasHeader: false, compactActivity: true)
                .offsetBy(dx: (size.width - strip.width) / 2, dy: 0)
        } else {
            activationRect = (expanded ? expandedGeometry : compactActivityIsVisible ? compactActivityGeometry : geometry)
                .activationArea(in: size, hasHeader: expanded || peeking, compactActivity: compactActivityIsVisible, expandedHeader: expanded)
                .offsetBy(dx: -surfaceShift, dy: 0)
        }
        let text = FeatureStrings.notch(L10n.shared.language)
        windowHost?.setActivationArea(activationRect, title: expanded ? text.collapse : text.open,
            willPress: { [weak self] in
                guard let self else { return }
                self.hoverWork?.cancel()
                if !(self.geometry.floats && self.musicStripShowsControl) { self.hoverState.close(pointerInside: true) }
            }, activate: { [weak self] in
                guard let self else { return }
                if self.captureControls != nil { self.expandCaptureControls() }
                else if self.geometry.floats, self.musicStripShowsControl { self.toggleMusicStripSong() }
                else if !self.expanded, self.compactActivity == .calendar {
                    self.openCountdownEvent()
                } else { self.toggle() }
            })
        if panel?.isVisible != true, mirrorHeldForArrival == nil { panel?.orderFrontRegardless() }
        let music = NotchMusicService.shared
        rememberPresentedMusic(playback: music.playback, artwork: music.artwork, tint: music.artworkTint)
        if contentTransition == .depart {
            if windowHost?.departsContent == true {
                let work = DispatchWorkItem { [weak self] in self?.finishMusicDeparture() }
                musicDepartureWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.departureHidden, execute: work)
            } else { finishMusicDeparture() }
        }
        syncScreenEdgeClicks()
    }

    private func syncHiddenHoverMonitoring() {
        if fullscreenCompact, !hoverOpeningEnabled {
            hoverWork?.cancel(); hoverWork = nil
            removeHoverExitMonitors()
        }
        guard running, !suspended, watchesHiddenHover, windowHost != nil else {
            removeHiddenHoverMonitors()
            return
        }
        guard hiddenHoverMonitors.isEmpty else { return }
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.hover(true)
        }) { hiddenHoverMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.hover(true)
            return event
        }) { hiddenHoverMonitors.append(token) }
    }

    private func removeHiddenHoverMonitors() {
        hiddenHoverMonitors.forEach(NSEvent.removeMonitor)
        hiddenHoverMonitors.removeAll()
    }

    private func syncPointerFollowing() {
        guard running, !suspended, followsPointer, windowHost != nil, NSScreen.screens.count > 1 else {
            removePointerMonitors()
            return
        }
        guard pointerMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.schedulePointerFollow()
        }) { pointerMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.schedulePointerFollow()
            return event
        }) { pointerMonitors.append(token) }
    }

    private func removePointerMonitors() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
        pointerFollowWork?.cancel(); pointerFollowWork = nil
    }

    private var canFollowPointer: Bool {
        !expanded && !peeking && notice == nil && captureControls == nil && !heldDrag
            && !choosingFileDropDestination && !keepsWorkingSurface && heldMusic == nil
    }

    private func schedulePointerFollow() {
        guard followsPointer, windowHost != nil else { return }
        guard !NSMouseInRect(NSEvent.mouseLocation, geometry.screen, false) else {
            pointerFollowWork?.cancel(); pointerFollowWork = nil
            return
        }
        guard pointerFollowWork == nil, canFollowPointer else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pointerFollowWork = nil
            self.windowHost?.whenSettled { [weak self] in self?.followPointer() }
        }
        pointerFollowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pointerFollowDelay, execute: work)
    }

    private func followPointer() {
        guard running, !suspended, followsPointer, canFollowPointer,
              windowHost?.isConcealedForMissionControl == false,
              let screen = NSScreen.withMouse, screen.notchDisplayID != displayID else { return }
        move(to: screen)
    }

    private func move(to screen: NSScreen) {
        guard let host = windowHost else { return }
        let destination = screen.notchDisplayID
        let reveal = host.canRelocateOnScreen()
        relocationTicket += 1
        let ticket = relocationTicket
        let origin = displayID
        displayID = destination
        mirrorHeldForArrival = reveal ? destination : nil
        if reveal {
            syncMirrors()
            guard relocationTicket == ticket, windowHost === host else { return }
            if let origin { holdMusicWave(on: origin) }
            _ = host.orderOutForRelocation()
        } else {
            releaseMusicWave()
        }
        guard relocationTicket == ticket, windowHost === host else { return }
        updateScreen()
        guard relocationTicket == ticket, windowHost === host else { return }
        if reveal { mirrorHeldForArrival = displayID }
        invalidateMenuSpace()
        syncVisibleConsumers()
        refreshPresentation(animated: false)
        guard reveal, relocationTicket == ticket, windowHost === host else { return }
        let arrival = displayID
        let work = DispatchWorkItem { [weak self, weak host] in
            guard let self, let host, self.relocationTicket == ticket, self.windowHost === host else { return }
            guard self.running, !self.suspended else {
                self.cancelRelocation()
                host.hide(animated: false)
                host.cancelRelocation()
                self.syncMirrors()
                return
            }
            let missing = !NSScreen.screens.contains { $0.notchDisplayID == self.displayID }
            if missing {
                self.updateScreen()
                guard self.relocationTicket == ticket, self.windowHost === host else { return }
                self.invalidateMenuSpace()
                self.syncVisibleConsumers()
            }
            if missing || self.displayID != arrival {
                self.mirrorHeldForArrival = self.displayID
                self.refreshPresentation(animated: false)
                guard self.relocationTicket == ticket, self.windowHost === host else { return }
            }
            self.matchMusicWave()
            guard self.relocationTicket == ticket, self.windowHost === host else { return }
            host.orderFrontForRelocation()
            guard self.relocationTicket == ticket, self.windowHost === host else { return }
            self.mirrorHeldForArrival = nil
            self.keepMusicWave()
            self.syncMirrors()
            guard self.relocationTicket == ticket, self.windowHost === host else { return }
            self.releaseMusicWave()
            self.syncScreenEdgeClicks()
        }
        DispatchQueue.main.async(execute: work)
    }

    private func cancelRelocation() {
        relocationTicket += 1
        mirrorHeldForArrival = nil
        releaseMusicWave()
    }

    private func holdMusicWave(on id: CGDirectDisplayID) {
        guard let mirror = mirrors[id], mirror.model.shown else { return }
        mirror.host.holdWave()
    }

    private func matchMusicWave() {
        guard let id = displayID, let mirror = mirrors[id], mirror.model.shown else { return }
        windowHost?.matchWave(from: mirror.host.panel.contentView)
    }

    private func keepMusicWave() {
        guard let id = displayID, let mirror = mirrors[id] else { return }
        mirror.host.keepWave()
    }

    private func releaseMusicWave() {
        for mirror in mirrors.values { mirror.host.releaseWave() }
    }

    private func nameCapsuleSong() {
        guard heldMusic == nil else { return }
        musicTitleWork?.cancel()
        capsuleMusicTitleShown = true
        refreshCapsuleMusic()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.musicTitleWork = nil
            self.capsuleMusicTitleShown = false
            self.refreshCapsuleMusic()
        }
        musicTitleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.musicTitleDuration, execute: work)
    }

    private func refreshCapsuleMusic() {
        guard compactActivity == .music,
              geometry.floats || mirrors.values.contains(where: { $0.model.geometry.floats }) else { return }
        refreshPresentation()
    }

    // MARK: The closed music strip under the pointer

    func musicStripAnswers(_ part: NotchMusicStripPart) -> Bool {
        guard compactMusicIsVisible, !hiddenUntilHover else { return false }
        if showsCompactActivityPicker { return part == .bars }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return true }
        return !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands)
            && compactActivityGeometry.compactActivityWingWidth > 0
    }

    var musicStripNamesSong: Bool {
        musicStripNamed && musicStripAnswers(.cover)
    }

    var namedMusicWings: NotchNoticeWings? {
        guard musicStripNamesSong, !geometry.floats else { return nil }
        let live = NotchMusicService.shared.playback
        let track = (heldMusic ?? musicStripStandIn(for: live))?.playback.track ?? live?.track
        return NotchMusicStripLayout.namedWings(title: track?.title, artist: track?.artist, geometry: compactActivityGeometry,
                                                room: geometry.compactSideRoom ?? 0)
    }

    private func musicStripHolds(context: NotchPlaybackContext?, player: Int32?) -> Bool {
        guard let held = musicStripHeldSong else { return false }
        return context.map { $0 == held } ?? (player == held.pid)
    }

    func musicStripStandIn(for playback: NotchPlayback?) -> NotchCompactMusicSnapshot? {
        guard let playback, playback.commandContext == nil,
              musicStripHolds(context: nil, player: playback.track.appPID) else { return nil }
        return musicStripHeldMusic
    }

    private func musicStripSnapshot(for reading: NotchCompactMusicSnapshot) -> NotchCompactMusicSnapshot {
        guard let held = musicStripHeldSong else { return reading }
        if reading.playback.commandContext == held { musicStripHeldMusic = reading }
        return musicStripStandIn(for: reading.playback) ?? reading
    }

    private func fitNamedMusicStrip() {
        guard musicStripNamesSong, !geometry.floats else { return }
        musicStripFitsInPlace = true
        refreshPresentation()
    }

    var musicStripShowsControl: Bool {
        musicStripPointer == .bars && musicStripAnswers(.bars) && heldMusic == nil && musicStripCanToggle
    }

    private var musicStripCanToggle: Bool {
        let music = NotchMusicService.shared
        return music.canPerform(.toggle) || music.commandPending
    }

    func hoverMusicStrip(_ part: NotchMusicStripPart, entered: Bool) {
        guard entered else {
            if musicStripPointer == part { musicStripPointer = nil }
            if part == .cover { musicNamingWork?.cancel(); musicNamingWork = nil }
            return
        }
        guard musicStripAnswers(part) else { return }
        if musicStripPointer != part { musicStripPointer = part }
        guard part == .cover, !musicStripNamed, musicNamingWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.musicNamingWork = nil
            guard self.inside, self.musicStripPointer == .cover, self.musicStripAnswers(.cover) else { return }
            self.musicStripNamed = true
            self.musicStripFitsInPlace = true
            if self.geometry.floats { self.refreshCapsuleMusic() } else { self.refreshPresentation() }
            self.syncHoverExitMonitoring(entered: true, point: NSEvent.mouseLocation)
        }
        musicNamingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMusicStripLayout.namingDelay, execute: work)
    }

    private func endMusicStripHover(leaving: Bool) -> Bool {
        var changed = false
        if leaving {
            musicNamingWork?.cancel(); musicNamingWork = nil
            if musicStripPointer != nil { musicStripPointer = nil }
            if musicStripHeldSong != nil { musicStripHeldSong = nil; musicStripHeldMusic = nil; changed = true }
        }
        if musicStripNamed { musicStripNamed = false; changed = true }
        return changed
    }

    func activateMusicStrip() {
        guard musicStripShowsControl else { openActivity(.music); return }
        toggleMusicStripSong()
    }

    @discardableResult
    func toggleMusicStripSong() -> Bool {
        let music = NotchMusicService.shared
        guard heldMusic == nil, musicStripCanToggle, let playback = music.playback else { return false }
        let playing = musicStripRequest ?? playback.isPlaying
        guard music.send(.toggle, context: playback.commandContext) else { return music.commandPending }
        if playing && inside {
            musicStripHeldSong = playback.commandContext
            musicStripHeldMusic = presentedMusic
            syncHoverExitMonitoring(entered: true, point: NSEvent.mouseLocation)
        }
        guard playback.canSendCommandsDirectly else { return true }
        musicStripRequest = !playing
        musicRequestWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMusicStripRequest() }
        musicRequestWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        return true
    }

    private func endMusicStripRequest() {
        musicRequestWork?.cancel(); musicRequestWork = nil
        if musicStripRequest != nil { musicStripRequest = nil }
    }

    private func endMusicStripSong(_ playback: NotchPlayback?) {
        endMusicStripRequest()
        guard let held = musicStripHeldSong, playback?.commandContext != held else { return }
        if let playback, playback.track.appPID == held.pid {
            guard let context = playback.commandContext else { return }
            let shown = musicStripHeldMusic?.playback.track
            if playback.track.title == shown?.title, playback.track.artist == shown?.artist {
                musicStripHeldSong = context
                return
            }
        }
        musicStripHeldSong = nil
        musicStripHeldMusic = nil
        syncMenuSpaceMonitoring()
        refreshPresentation()
    }

    // MARK: Every display

    private struct NotchMirror {
        let host: NotchWindowHost
        let model: NotchMirrorModel
    }

    private func syncMirrors() {
        guard showsOnAllDisplays, running, !suspended, windowHost != nil else { closeMirrors(); return }
        let screens = NSScreen.screens
        for (id, mirror) in mirrors where !screens.contains(where: { $0.notchDisplayID == id }) {
            mirror.host.close()
            mirrors[id] = nil
        }
        let activity = compactActivity
        let hidesAtRest = NotchSupport.hidesUntilHover() && (activity == nil || !NotchSupport.hiddenShowsActivity())
        let outline = UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled)
        for screen in screens {
            let id = screen.notchDisplayID
            var base: NotchGeometry?
            if id != displayID || id == mirrorHeldForArrival, !hidesAtRest, !fullscreenDisplays.contains(id) {
                var geometry = baseGeometry(for: screen)
                geometry.compactSideRoom = mirrorSideRoom(on: screen, geometry: geometry)
                if geometry.isNotched || geometry.compactSideRoom != nil {
                    if id == mirrorHeldForArrival { continue }
                    base = geometry
                }
            }
            guard let base else {
                if let mirror = mirrors[id], mirror.model.shown {
                    mirror.model.shown = false
                    mirror.host.hide(animated: false)
                }
                continue
            }
            let (strip, size) = mirrorSurface(on: base, activity: activity)
            let mirror = mirrors[id] ?? makeMirror(geometry: base, size: size)
            mirrors[id] = mirror
            if mirror.model.outline != outline || mirror.model.timerOutline != (activity == .timer) {
                mirror.model.outline = outline
                mirror.model.timerOutline = activity == .timer
                mirror.host.setOutline(enabled: outline, color: activity == .timer ? .systemOrange : .white)
            }
            let sharing: NSWindow.SharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
            if mirror.host.panel.sharingType != sharing { mirror.host.panel.sharingType = sharing }
            let revealing = !mirror.model.shown
            let previous = mirror.model.activity
            guard mirror.model.update(geometry: base, strip: strip, size: size, activity: activity) || revealing else { continue }
            mirror.model.shown = true
            mirror.host.present(size: size, geometry: base, animated: !revealing,
                                transitionContent: !revealing && previous != activity ? .replace : .none)
            mirror.host.setActivationArea(CGRect(origin: .zero, size: size),
                                          title: FeatureStrings.notch(L10n.shared.language).open,
                                          willPress: {}, activate: { [weak self] in self?.bringIsland(to: id) })
            guard !mirror.host.panel.isVisible else { continue }
            if mirrorHeldForArrival != nil, let live = windowHost?.panel, live.isVisible, live.windowNumber > 0 {
                mirror.host.panel.order(.below, relativeTo: live.windowNumber)
            } else {
                mirror.host.panel.orderFrontRegardless()
            }
        }
    }

    private func mirrorSurface(on base: NotchGeometry, activity: NotchCompactActivity?) -> (strip: NotchGeometry, size: CGSize) {
        guard let activity else {
            return (base, base.restingSize(showsContent: !base.floats && (idleContent != .none || mascotShows(on: base))))
        }
        let companion = compactCompanion
        if base.floats { return (base, capsuleStripSize(for: activity, companion: companion, geometry: base)) }
        let strip = compactGeometry(for: activity, companion: companion, base: base)
        return (strip, strip.compactActivitySize)
    }

    private func mirrorSideRoom(on screen: NSScreen, geometry: NotchGeometry) -> CGFloat? {
        let hasMenuBar = NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar == screen
        guard NotchSupport.coversMenus() || !hasMenuBar else { return nil }
        return NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                           barHeight: geometry.menuBarHeight, occupied: [])
    }

    private func makeMirror(geometry: NotchGeometry, size: CGSize) -> NotchMirror {
        let model = NotchMirrorModel(geometry: geometry, size: size)
        let host = NotchWindowHost(content: AnyView(NotchMirrorView(service: self, mirror: model)),
                                   geometry: geometry, size: size,
                                   background: { AnyView(NotchWindowBackground(presentation: $0)) })
        host.panel.title = FeatureStrings.notch(L10n.shared.language).title
        return NotchMirror(host: host, model: model)
    }

    private func closeMirrors() {
        guard !mirrors.isEmpty else { return }
        mirrors.values.forEach { $0.host.close() }
        mirrors.removeAll()
    }

    private var showsCopies: Bool { mirrors.values.contains { $0.model.shown } }

    private func updateFullscreenDisplays() {
        guard showsOnAllDisplays, UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
        else { fullscreenDisplays = []; return }
        let covered = NotchAppFullscreen.coveredDisplays()
        guard let topology = SpaceWindowBridge.topology() else { fullscreenDisplays = covered; return }
        let separate = NSScreen.screensHaveSeparateSpaces
        fullscreenDisplays = Set(NSScreen.screens.map(\.notchDisplayID).filter {
            topology.isFullscreen(on: $0, separateSpaces: separate) || covered.contains($0)
        })
    }

    private func bringIsland(to id: CGDirectDisplayID) {
        guard running, !suspended, showsOnAllDisplays, id != displayID else { return }
        if expanded || peeking { collapse() }
        windowHost?.whenSettled { [weak self] in
            guard let self, self.running, !self.suspended, self.canFollowPointer,
                  let screen = NSScreen.screens.first(where: { $0.notchDisplayID == id }) else { return }
            self.move(to: screen)
            if self.compactActivity == .calendar { self.openCountdownEvent() } else { self.open() }
        }
    }

    private var screenEdgeClickArea: CGRect? {
        guard running, !suspended, !expanded, captureControls == nil, notice == nil,
              !dragPlaceholder, !heldDrag, let panel, panel.isVisible, !panel.ignoresMouseEvents else { return nil }
        let geometry = compactActivityIsVisible ? compactActivityGeometry : self.geometry
        let area = geometry.activationArea(in: surfaceSize, hasHeader: peeking, compactActivity: compactActivityIsVisible)
        guard !area.isEmpty else { return nil }
        let frame = geometry.frame(for: surfaceSize)
        return CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY, width: area.width, height: area.height)
    }

    private func syncScreenEdgeClicks() {
        guard screenEdgeClickArea != nil else { removeScreenEdgeClickMonitors(); return }
        guard screenEdgeClickMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleScreenEdgeEvent(event)
        }) { screenEdgeClickMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleScreenEdgeEvent(event)
            return event
        }) { screenEdgeClickMonitors.append(token) }
    }

    private func handleScreenEdgeEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown || screenEdgePressArea != nil else { return }
        guard let location = event.cgEvent?.location, let primary = NSScreen.withMenuBar else {
            screenEdgePressArea = nil
            return
        }
        handleScreenEdgeClick(event.type, at: CGPoint(x: location.x, y: primary.frame.maxY - location.y),
                              isNotchWindow: event.window === panel)
    }

    private func handleScreenEdgeClick(_ type: NSEvent.EventType, at point: CGPoint, isNotchWindow: Bool) {
        guard let area = screenEdgeClickArea else { screenEdgePressArea = nil; return }
        let local = CGPoint(x: point.x - area.minX, y: area.maxY - point.y)
        switch type {
        case .leftMouseDown:
            screenEdgePressArea = nil
            guard !isNotchWindow, !keepsWorkingSurface,
                  CGRect(x: 0, y: 0, width: area.width, height: 1 + (geometry.floatingGap ?? 0)).contains(local),
                  windowHost?.containsDestination(point) == true else { return }
            screenEdgePressArea = area
            hoverWork?.cancel(); hoverWork = nil
            hoverState.close(pointerInside: true)
        case .leftMouseUp:
            let pressedArea = screenEdgePressArea
            screenEdgePressArea = nil
            guard let pressed = pressedArea,
                  NotchSupport.screenEdgeArea(pressed, contains: point) || NotchSupport.screenEdgeArea(area, contains: point),
                  windowHost?.containsDestination(point) == true else { return }
            if compactActivity == .calendar { openCountdownEvent() } else { open() }
        case .leftMouseDragged:
            guard !NotchSupport.screenEdgeArea(area, contains: point),
                  !(screenEdgePressArea.map { NotchSupport.screenEdgeArea($0, contains: point) } ?? false) else { return }
            screenEdgePressArea = nil
        default:
            break
        }
    }

    private func removeScreenEdgeClickMonitors() {
        screenEdgeClickMonitors.forEach(NSEvent.removeMonitor)
        screenEdgeClickMonitors.removeAll()
        screenEdgePressArea = nil
    }

    private func stopMenuSpaceMonitoring() {
        menuSpaceTimer?.invalidate()
        menuSpaceTimer = nil
        menuSpaceGeneration += 1
    }

    private var displayHasMenuBar: Bool {
        NSScreen.screensHaveSeparateSpaces || NSScreen.withMenuBar?.frame == geometry.screen
    }

    private func syncMenuSpaceMonitoring() {
        guard !hiddenInFullscreen else { stopMenuSpaceMonitoring(); return }
        if running, !suspended, NotchSupport.coversMenus() || !displayHasMenuBar {
            stopMenuSpaceMonitoring()
            applyMenuSpace(NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                       barHeight: geometry.menuBarHeight, occupied: []))
            return
        }
        guard AXIsProcessTrusted() else {
            stopMenuSpaceMonitoring()
            if geometry.compactSideRoom != nil {
                geometry.compactSideRoom = nil
                refreshPresentation(animated: false)
            }
            return
        }
        let wanted = running && !suspended && (!hiddenUntilHover || NotchSupport.hiddenShowsActivity())
            && !expanded && captureControls == nil
            && (idleContent != .none || compactActivity != nil || !geometry.isNotched || mascotWantsRoom)
        guard wanted else { stopMenuSpaceMonitoring(); return }
        guard menuSpaceTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.readMenuSpace() }
        timer.tolerance = 0.2
        menuSpaceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readMenuSpace()
    }

    private func invalidateMenuSpace() {
        menuSpaceGeneration += 1
        readMenuSpace()
    }

    private func screenParametersDidChange() {
        guard running, !suspended else { return }
        screenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.screenRefreshWork = nil
            guard self.running, !self.suspended else { return }
            self.invalidateMenuSpace()
            self.syncWithPreferences()
        }
        screenRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func readMenuSpace() {
        guard menuSpaceTimer != nil, !menuSpaceReading,
              let pid = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
                ?? (NSApp.isActive ? getpid() : nil) else { return }
        menuSpaceReading = true
        let generation = menuSpaceGeneration
        let geometry = geometry
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY
        let window = panel?.windowNumber ?? -1
        menuSpaceQueue.async { [weak self] in
            let room = NotchMenuBarSpace.measure(pid: pid, geometry: geometry,
                                                primaryTop: primaryTop, ownWindow: window)
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuSpaceReading = false
                guard self.menuSpaceTimer != nil else { return }
                guard self.menuSpaceGeneration == generation,
                      (NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
                        ?? (NSApp.isActive ? getpid() : nil)) == pid else {
                    self.readMenuSpace(); return
                }
                self.applyMenuSpace(room)
            }
        }
    }

    private func applyMenuSpace(_ room: CGFloat?) {
        guard geometry.compactSideRoom != room else { return }
        let previousSize = surfaceSize
        let grows = (room ?? 0) > (geometry.compactSideRoom ?? 0)
        geometry.compactSideRoom = room
        if previousSize != surfaceSize || panel?.isVisible != true || room == nil {
            refreshPresentation(animated: grows)
        }
    }

    private static let hasLid = BrightnessService.lidClosed() != nil

    private var displayPreference: NotchDisplay {
        NotchDisplay(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic
    }

    private static func displayLayout(_ screens: [NSScreen]) -> (builtIn: [Bool], notched: [Bool], main: Int) {
        (screens.map { CGDisplayIsBuiltin($0.notchDisplayID) != 0 },
         screens.map { $0.safeAreaInsets.top > 0 },
         screens.firstIndex(where: { $0 === NSScreen.withMenuBar }) ?? 0)
    }

    private func screenIndex(in screens: [NSScreen]) -> Int? {
        let preference = displayPreference
        var pointer: Int?
        if preference == .pointer || preference == .all {
            let mouse = NSEvent.mouseLocation
            pointer = screens.firstIndex { $0.notchDisplayID == displayID }
                ?? screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) }
        }
        let layout = Self.displayLayout(screens)
        return NotchSupport.screenIndex(preference: preference, builtIn: layout.builtIn, notched: layout.notched,
                                        main: layout.main, pointer: pointer, hasLid: Self.hasLid)
    }

    static func reachesDisplayWithoutNotch(_ preference: NotchDisplay) -> Bool {
        let layout = displayLayout(NSScreen.screens)
        return NotchSupport.reachesDisplayWithoutNotch(preference: preference, builtIn: layout.builtIn,
                                                       notched: layout.notched, main: layout.main, hasLid: hasLid)
    }

    private func withdrawFromMissingScreen() {
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = captureFallback
        clearCapture()
        tearDownPresentation()
        NotchTimerService.shared.suspend()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        fallback?()
    }

    private func updateScreen() {
        let screens = NSScreen.screens
        menuBarMeasurements.retainDisplays(screens.map(\.notchDisplayID))
        guard let index = screenIndex(in: screens) else { withdrawFromMissingScreen(); return }
        let screen = screens[index]
        displayID = screen.notchDisplayID
        var next = baseGeometry(for: screen)
        let sameMenuBar = next.hasSameMenuBar(as: geometry)
        if sameMenuBar { next.compactSideRoom = geometry.compactSideRoom }
        let access = NotchQuickAccessConfiguration.current()
        next.quickAccessBottomInset = access.hasBottom ? NotchQuickAccessLayout.gutter : 0
        next.sectionsButtonInRow = false
        if next != geometry { menuSpaceGeneration += 1; geometry = next }
        if !sameMenuBar { readMenuSpace() }
        if windowHost == nil {
            windowHost = NotchWindowHost(content: AnyView(NotchView(service: self)), geometry: geometry, size: surfaceSize,
                                        background: { AnyView(NotchWindowBackground(presentation: $0)) },
                                        quickAccess: { AnyView(NotchQuickAccessView(service: self, motion: $0, backdrop: $1)) })
            windowHost?.missionControlDidRestore = { [weak self] in self?.missionControlDidRestore() }
            windowHost?.setHoverHandler { [weak self] in self?.hover($0) }
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && !ShelfService.shared.isInternalDragActive
                        && ShelfService.shared.canAcceptPasteboard(pasteboard)
                },
                enter: { [weak self] in self?.beginFileDrop($0) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.endFileDrop()
                    self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
                },
                update: { [weak self] in self?.updateFileDrop(at: $0) == true }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        updateFullscreenVisibility(displayID: screen.notchDisplayID)
    }

    private func baseGeometry(for screen: NSScreen) -> NotchGeometry {
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        return NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                             cameraWidth: cameraWidth,
                             layout: NotchSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSize) ?? "") ?? .spacious,
                             menuBarHeight: menuBarMeasurements.height(
                                displayID: screen.notchDisplayID, frame: screen.frame,
                                visibleTop: screen.visibleFrame.maxY, scale: screen.backingScaleFactor,
                                statusBarThickness: NSStatusBar.system.thickness),
                             customWidth: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomWidth),
                             customHeight: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomHeight),
                             cameraFit: NotchCameraFit.current(), silhouette: NotchSilhouette.current(),
                             capsuleFit: NotchCapsuleFit.current(),
                             hideMenuBarGap: UserDefaults.standard.bool(forKey: DefaultsKey.notchHideMenuBarGap),
                             outline: UserDefaults.standard.bool(forKey: DefaultsKey.notchOutlineEnabled),
                             barEdge: 1 / max(1, screen.backingScaleFactor))
    }

    private func updateFullscreenVisibility(displayID: CGDirectDisplayID) {
        let hidden = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
            && (SpaceWindowBridge.topology()?.isFullscreen(on: displayID, separateSpaces: NSScreen.screensHaveSeparateSpaces) == true
                || NotchAppFullscreen.coveredDisplays().contains(displayID))
        guard hidden != hiddenInFullscreen else { return }
        hiddenInFullscreen = hidden
        if hidden {
            hoverWork?.cancel(); hoverWork = nil
            hoverEmphasized = false
            heldDrag = false
            dragPlaceholder = false
            cancelCaptureControls()
            noticeWork?.cancel(); noticeWork = nil
            endDeparture()
            notice = nil
            noticeExpanded = false
            collapse()
        }
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private func fullscreenEnvironmentDidChange() {
        guard running, !suspended,
              hiddenInFullscreen || UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
        else { return }
        let wasHidden = hiddenInFullscreen
        updateScreen()
        updateFullscreenDisplays()
        syncMirrors()
        guard hiddenInFullscreen != wasHidden else { return }
        syncVisibleConsumers()
        refreshPresentation(animated: false)
    }

    private func syncAppFullscreenMonitoring() {
        guard running, !suspended, UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen) else {
            stopAppFullscreenMonitoring()
            return
        }
        appFullscreenDisplays = NotchAppFullscreen.coveredDisplays()
        guard appFullscreenTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.readAppFullscreen() }
        timer.tolerance = 0.3
        appFullscreenTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAppFullscreenMonitoring() {
        appFullscreenTimer?.invalidate()
        appFullscreenTimer = nil
        appFullscreenDisplays = []
    }

    private func readAppFullscreen() {
        let covered = NotchAppFullscreen.coveredDisplays()
        guard covered != appFullscreenDisplays else { return }
        appFullscreenDisplays = covered
        fullscreenEnvironmentDidChange()
    }

    private func installObservers() {
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in
            guard let self else { return }
            self.activityPickerMenuOpen = self.showsCompactActivityPicker
            self.trackingMenu = true
            self.hoverWork?.cancel()
        }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            guard let self else { return }
            self.trackingMenu = false
            self.activityPickerMenuOpen = false
            self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
            self.refreshPresentation()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screenParametersDidChange()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            self?.schedulePreferenceSync()
        }
        observe(.default, NSWindow.didBecomeKeyNotification) { [weak self] in self?.syncPanelKey() }
        observe(.default, NSWindow.didResignKeyNotification) { [weak self] in self?.syncPanelKey() }
        session.onConsole = SessionActivity.shared.isActive
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.schedulePreferenceSync()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.fullscreenEnvironmentDidChange()
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.applicationDidActivate() }
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification) { [weak self] in self?.panelDidResignKey() }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.updateSession { $0.sleeping = true }
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.updateSession { $0.sleeping = false; $0.screenSaverRunning = false }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = true }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = false }
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = false }
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = true }
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.updateSession { $0.locked = true }
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.updateSession { $0.locked = false; $0.screenSaverRunning = false }
            self?.reactMascot(.wakeUp)
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { [weak self] in
            self?.updateSession { $0.screenSaverRunning = true }
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { [weak self] in
            self?.updateSession { $0.screenSaverRunning = false }
        }
    }

    private func schedulePreferenceSync() {
        guard running, preferenceSyncWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.preferenceSyncWork = nil
            guard self.running else { return }
            self.syncWithPreferences()
        }
        preferenceSyncWork = work
        DispatchQueue.main.async(execute: work)
    }

    static let launcherIdentifiers: Set<String> = ["com.raycast.macos", "com.apple.Spotlight"]

    static func launcherIsShowing() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "Raycast" || owner == "Spotlight",
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Height"] ?? 0) > 60 && (bounds["Width"] ?? 0) > 200
        }
    }

    func panelDidResignKey() {
        guard expanded, !pinned else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.expanded, Self.launcherIsShowing() else { return }
            self.collapse()
        }
    }

    private func applicationDidActivate() {
        guard !suspended else { return }
        fullscreenEnvironmentDidChange()
        invalidateMenuSpace()
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard identifier != Bundle.main.bundleIdentifier, identifier != AssistiveKeyboard.bundleID else { return }
        if expanded, Self.launcherIdentifiers.contains(identifier ?? "") || Self.launcherIsShowing() {
            collapse()
            return
        }
        panel?.resignKey()
        if expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        if expanded, !pinned, !keepsWorkingSurface, captureControls == nil,
           NotchSupport.closesOnActivation(openedByHover: openedByHover, clicked: clickedSinceOpening,
                                           pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true) {
            collapse()
        }
    }

    private func syncPanelKey() {
        let isKey = panel?.isKeyWindow == true
        if panelIsKey != isKey { panelIsKey = isKey }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    private func updateSession(_ change: (inout NotchSessionState) -> Void) {
        guard running else { return }
        let couldPresent = session.canPresent
        let timerCouldRun = session.canRunTimer
        let wasLocked = session.locked
        change(&session)
        if session.locked != wasLocked, session.locked ? session.hearsLockChange : session.onConsole,
           NotchLockScreenSupport.playsSounds() {
            NotchLockScreenService.shared.playSound(locking: session.locked)
        }
        if wasLocked, !session.locked { NotchLockScreenService.shared.sync(session) }
        if couldPresent != session.canPresent {
            if session.canPresent {
                syncWithPreferences()
            } else {
                let cancel = captureControlsCancel
                endCaptureControls()
                cancel?()
                captureClose?()
                clearCapture()
                tearDownPresentation()
                if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
                if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
            }
        }
        NotchLockScreenService.shared.sync(session)
        guard timerCouldRun != session.canRunTimer, !session.canPresent else { return }
        if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
        else { NotchTimerService.shared.suspend() }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        clickedSinceOpening = false
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.clickedElsewhere()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === self.panel, !self.showsKeyboardFocus {
                self.showsKeyboardFocus = true
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53,
               (self.panel?.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
            if event.type == .keyDown, event.window === self.panel, self.showingCommandBar { return event }
            if event.type == .keyDown, event.window === self.panel, self.captureControls == nil {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .command, event.charactersIgnoringModifiers == "," {
                    self.openSettings()
                    return nil
                }
                if modifiers == [.command, .option],
                   let module = NotchSupport.moduleShortcut(event.charactersIgnoringModifiers ?? "", modules: self.modules) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift],
                   let module = NotchSupport.adjacentModule(to: self.selected, modules: self.modules,
                                                           backwards: modifiers.contains(.shift)) {
                    self.select(module)
                    return nil
                }
                if self.handleScratchpadKey(event) { return nil }
                if self.handleClipboardPasteKey(event) { return nil }
            }
            if event.type == .keyDown, event.window === self.panel, self.selected == .tools, !self.showingAppPanel, !self.showingSections {
                let launcher = QuickLauncherService.shared
                let flow: QuickToolsSupport.GridFlow = launcher.isEditing
                    ? .rows(columns: NotchSupport.toolColumns)
                    : self.expandedGeometry.toolFlow(count: launcher.visibleItems.count)
                return launcher.handlePanelKey(event, flow: flow)
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                if let editor = self.panel?.firstResponder as? NSTextView, editor.isFieldEditor,
                   (editor.delegate as AnyObject?) is MixerPercentNativeTextField { return event }
                if PlainTextEditor.findBarHasKeyboard(in: self.panel) { return event }
                self.stepBack()
                return nil
            }
            let click = clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue))
            let islandWindow = self.ownsWindow(event.window)
            if click, islandWindow { self.clickedSinceOpening = true }
            if click, !islandWindow { self.clickedElsewhere() }
            return event
        }) { eventMonitors.append(token) }
    }

    private func clickedElsewhere() {
        guard !keepsSurfaceOnClick,
              windowHost?.contains(NSEvent.mouseLocation) != true,
              !mirrors.values.contains(where: { $0.model.shown && $0.host.contains(NSEvent.mouseLocation) }),
              (NSApp.delegate as? AppDelegate)?.isOverStatusItem(NSEvent.mouseLocation) != true,
              !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) else { return }
        if showsCapturePreview { captureDismiss?() } else { collapse() }
    }

    private func ownsWindow(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        return sequence(first: window, next: { $0.parent }).contains { $0 === panel }
    }

    private func pointerOverChildWindow(_ point: CGPoint) -> Bool {
        panel?.childWindows?.contains { $0.isVisible && $0.frame.contains(point) } == true
    }

    private func syncGestures() {
        if !NotchGestureSupport.isEnabled() { gesture = NotchGestureSupport() }
        panel?.handleScroll = { [weak self] event in self?.handleScroll(event) ?? false }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        handleSectionScroll(event) || handleGesture(event)
    }

    private func handleSectionScroll(_ event: NSEvent) -> Bool {
        guard running, !suspended, expanded, showingSections, let panel, !trackingMenu,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            sectionScroll = NotchSectionScroll()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        guard windowHost?.containsSurface(screenPoint) == true,
              panel.frame.maxY - screenPoint.y > expandedGeometry.headerTopInset + expandedGeometry.headerRowHeight else {
            sectionScroll = NotchSectionScroll()
            return false
        }
        let steps = sectionScroll.steps(deltaY: Double(event.scrollingDeltaY), timestamp: event.timestamp,
                                        precise: event.hasPreciseScrollingDeltas, hasPhase: !event.phase.isEmpty,
                                        began: event.phase.contains(.began),
                                        ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                        momentum: !event.momentumPhase.isEmpty)
        if steps != 0 { scrollSections(by: steps) }
        return true
    }

    private func handleGesture(_ event: NSEvent) -> Bool {
        guard running, !suspended, NotchGestureSupport.isEnabled(), let panel,
              !trackingMenu, captureControls == nil, !heldDrag,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            gesture = NotchGestureSupport()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        guard windowHost?.contains(screenPoint) == true else { gesture = NotchGestureSupport(); return false }
        let fromTop = panel.frame.maxY - screenPoint.y
        let page = expandedGeometry
        let row = page.headerRowHeight > 0
        let inHeader = NotchSupport.gestureIsOverHeader(expanded: expanded, peeking: peeking, fromTop: fromTop,
                                                       safeTop: expanded ? (row ? page.headerTopInset : 0) : geometry.safeContentTop,
                                                       height: expanded ? (row ? page.headerRowHeight : page.pageTopInset)
                                                           : NotchLayout.headerHeight)
        let interaction = NotchGestureSupport.nativeInteraction(at: panel.contentView?.hitTest(event.locationInWindow))
        let musicSurface = modules.contains(.music)
            && (compactMusicIsVisible || (expanded && selected == .music && !showingAppPanel && !showingSections
                                          && !showingCommandBar))
        let vertical = NotchGestureSupport.allowsVertical(expanded: expanded, inHeader: inHeader,
                                                          musicSurface: musicSurface,
                                                          control: interaction.control, scroll: interaction.scroll)
        let horizontal = !interaction.control && !interaction.scroll && !inHeader && musicSurface
        let x = NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        let y = NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        guard let action = gesture.handle(x: x, y: y, timestamp: event.timestamp,
                                          began: event.phase.contains(.began),
                                          ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                          momentum: !event.momentumPhase.isEmpty,
                                          precise: event.hasPreciseScrollingDeltas,
                                          hasPhase: !event.phase.isEmpty,
                                          allowVertical: vertical, allowHorizontal: horizontal, expanded: expanded) else { return false }
        switch action {
        case .open: open()
        case .close: collapse()
        case .nextTrack, .previousTrack:
            guard musicSurface else { gesture = NotchGestureSupport(); return false }
            NotchMusicService.shared.skipFromGesture(forward: action == .nextTrack)
        }
        return true
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    func showUpdate() {
        guard running, !suspended, expanded, case .available = UpdateService.shared.state else { return }
        collapse()
    }

    private func bindEvents() {
        subscriptions.removeAll()
        if modules.contains(.timer) {
            NotchTimerService.shared.$session.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.watch) {
            let watch = NotchWatchService.shared
            Publishers.CombineLatest3(watch.$state.removeDuplicates(), watch.$headline.removeDuplicates(),
                                      watch.$preview.map { $0 != nil }.removeDuplicates())
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.music) {
            let music = NotchMusicService.shared
            music.$playback.combineLatest(music.$artwork, music.$artworkTint)
                .sink { [weak self] playback, artwork, tint in
                    guard playback != nil else { return }
                    self?.rememberPresentedMusic(playback: playback, artwork: artwork, tint: tint)
                }.store(in: &subscriptions)
            music.trackEnds
                .sink { [weak self] in self?.holdEndingTrack() }
                .store(in: &subscriptions)
            music.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
            music.$playback.map { [$0?.track.title, $0?.track.artist] }.removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.fitNamedMusicStrip() }
                .store(in: &subscriptions)
            music.$playback.map { $0?.isPlaying }.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak self] playing in
                    if let self, self.musicStripRequest == playing { self.endMusicStripRequest() }
                }.store(in: &subscriptions)
            music.$playback.removeDuplicates(by: NotchPlayback.sameRecording).receive(on: DispatchQueue.main)
                .sink { [weak self] playback in self?.endMusicStripSong(playback) }
                .store(in: &subscriptions)
            music.$playback.map { $0?.isPlaying == true }
                .removeDuplicates().dropFirst().filter { $0 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.mascotHearsMusic() }
                .store(in: &subscriptions)
            music.$playback.map { $0?.track.title }.removeDuplicates().map { _ in () }
                .merge(with: $heldMusic.map { $0?.playback.track.title }.removeDuplicates().map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.nameCapsuleSong() }
                .store(in: &subscriptions)
        }
        if NotchSupport.routes(.track) {
            NotchMusicService.shared.trackChanges
                .sink { [weak self] in self?.scheduleTrackNotice() }
                .store(in: &subscriptions)
        }
        if modules.contains(.tools) {
            let launcher = QuickLauncherService.shared
            launcher.$isEditing.map { _ in () }
                .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () })
                .dropFirst(3).receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self, self.expanded, self.selected == .tools, !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.system), AppFeature.fanControl.isAvailable {
            SystemMonitor.shared.$snapshot.map { $0.fanSpeeds.isEmpty }.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.expanded, self.selected == .system, self.selectedMetric == nil,
                          !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.download) {
            NotchDownloadService.shared.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.syncMenuSpaceMonitoring()
                self?.objectWillChange.send()
                self?.refreshPresentation()
            }.store(in: &subscriptions)
            NotchDownloadService.shared.onArrival = { [weak self] item in
                self?.show(NotchNotice(event: .download,
                    title: FeatureStrings.notchFiles(L10n.shared.language).completed,
                    detail: item.name, symbol: "arrow.down.circle.fill", mascot: .celebrate))
                self?.reactMascot(.celebrate)
            }
            NotchDownloadService.shared.onFailure = { [weak self] in self?.reactMascot(.confused) }
        }
        if modules.contains(.agents) {
            AgentUsageService.shared.$snapshot
                .map { ($0.loaded, $0.live.isEmpty, $0.seen, Set($0.live.map(\.provider))) }
                .removeDuplicates(by: ==)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
            CodexProfileLimitsService.shared.$states
                .map { $0.map(\.id) }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.selected == .agents else { return }
                    self.objectWillChange.send()
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.calendar) {
            NotchCalendarService.shared.$countdown.removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMascotCalendar()
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        KeepAwakeManager.shared.$isActive.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncMascotKeepAwake() }
            .store(in: &subscriptions)
        if NotchKeepAwakeSupport.showsActivity() {
            let awake = KeepAwakeManager.shared
            awake.$isActive.combineLatest(awake.$endDate).removeDuplicates { $0 == $1 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.agents) {
            AgentUsageService.shared.events.receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.showAgentEvent($0) }
                .store(in: &subscriptions)
        }
        stopPower()
        if NotchSupport.routes(.volume) {
            bindVolumeEvents()
        }
        if NotchSupport.routes(.inputSource) {
            ownInputSourceID = nil
            inputSourceID = InputSourceSelection.currentReading()?.id
            NotificationCenter.default.publisher(for: GlobalShortcut.keyboardLayoutDidChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.inputSourceChanged() }
                .store(in: &subscriptions)
        }
        if NotchSupport.routes(.systemNotification) {
            NotchNotificationService.shared.received.sink { [weak self] item in
                guard let self else { return }
                let shown = self.show(NotchNotice(event: .systemNotification, title: item.content.title,
                                                 detail: item.content.body, symbol: "bell.fill", notification: item.content, notificationID: item.id))
                if shown, !self.expanded, self.captureControls == nil, !self.dragPlaceholder {
                    NotchNotificationService.shared.hideNative(item.id)
                }
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.clipboard) {
            let history = ClipboardHistoryService.shared
            history.capturedEntry.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.battery) || idleContent == .battery || NotchMascotSupport.isEnabled() { startPower() }
    }

    private func showAgentEvent(_ event: AgentUsageEvent) {
        let text = FeatureStrings.notchAgents(L10n.shared.language)
        let locale = L10n.shared.language.formattingLocale()
        func window(_ window: AgentLimitWindow) -> String {
            switch window.kind {
            case .session: return text.session
            case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
            case .other: return window.minutes.map { AgentFormat.duration(TimeInterval($0) * 60, locale: locale, units: 1) }
                ?? text.readoutLimit
            }
        }
        switch event {
        case .finished(let provider, let duration, _, _, _):
            show(NotchNotice(event: .agents, title: text.finished(provider.displayName),
                             detail: AgentFormat.duration(duration, locale: locale),
                             symbol: provider.symbol, agent: provider))
            reactMascot(.celebrate)
        case .limitWarning(let provider, let limit):
            show(NotchNotice(event: .agents, title: "\(provider.displayName) · \(window(limit))",
                             detail: NotchAgentSupport.limitShare(limit, display: NotchAgentSupport.limitDisplay(),
                                                                  text: text),
                             symbol: "exclamationmark.triangle.fill", agent: provider))
        case .limitReset(let provider, let limit):
            show(NotchNotice(event: .agents, title: "\(provider.displayName) · \(window(limit))",
                             detail: text.limitRenewed, symbol: "arrow.clockwise", agent: provider, mascot: .celebrate))
            reactMascot(.celebrate)
        case .budgetReached(let spent, _):
            show(NotchNotice(event: .agents, title: text.budgetTitle, detail: AgentFormat.cost(spent),
                             symbol: "dollarsign.circle.fill"))
        }
    }

    func showCurrentVolume() {
        let mixer = AppVolumeMixer.shared
        guard let volume = mixer.systemOutputVolume else { return }
        showVolume(volume, muted: mixer.systemOutputMuted)
    }

    func noteOwnLevelAdjustment(_ event: NotchEvent) {
        ownLevelAdjustmentUntil[event] = ProcessInfo.processInfo.systemUptime + 1
    }

    private func ownsLevelAdjustment(_ event: NotchEvent) -> Bool {
        expanded && ProcessInfo.processInfo.systemUptime < ownLevelAdjustmentUntil[event, default: 0]
    }

    private func bindVolumeEvents() {
        let mixer = AppVolumeMixer.shared
        volumeDeviceUID = mixer.currentOutputDeviceUID
        volumeBaseline = mixer.systemOutputVolume
        muteBaseline = mixer.systemOutputMuted
        mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted, mixer.$currentOutputDeviceUID)
            .handleEvents(receiveOutput: { [weak self] _, _, deviceUID in
                guard let self, deviceUID != self.volumeDeviceUID else { return }
                self.volumeDeviceUID = deviceUID
                self.volumeBaseline = nil
                self.muteBaseline = nil
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mixer] _ in
                guard let mixer else { return }
                self?.volumeChanged(mixer.systemOutputVolume, muted: mixer.systemOutputMuted)
            }
            .store(in: &subscriptions)
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard volumeDeviceUID != nil, let volume, let baseline = volumeBaseline,
              volume != baseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        guard !ownsLevelAdjustment(.volume) else { return }
        let muteChanged = muteBaseline != nil && muted != muteBaseline
        if !muteChanged {
            let origin = NotchSupport.volumeChangeOrigin(
                from: baseline, to: volume,
                sinceRide: ProcessInfo.processInfo.systemUptime - lastVolumeRide)
            guard origin == .announces else {
                lastVolumeRide = ProcessInfo.processInfo.systemUptime
                return
            }
        }
        lastVolumeRide = -.infinity
        showVolume(volume, muted: muted)
    }

    @discardableResult
    func showVolume(_ volume: Double, muted: Bool? = nil) -> Bool {
        guard volume.isFinite else { return false }
        let value = muted == true ? 0 : min(1, max(0, volume))
        let mixer = AppVolumeMixer.shared
        let output = mixer.outputDevices.first { $0.uid == mixer.currentOutputDeviceUID }
        let symbol: String
        if let output, output.isHeadphones {
            symbol = NotchAccessorySupport.symbol(for: .audio, name: output.name)
        } else {
            symbol = value == 0 ? "speaker.slash.fill"
                : value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
        return show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                                detail: "",
                                symbol: symbol, level: value))
    }

    func noteOwnInputSourceSwitch(to sourceID: String) {
        ownInputSourceID = sourceID
    }

    private func inputSourceChanged() {
        guard let reading = InputSourceSelection.currentReading(), reading.id != inputSourceID else { return }
        inputSourceID = reading.id
        let isOwnSwitch = reading.id == ownInputSourceID
        ownInputSourceID = nil
        guard !isOwnSwitch else { return }
        show(NotchNotice(event: .inputSource, title: reading.code, detail: reading.name, symbol: "keyboard"))
    }

    private func startPower() {
        guard PowerSampler.hasInternalBattery else { return }
        powerSampler = PowerSampler(smc: nil)
        power = powerSampler?.sample() ?? PowerReading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let owner = Unmanaged<NotchService>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if lowPowerObserver == nil {
            lowPowerObserver = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let on = ProcessInfo.processInfo.isLowPowerModeEnabled
                self.showBattery(title: on ? "Low Power Mode"
                                 : self.power.externalConnected ? "Charging" : "Discharging")
            }
        }
    }

    private var lowPowerObserver: NSObjectProtocol?

    private func showBattery(title: String, mascot: NotchMascotReaction? = nil) {
        guard running, !suspended, let percent = power.chargePercent else { return }
        let charging = power.externalConnected
        let step = charging ? "bolt" : percent > 87 ? "100percent" : percent > 62 ? "75percent"
            : percent > 37 ? "50percent" : percent > 12 ? "25percent" : "0percent"
        show(NotchNotice(event: .battery, title: title, detail: "\(percent)%",
                         symbol: charging ? "battery.100percent.bolt" : "battery.\(step)", mascot: mascot))
    }

    private func stopPower() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        powerSampler = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
    }

    private func powerChanged() {
        guard running, !suspended, let sampler = powerSampler else { return }
        let before = power
        let next = sampler.sample()
        power = next
        let pluggedIn = !before.externalConnected && next.externalConnected
        let low = (next.chargePercent ?? 100) <= 20 && (before.chargePercent ?? 0) > 20
        guard before.externalConnected != next.externalConnected || low
                || (before.isCharging && !next.isCharging && next.chargePercent == 100) else { return }
        let text = FeatureStrings.notch(L10n.shared.language)
        let title = low ? text.lowBattery : next.externalConnected
            ? (next.isCharging ? "Charging" : next.chargePercent == 100 ? "Charged" : "Charging")
            : "Discharging"
        let charged = next.externalConnected && before.isCharging && !next.isCharging && next.chargePercent == 100
        let reaction = NotchMascotSupport.powerReaction(pluggedIn: pluggedIn, charged: charged, low: low)
        showBattery(title: title, mascot: reaction)
        if let reaction { reactMascot(reaction) }
    }

    private func syncVisibleConsumers() {
        syncMenuSpaceMonitoring()
        guard running, !suspended else { releaseMonitor(); return }
        if fullscreenCompact {
            CameraPreviewService.shared.hideEmbedded()
            let copiesShowMusic = showsCopies && NotchSupport.watchesMusicActivity()
            if copiesShowMusic { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
            releaseMonitor()
            return
        }
        if !NotchCameraSupport.canPresent(expanded: expanded && !showingSections && !showingCommandBar, selected: selected,
            appPanel: showingAppPanel, captureControls: captureControls != nil) {
            CameraPreviewService.shared.hideEmbedded()
        }
        let musicWanted = modules.contains(.music) && ((expanded && (selected == .music || (selected == .controls && NotchSupport.controls().contains(.music)))
            && !showingAppPanel && !showingSections && !showingCommandBar)
            || ((!hiddenUntilHover || NotchSupport.hiddenShowsActivity())
                && (NotchSupport.watchesMusicActivity() || NotchSupport.routes(.track))))
        if musicWanted { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel
            && !showingSections && !showingCommandBar
        var detailNeeds = expanded && !showingSections ? selectedMetric?.monitorNeeds ?? .none : .none
        if needs, AppFeature.monitorDisk.isAvailable { detailNeeds.disk = true }
        if needs, AppFeature.fanControl.isAvailable { detailNeeds.fanSpeed = true }
        if needs, AppFeature.connectedDevices.isAvailable { detailNeeds.connectedDevices = true }
        SystemMonitor.shared.setNotchDetailNeeds(detailNeeds)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            SystemMonitor.shared.setNotchVisible(needs)
        }
    }

    private func releaseMonitor() {
        SystemMonitor.shared.setNotchDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        SystemMonitor.shared.setNotchVisible(false)
    }
}

// MARK: - Companion

extension NotchService {
    fileprivate func syncMascotVisits() {
        let visits = running && NotchMascotSupport.visits()
        let frequency = NotchMascotSupport.visitFrequency()
        defer { mascotVisitsWereOn = visits; mascotFrequencyAtSync = frequency }
        guard visits else {
            nextMascotVisitWork?.cancel(); nextMascotVisitWork = nil
            if let visit = mascotVisit, visit.kind != .farewell, !running { endMascotVisit() }
            return
        }
        if !mascotVisitsWereOn {
            if mascotVisit?.kind != .arrive {
                scheduleMascotVisit(after: NotchMascotSupport.welcomeDelay, greeting: .wink)
            }
        } else if mascotVisit == nil, nextMascotVisitWork == nil || mascotFrequencyAtSync != frequency {
            scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay(frequency))
        }
    }

    fileprivate func scheduleMascotVisit(after delay: TimeInterval, greeting: NotchMascotMood? = nil) {
        nextMascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.beginMascotVisit(greeting: greeting) }
        nextMascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginMascotVisit(greeting: NotchMascotMood?, asked: Bool = false) {
        nextMascotVisitWork = nil
        guard asked || NotchMascotSupport.visits() else { return }
        guard canHostMascotVisit(), mascotVisit == nil else {
            scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay())
            return
        }
        guard asked || !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay())
            return
        }
        let coversNothing = mascotRestsInView || (mascotTucked && idleContent == .none && compactActivity == nil)
        if PerformanceMode.reduceMotion, !coversNothing {
            if asked { beginMascotCameo(.celebrate) } else { scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay()) }
            return
        }
        let visit = NotchMascotVisit(id: UUID(), kind: mascotRestsInView ? .lap : .pass,
                                     greeting: greeting ?? NotchMascotSupport.greeting(), start: CACurrentMediaTime())
        setMascotVisit(visit)
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visit.duration, execute: work)
    }

    fileprivate func endMascotVisit() {
        mascotVisitWork?.cancel(); mascotVisitWork = nil
        guard let ended = mascotVisit else { return }
        if ended.kind.reaction != nil, mascotRestsInView, CACurrentMediaTime() >= ended.start + ended.duration - 0.05,
           !PerformanceMode.reduceMotion {
            let back = NotchMascotVisit(id: UUID(), kind: .arrive, greeting: .idle,
                                        start: max(ended.start + ended.duration, CACurrentMediaTime() - 0.1))
            setMascotVisit(back)
            let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
            mascotVisitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + back.duration, execute: work)
            return
        }
        if running, !NotchMascotSupport.isEnabled(), !ended.kind.endsOutOfSight, ended.kind != .farewell,
           !PerformanceMode.reduceMotion, idleContent == .none, compactActivity == nil,
           !mascotInBar, canHostMascotVisit() {
            let farewell = NotchMascotVisit(id: UUID(), kind: .farewell, greeting: .happy, start: CACurrentMediaTime())
            setMascotVisit(farewell)
            let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
            mascotVisitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + farewell.duration, execute: work)
            return
        }
        setMascotVisit(nil)
        if mascotSideAtSync != NotchMascotSupport.side() {
            syncMascotSide()
            if mascotVisit != nil { return }
        }
        if running, NotchMascotSupport.visits() { scheduleMascotVisit(after: NotchMascotSupport.nextVisitDelay()) }
    }

    fileprivate func mascotReturnedToRest() {
        guard let visit = mascotVisit, let reaction = visit.kind.reaction else { return }
        let landed = visit.start + (visit.kind == .linger(reaction) ? 0 : NotchMascotMotion.cameoArrival)
        let now = CACurrentMediaTime()
        guard now < landed + NotchMascotMotion.cameoHold(reaction) - 0.05 else { return }
        let wait = max(0, landed + 0.05 - now)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mascotVisit?.id == visit.id else { return }
            if self.mascotRestsInView { self.endMascotVisit(); return }
            let leave = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
            self.mascotVisitWork = leave
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, visit.start + visit.duration - CACurrentMediaTime()),
                                          execute: leave)
        }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    fileprivate func stageMascotEntrance(arriving: Bool) {
        guard !PerformanceMode.reduceMotion, idleContent == .none,
              compactActivity == nil, !mascotInBar, arriving || !mascotTucked, canHostMascotVisit(),
              arriving ? mascotVisit == nil || mascotVisit?.kind == .farewell : mascotVisit == nil else { return }
        let visit = NotchMascotVisit(id: UUID(), kind: arriving ? .arrive : .farewell,
                                     greeting: arriving ? .wink : .happy, start: CACurrentMediaTime())
        mascotVisitWork?.cancel()
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = visit
        mascotStepsAside = false
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visit.duration, execute: work)
    }

    // MARK: Hiding when idle

    fileprivate func syncMascotHiding(switchedOn: Bool) -> Bool {
        let hides = NotchMascotSupport.hidesWhenIdle()
        let previous = mascotHidesAtSync
        mascotHidesAtSync = hides
        var toggled = false
        if previous == nil {
            mascotTucked = hides
        } else if switchedOn {
            mascotTucked = false
        } else if previous != hides, mascotOn {
            toggled = true
            if !hides { untuckMascot() } else if !stageMascotTuck() {
                scheduleMascotTuck(after: NotchMascotSupport.hideRetry, now: true)
            }
        }
        if !hides {
            mascotTuckWork?.cancel(); mascotTuckWork = nil
        } else if !mascotTucked, mascotTuckWork == nil {
            scheduleMascotTuck(after: NotchMascotSupport.hideDelay)
        }
        return toggled
    }

    fileprivate func noteMascotStirred() {
        mascotStirred = CACurrentMediaTime()
    }

    private func scheduleMascotTuck(after delay: TimeInterval, now: Bool = false) {
        mascotTuckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tuckMascotIfQuiet(now: now) }
        mascotTuckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func tuckMascotIfQuiet(now: Bool) {
        mascotTuckWork = nil
        guard running, mascotHidesAtSync == true, !mascotTucked else { return }
        let quiet = CACurrentMediaTime() - mascotStirred
        if !now, quiet < NotchMascotSupport.hideDelay - 0.05 {
            scheduleMascotTuck(after: NotchMascotSupport.hideDelay - quiet)
            return
        }
        if !now, mascotRestsInView, windowHost?.containsHover(NSEvent.mouseLocation) == true {
            scheduleMascotTuck(after: NotchMascotSupport.hideRetry)
            return
        }
        guard stageMascotTuck() else {
            scheduleMascotTuck(after: NotchMascotSupport.hideRetry, now: now)
            return
        }
        refreshPresentation()
    }

    private func stageMascotTuck() -> Bool {
        let reacting = pendingMascotReaction.map { CACurrentMediaTime() <= $0.deadline } ?? false
        guard mascotVisit == nil, !reacting, !mascotBridging, !mascotInBar else { return false }
        let shown = mascotRestsInView && canHostMascotVisit()
        mascotTucked = true
        mascotTuckWork?.cancel(); mascotTuckWork = nil
        guard shown, !PerformanceMode.reduceMotion else { return true }
        let tuck = NotchMascotVisit(id: UUID(), kind: NotchMascotSupport.hideAway, greeting: .idle,
                                    start: CACurrentMediaTime())
        mascotVisitWork?.cancel()
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = tuck
        mascotStepsAside = true
        if let handBack = NotchMascotMotion.handBack(of: tuck.kind, floats: geometry.floats) {
            let back = DispatchWorkItem { [weak self] in
                self?.mascotStepBackWork = nil
                self?.mascotStepsAside = false
            }
            mascotStepBackWork = back
            DispatchQueue.main.asyncAfter(deadline: .now() + handBack, execute: back)
        }
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + tuck.duration, execute: work)
        return true
    }

    private func untuckMascot() {
        guard mascotTucked else { return }
        mascotTucked = false
        if !expanded { stageMascotEntrance(arriving: true) }
    }

    @discardableResult
    func greetMascot() -> Bool {
        guard NotchMascotSupport.isEnabled(), mascotVisit == nil else { return false }
        guard canHostMascotVisit() else { return false }
        nextMascotVisitWork?.cancel()
        beginMascotVisit(greeting: .wink, asked: true)
        return mascotVisit != nil
    }

    private func canHostMascotVisit(returning: Bool = false) -> Bool {
        showsSystemFeedback && !hiddenUntilHover && (returning || !mascotInBar) && !expanded && !peeking && !dragPlaceholder && notice == nil
            && captureControls == nil && !showsCompactActivityPicker && !fullscreenCompact
            && panel?.isVisible == true && mascotHasRoom
    }

    private var mascotHasRoom: Bool {
        guard let activity = compactActivity else { return geometry.floats || geometry.restingWingWidth > 0 }
        return mascotTrack(overActivityStrip: compactStripSize(for: activity, companion: compactCompanion)) != nil
    }

    func mascotTrack(overActivityStrip size: CGSize) -> NotchMascotTrack? {
        guard mascotOn || mascotVisit != nil else { return nil }
        return NotchMascotSupport.track(overActivity: geometry.floats ? geometry : compactActivityGeometry, size: size,
                                        side: mascotSide)
    }

    private var mascotRestsInView: Bool { mascotAtRest && compactActivity == nil }

    // MARK: Command Bar

    func commandBarDropSource() -> CGRect? {
        guard acceptsSystemFeedback, !hiddenUntilHover, !fullscreenCompact, !expanded, captureControls == nil,
              panel?.isVisible == true, let frame = windowHost?.visibleFrame, !frame.isEmpty,
              NSMouseInRect(NSEvent.mouseLocation, geometry.screen, false) else { return nil }
        let gap = geometry.floatingGap ?? 0
        return frame.insetBy(dx: 0, dy: min(gap, frame.height / 2 - 1))
    }

    func presentCommandBar() -> NSPanel? {
        guard NotchSupport.isEnabled(), acceptsUserInteraction, !hiddenInFullscreen, captureControls == nil,
              !heldDrag, NSMouseInRect(NSEvent.mouseLocation, geometry.screen, false), let panel else { return nil }
        panel.acceptsKeyFocus = true
        panel.makeKey()
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        hoverState.open()
        hoverWork?.cancel()
        if !expanded { removeHoverExitMonitors() }
        mutatePresentation(transitionContent: expanded ? .replace : .reveal) {
            showingCommandBar = true
            showingAppPanel = false
            showingSections = false
            selectedMetric = nil
            peeking = false
            openedByHover = false
            expanded = true
            if notice?.notificationID != nil { noticeWork?.cancel(); noticeWork = nil; notice = nil; noticeExpanded = false }
        }
        inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
        installEventMonitors()
        syncVisibleConsumers()
        panel.makeKey()
        return panel
    }

    func setMascotInBar(_ away: Bool, homecoming: NotchMascotMood? = nil) {
        guard away != mascotInBar else { return }
        if away, mascotVisit != nil { endMascotVisit() }
        let home = homecoming.flatMap { mood -> NotchMascotVisit? in
            guard !away, !PerformanceMode.reduceMotion, NotchMascotSupport.isEnabled(),
                  !mascotTucked, idleContent == .none, compactActivity == nil, canHostMascotVisit(returning: true)
            else { return nil }
            return NotchMascotVisit(id: UUID(), kind: .home, greeting: mood, start: CACurrentMediaTime())
        }
        mutatePresentation {
            mascotInBar = away
            if let home { mascotVisit = home }
        }
        guard let home else { return }
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + home.duration + 0.1, execute: work)
    }

    func mascotNoticeBridgeStart(for incoming: NotchNotice) -> CGFloat? {
        if mascotBridging, notice != nil { endMascotBridgeNow() }
        guard incoming.mascot != nil, notice == nil, noticeCanPresent, mascotVisit == nil,
              NotchMascotSupport.isEnabled(), geometry.isNotched, !geometry.floats,
              !PerformanceMode.reduceMotion,
              mascotRestsInView, canHostMascotVisit() else { return nil }
        endMascotBridgeNow()
        let from = mascotClosedOffset
        mascotBridgeLift = mascotClosedTrack.hop(0.22)
        showMascotBridge(from: from, to: from, duration: 0)
        mascotBridgeTarget = .notice(incoming)
        mascotBridging = true
        return from
    }

    func bridgeMascotIntoNotice(_ shown: NotchNotice, from: CGFloat) {
        guard notice == shown, let reaction = shown.mascot else { endMascotBridgeNow(); return }
        let scale = mascotNoticeScale
        let duration: TimeInterval = 0.45
        showMascotBridge(from: from, to: shown.mascotOffset(in: geometry), duration: duration, scale: (1, scale),
                         trailsGrowth: true)
        if NotchMascotSupport.reacts() {
            windowHost?.reactMascotBridge(NotchMascotReactionEvent(id: UUID(), reaction: reaction,
                                                                   start: CACurrentMediaTime()),
                                          lift: NotchMascotSupport.noticeSize * 0.32 / scale)
        }
        scheduleMascotBridgeEnd(after: duration)
    }

    func mascotNoticeBridgeBackStart(from ending: NotchNotice?) -> CGFloat? {
        guard let ending, ending.mascot != nil, NotchMascotSupport.isEnabled(), mascotVisit == nil,
              geometry.isNotched, !geometry.floats, !PerformanceMode.reduceMotion,
              mascotRestsInView else { return nil }
        endMascotBridgeNow()
        let from = ending.mascotOffset(in: geometry)
        let scale = mascotNoticeScale
        mascotBridgeLift = mascotClosedTrack.hop(0.22)
        showMascotBridge(from: from, to: from, duration: 0, scale: (scale, scale))
        mascotBridgeTarget = .rest
        mascotBridging = true
        return from
    }

    func bridgeMascotHome(from: CGFloat) {
        guard mascotRestsInView, canHostMascotVisit() else { endMascotBridgeNow(); return }
        let duration: TimeInterval = 0.45
        showMascotBridge(from: from, to: mascotClosedOffset, duration: duration, scale: (mascotNoticeScale, 1),
                         hop: mascotClosedTrack.hop(0.22))
        scheduleMascotBridgeEnd(after: duration)
    }

    private var mascotNoticeScale: CGFloat {
        NotchMascotSupport.noticeSize / NotchMascotSupport.size(stripHeight: geometry.stripHeight, floats: false)
    }

    private func showMascotBridge(from: CGFloat, to: CGFloat, duration: TimeInterval,
                                  scale: (from: CGFloat, to: CGFloat) = (1, 1), trailsGrowth: Bool = false,
                                  hop: CGFloat = 0) {
        windowHost?.bridgeMascot(look: NotchMascotSupport.look(),
                                 size: NotchMascotSupport.size(stripHeight: geometry.stripHeight, floats: false),
                                 mood: mascotRestingMood, from: from, to: to,
                                 baseline: geometry.stripHeight / 2 + 0.5, duration: duration, scale: scale,
                                 trailsGrowth: trailsGrowth, hop: hop)
    }

    private func scheduleMascotBridgeEnd(after duration: TimeInterval) {
        mascotBridgeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.mascotBridgeWork = nil
            self.mascotBridging = false
            self.mascotBridgeTarget = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.mascotBridging else { return }
                self.windowHost?.endMascotBridge()
            }
        }
        mascotBridgeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func endMascotBridgeNow(fading: Bool = false) {
        mascotBridgeWork?.cancel(); mascotBridgeWork = nil
        mascotBridgeTarget = nil
        if mascotBridging { mascotBridging = false }
        windowHost?.endMascotBridge(fading: fading)
    }

    private var mascotBridgeTargetShows: Bool {
        switch mascotBridgeTarget {
        case .rest: return mascotRestsInView && canHostMascotVisit()
        case .notice(let shown): return notice == shown && !noticeExpanded && noticeCanPresent
        case nil: return true
        }
    }

    private var mascotClosedTrack: NotchMascotTrack {
        NotchMascotSupport.track(stripWidth: geometry.collapsed.width, stripHeight: geometry.stripHeight,
                                 wing: geometry.restingWingWidth, cameraWidth: geometry.cameraWidth,
                                 floats: false, bodyHeight: geometry.stripBodyHeight, side: mascotSide)
    }

    private var mascotClosedOffset: CGFloat { mascotClosedTrack.rest - geometry.collapsed.width / 2 }

    private func syncMascotSide() {
        let side = NotchMascotSupport.side()
        let previous = mascotSideAtSync
        guard previous == nil || mascotVisit == nil else { return }
        mascotSideAtSync = side
        guard let previous, previous != side, !geometry.floats,
              !PerformanceMode.reduceMotion,
              mascotRestsInView, canHostMascotVisit() else { return }
        let cross = NotchMascotVisit(id: UUID(), kind: .cross, greeting: .wink, start: CACurrentMediaTime())
        mutatePresentation { mascotVisit = cross }
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cross.duration + 0.1, execute: work)
    }

    fileprivate func syncMascotKeepAwake() {
        let active = KeepAwakeManager.shared.isActive
        let saw = mascotSawKeepAwake
        mascotSawKeepAwake = active
        guard let saw, saw != active, NotchMascotSupport.isEnabled() else { return }
        objectWillChange.send()
        reactMascot(active ? .perk : .yawn)
    }

    fileprivate func syncMascotAgents() {
        guard AgentUsageService.shared.snapshot.loaded else { return }
        let working = hasAgentActivity
        let saw = mascotSawAgents
        mascotSawAgents = working
        guard saw == false, working, mascotRestedInView, NotchMascotSupport.reacts() else { return }
        let now = CACurrentMediaTime()
        guard now - lastMascotAgentStart > NotchMascotSupport.agentStartInterval else { return }
        lastMascotAgentStart = now
        reactMascot(.ready, patience: 1)
    }

    fileprivate func syncMascotCalendar() {
        let countdown = NotchCalendarService.shared.countdown
        defer { mascotSawCountdown = countdown }
        guard NotchMascotSupport.eventBegan(from: mascotSawCountdown, to: countdown, at: Date()) else { return }
        reactMascot(.bounce)
    }

    fileprivate func mascotHearsMusic() {
        let now = CACurrentMediaTime()
        guard NotchMascotSupport.reacts(), now - lastMascotGroove > NotchMascotSupport.grooveInterval else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMascotSupport.grooveDelay) { [weak self] in
            guard NotchMusicService.shared.playback?.isPlaying == true else { return }
            self?.reactMascot(.groove, patience: 3)
        }
    }

    func reactMascot(_ reaction: NotchMascotReaction, patience: TimeInterval = NotchMascotReactionGate.patience,
                     after delay: TimeInterval = 0) {
        guard NotchMascotSupport.reacts() else { return }
        if notice?.mascot == reaction, noticeCanPresent {
            _ = mascotReactionGate.admits(reaction, at: CACurrentMediaTime())
            return
        }
        let now = CACurrentMediaTime()
        pendingMascotReaction = (reaction, now + delay + patience, now + delay)
        flushMascotReaction()
    }

    fileprivate func flushMascotReaction() {
        if mascotVisit?.kind.watchesTimer == true, compactActivity != .timer {
            endMascotCountdown(retreating: false)
        }
        guard let pending = pendingMascotReaction else { return }
        let now = CACurrentMediaTime()
        guard now <= pending.deadline, NotchMascotSupport.reacts() else { pendingMascotReaction = nil; return }
        guard now >= pending.notBefore else {
            mascotReactionFlushWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.mascotReactionFlushWork = nil
                self?.flushMascotReaction()
            }
            mascotReactionFlushWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (pending.notBefore - now), execute: work)
            return
        }
        guard mascotVisit == nil, canHostMascotVisit() else { return }
        if mascotRestsInView, !mascotBridging {
            guard mascotRestedInView else { return }
            let shows = mascotBackAtRest + NotchMascotMotion.restCrossfade
            if now < shows {
                pendingMascotReaction = (pending.reaction, max(pending.deadline, shows + 0.5), shows)
                flushMascotReaction()
                return
            }
        }
        pendingMascotReaction = nil
        guard mascotReactionGate.admits(pending.reaction, at: now) else { return }
        if pending.reaction == .groove { lastMascotGroove = now }
        if mascotRestsInView {
            let event = NotchMascotReactionEvent(id: UUID(), reaction: pending.reaction, start: now)
            mascotReaction = event
            if mascotBridging { windowHost?.reactMascotBridge(event, lift: mascotBridgeLift) }
        } else {
            beginMascotCameo(pending.reaction, lingering: mascotJustRested && compactActivity != nil)
        }
    }

    func watchMascotCountdown(remaining: TimeInterval) {
        guard NotchMascotSupport.reacts(), remaining > 1, mascotVisit == nil, compactActivity == .timer,
              !geometry.floats, canHostMascotVisit() else { return }
        let watch = NotchMascotVisit(id: UUID(), kind: .countdown(remaining), greeting: .idle,
                                     start: CACurrentMediaTime())
        setMascotVisit(watch)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + watch.duration, execute: work)
    }

    func endMascotCountdown(retreating: Bool) {
        guard let visit = mascotVisit, case .countdown = visit.kind else { return }
        guard retreating, compactActivity == .timer, !geometry.floats else { endMascotVisit(); return }
        let retreat = NotchMascotVisit(id: UUID(), kind: .retreat, greeting: .idle, start: CACurrentMediaTime())
        setMascotVisit(retreat)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retreat.duration, execute: work)
    }

    private func beginMascotCameo(_ reaction: NotchMascotReaction, lingering: Bool = false) {
        let cameo = NotchMascotVisit(id: UUID(), kind: lingering ? .linger(reaction) : .cameo(reaction), greeting: .idle,
                                     start: CACurrentMediaTime())
        setMascotVisit(cameo)
        mascotVisitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endMascotVisit() }
        mascotVisitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cameo.duration, execute: work)
    }

    private func setMascotVisit(_ visit: NotchMascotVisit?) {
        mascotStepBackWork?.cancel(); mascotStepBackWork = nil
        mascotVisit = visit
        mascotStepsAside = visit != nil
        refreshPresentation()
        guard let visit, let handBack = NotchMascotMotion.handBack(of: visit.kind, floats: geometry.floats) else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.mascotStepBackWork = nil
            self?.mascotStepsAside = false
        }
        mascotStepBackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, visit.start + handBack - CACurrentMediaTime()),
                                      execute: work)
    }

    func orderBelowIsland(_ window: NSWindow) {
        guard let panel, panel.isVisible else { window.orderFrontRegardless(); return }
        window.order(.below, relativeTo: panel.windowNumber)
    }

    func dismissCommandBar() {
        guard showingCommandBar else { return }
        collapse()
    }

    fileprivate func commandBarDidClose() {
        commandBarHeight = nil
        measuredCommandBarHeight = nil
    }

    func updateCommandBarHeight(_ height: CGFloat) {
        guard showingCommandBar, height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        guard (measuredCommandBarHeight ?? commandBarHeight) != measured else { return }
        let waiting = measuredCommandBarHeight != nil
        measuredCommandBarHeight = measured
        guard !waiting else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let measured = self.measuredCommandBarHeight else { return }
            self.measuredCommandBarHeight = nil
            guard self.showingCommandBar, self.commandBarHeight != measured else { return }
            self.commandBarHeight = measured
            self.refreshPresentation()
        }
    }
}

extension NSScreen {
    var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
