// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        surface
            .transaction(value: service.compactActivity) { transaction in
                guard !reduceMotion, !service.mascotLingers else { return }
                let arrives = service.compactActivity != nil && service.mascotJustRested
                let leaves = service.compactActivity == nil && service.mascotAtRest
                    && service.departingMusic == nil && service.lingeringMusic == nil
                guard arrives || leaves else { return }
                transaction.animation = .easeInOut(duration: NotchMascotMotion.restCrossfade)
            }
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .foregroundStyle(.white)
            .background(shape.offset(x: service.surfaceShift).fill(Color.black.opacity(0.01)))
            .contentShape(shape.offset(x: service.surfaceShift))
            .onTapGesture { }
            .onChange(of: reduceTransparency) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .onChange(of: contrast) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .environment(\.notchGlassSurface, usesGlassSurface)
            .tint(.white)
            .accessibilityIdentifier("notch.surface")
    }

    private var usesGlassSurface: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *), glass, !reduceTransparency {
            return service.usesGlassSurface
        }
#endif
        return false
    }

    private var shape: NotchShape {
        NotchShape.island(height: service.surfaceSize.height, geometry: service.geometry)
    }

    @ViewBuilder private var surface: some View {
        if service.fullscreenCompact {
            Color.clear.accessibilityHidden(true)
        } else if let options = service.captureControls {
            if service.captureControlsCollapsed, floats {
                NotchCapsuleCaptureStrip(symbol: options.selectedTool.systemImageName, geometry: service.geometry,
                                         size: service.surfaceSize)
            } else if service.captureControlsCollapsed {
                HStack(spacing: 0) {
                    Image(systemName: options.selectedTool.systemImageName).frame(width: 28)
                    Color.clear.frame(width: service.geometry.cameraWidth)
                    Image(systemName: "chevron.down").frame(width: 28)
                }
                .font(.system(size: 10, weight: .semibold))
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            } else {
                NotchCaptureControlsView(options: options, service: service, layout: service.captureControlsLayout)
            }
        } else if service.expanded {
            if service.showingCommandBar {
                commandBarPage
            } else {
                expanded
            }
        } else if service.dragPlaceholder {
            Group {
                if service.mascotOn {
                    HStack(spacing: 8) {
                        NotchMascotView(look: NotchMascotSupport.look(), size: 20, followsDrag: true)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(text.dropHint)
                    }
                } else {
                    Label(text.dropHint, systemImage: "tray.and.arrow.down")
                }
            }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.24),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
                .padding(.top, service.geometry.safeContentTop)
        } else if let notice = service.notice ?? (service.peeking ? nil : service.departingNotice) {
            if service.noticeExpanded, let content = notice.notification {
                NotchNotificationPreviewView(notice: notice, content: content, service: service)
                    .padding(.horizontal, NotchLayout.horizontalInset)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, NotchLayout.bottomInset)
                    .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            } else {
                Button {
                    service.activateNotice(notice)
                } label: {
                    Group {
                        if floats {
                            NotchCapsuleNoticeView(notice: notice, geometry: service.geometry,
                                                   size: service.notice == nil ? service.capsuleNoticeSurface(notice)
                                                       : service.surfaceSize)
                        } else {
                            NotchNoticeView(notice: notice, geometry: service.geometry, hidesMascot: service.mascotBridging)
                        }
                    }
                    .contentShape(Rectangle().offset(x: floats ? 0
                        : service.geometry.noticeShift(notice.wings(in: service.geometry))))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 14, lifts: false, highlights: floats))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.accessibilityText)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { service.activateNotice(notice) }
                .accessibilityHint(text.open)
                .transition(.opacity)
            }
        } else if service.peeking {
            HStack {
                navigation
                Spacer(minLength: 8)
                NotchIconButton(symbol: "chevron.down", title: text.open) { service.open() }
            }
            .padding(.horizontal, NotchLayout.horizontalInset).padding(.top, service.geometry.safeContentTop)
        } else if let activity = service.compactActivity {
            if service.showsCompactActivityPicker {
                let layout = service.compactActivityPickerLayout
                VStack(spacing: 0) {
                    let strip = service.compactStripSize(for: activity, companion: service.compactCompanion)
                    ZStack(alignment: .top) {
                        activityStrip(activity, size: strip)
                            .frame(width: strip.width, height: layout.headerHeight, alignment: .top)
                            .id(NotchPickedStrip(activity: activity, companion: service.compactCompanion))
                            .transition(.blurReplace)
                    }
                    .frame(height: layout.headerHeight, alignment: .top)
                    NotchActivityPicker(activities: service.compactActivities, selected: activity,
                                        combinations: service.compactActivityCombinations,
                                        combination: service.compactCompanion.map {
                                            NotchActivityCombination(primary: activity, companion: $0)
                                        },
                                        columns: layout.columns, language: l10n.language,
                                        select: service.selectCompactActivity, combine: service.selectCompactCombination)
                        .padding(.horizontal, NotchActivityPickerLayout.horizontalInset)
                        .padding(.vertical, NotchActivityPickerLayout.verticalInset)
                }
            } else {
                let strip = service.compactStripSize(for: activity, companion: service.compactCompanion)
                activityStrip(activity, size: strip)
                    .modifier(NotchMascotActivityVisit(service: service,
                                                       track: service.mascotTrack(overActivityStrip: strip),
                                                       ownStrip: true))
                    .transition(companionSwap)
            }
        } else if let departingMusic = service.departingMusic ?? service.lingeringMusic {
            Group {
                if floats { NotchCapsuleMusicStrip(service: service, snapshot: departingMusic) }
                else { NotchMusicStrip(service: service, snapshot: departingMusic) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if floats {
            NotchCapsuleRestingView(service: service, size: service.surfaceSize)
                .transition(companionSwap)
        } else {
            compact
                .transition(companionSwap)
        }
    }

    private var floats: Bool { service.geometry.floats }

    private var companionSwap: AnyTransition { service.mascotAtRest ? .notchFadeThrough : .opacity }

    @ViewBuilder private func activityStrip(_ activity: NotchCompactActivity, size: CGSize) -> some View {
        if floats {
            switch activity {
            case .timer: NotchCapsuleTimerStrip(service: service, size: size)
            case .watch: NotchCapsuleWatchStrip(service: service, size: size)
            case .downloads: NotchCapsuleDownloadStrip(service: service, size: size)
            case .agents: NotchCapsuleAgentStrip(service: service, size: size)
            case .calendar: NotchCapsuleCalendarStrip(service: service, size: size)
            case .music: NotchCapsuleMusicStrip(service: service, size: size, interactive: true)
            case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size)
            }
        } else {
            let geometry = service.compactActivityGeometry
            switch activity {
            case .timer: NotchTimerStrip(service: service, displayGeometry: geometry)
            case .watch: NotchWatchStrip(service: service, displayGeometry: geometry)
            case .downloads: NotchDownloadStrip(service: service, displayGeometry: geometry)
            case .agents: NotchAgentStrip(service: service, displayGeometry: geometry)
            case .calendar: NotchCalendarStrip(service: service, displayGeometry: geometry)
            case .music: NotchMusicStrip(service: service, displayGeometry: geometry, interactive: true)
            case .keepAwake: NotchKeepAwakeStrip(service: service, displayGeometry: geometry)
            }
        }
    }

    private var compact: some View { NotchRestingStrip(service: service) }

    private var commandBarPage: some View { Color.clear }

    private var showsDetail: Bool { service.showingAppPanel || service.selectedMetric != nil }

    private var expanded: some View {
        let geometry = service.expandedGeometry
        let band = NotchBand(geometry: geometry, contentWidth: service.contentSize.width)
        let wraps = geometry.pageTop == .wrapsCamera
        return page
            .frame(width: service.contentSize.width, height: service.contentSize.height, alignment: .top)
            .clipShape(NotchPageClip(top: geometry.pageTopInset))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pageName)
            .accessibilityAction(named: service.pinned ? text.unpin : text.pin) { service.pinned.toggle() }
            .accessibilityAction(named: l10n.s.menuSettings) { service.openSettings() }
            .accessibilityAction(named: text.collapse) { service.collapse() }
            .padding(.top, geometry.pageTopInset - geometry.headerTopInset)
            .overlayPreferenceValue(NotchBandKey.self, alignment: .top) { items in
                if geometry.headerRowHeight > 0 {
                    bandRow(items, band: band, wraps: wraps)
                } else if let feedback = headerFeedback {
                    NotchExpandedLevelView(notice: feedback)
                        .padding(.horizontal, 10)
                        .frame(width: 170, height: 28)
                        .background(.black, in: Capsule())
                        .frame(maxWidth: .infinity, alignment: wraps ? .trailing : .leading)
                }
            }
            .environment(\.notchBand, band)
            .padding(.horizontal, NotchLayout.horizontalInset)
            .padding(.top, geometry.headerTopInset)
            .padding(.bottom, NotchLayout.bottomInset)
            .frame(width: service.expandedSize.width, height: service.expandedSize.height, alignment: .top)
            .contentShape(Rectangle())
            .contextMenu { islandMenu }
            .focusEffectDisabled(!service.showsKeyboardFocus)
            .onAppear { UpdateService.shared.checkIfStale() }
    }

    private var pageName: String {
        if service.showingSections { return text.sectionsTitle }
        if showsDetail || service.modules.isEmpty { return service.detailTitle }
        return service.selected.title(l10n.language)
    }

    @ViewBuilder private var page: some View {
        if scrollsVertically {
            ScrollView {
                content
                    .frame(height: contentOverflows ? pageSize.height : nil)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
            }
            .scrollIndicators(.automatic)
            .notchScrollEdgeFade()
        } else {
            content
        }
    }

    private func bandRow(_ items: NotchBandItems, band: NotchBand, wraps: Bool) -> some View {
        let feedback = headerFeedback
        let homeRow = !band.besideCamera && service.selected == .controls && !showsDetail
            && !service.showingSections && !service.modules.isEmpty
        let homeReading = homeRow
            ? NotchLayout.homeReadingWidth(levels: NotchSupport.controls().filter(\.isLevel).count, side: band.leadingRoom) : nil
        let side: HorizontalEdge = wraps || homeReading != nil ? .trailing : .leading
        let readingWidth = homeReading ?? (band.besideCamera ? band.side : min(band.side, 220))
        let makesRoom = homeReading != nil && feedback != nil
        return NotchBandRow(band: band, covered: feedback == nil ? nil : side) {
            if !wraps {
                bandLeading(band)
                items.leading
            }
        } trailing: {
            if makesRoom {
                Color.clear.frame(width: readingWidth)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { items.trailing; trailingSections(band); updateControl(band); pinMark }
                    HStack(spacing: 6) {
                        items.trailing; trailingSections(band)
                        NotchUpdateControl(action: service.showUpdate, compact: true); pinMark
                    }
                    HStack(spacing: 6) { items.trailing; trailingSections(band); pinMark }
                    HStack(spacing: 6) { items.trailing; trailingSections(band) }
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: makesRoom)
        .overlay(alignment: side == .leading ? .leading : .trailing) {
            if let feedback {
                NotchExpandedLevelView(notice: feedback, showsDetail: readingWidth >= NotchLayout.levelReadingDetailWidth)
                    .frame(width: readingWidth)
            }
        }
        .environment(\.locale, l10n.language.formattingLocale())
    }

    @ViewBuilder private func trailingSections(_ band: NotchBand) -> some View {
    }

    private func updateControl(_ band: NotchBand) -> some View {
        NotchUpdateControl(action: service.showUpdate, compact: band.besideCamera)
    }

    @ViewBuilder private var pinMark: some View {
        if service.pinned {
            NotchIconButton(symbol: "pin.fill", title: "Unpin", selected: true) { service.pinned = false }
        }
    }

    @ViewBuilder private func bandLeading(_ band: NotchBand) -> some View {
        if showsDetail {
            NotchBandBackButton(title: service.detailTitle, action: service.goBack)
        }
    }

    @ViewBuilder private var islandMenu: some View {
        Button {
            service.pinned.toggle()
        } label: {
            Label(service.pinned ? "Unpin" : "Pin", systemImage: service.pinned ? "pin.slash" : "pin")
        }
        Button(action: service.openSettings) {
            Label(l10n.s.menuSettings, systemImage: "gearshape")
        }
    }

    private var pageSize: CGSize {
        var size = service.contentSize
        guard !showsDetail else { return size }
        switch service.selected {
        case .mixer:
            size.height = max(size.height, NotchLayout.mixerMinimumHeight)
        case .music:
            size.height = max(size.height, NotchLayout.musicPlayerHeight(band: service.expandedGeometry.musicBandHeight,
                                                                         playing: music.playback != nil,
                                                                         showVolume: service.musicShowsVolume))
        default: break
        }
        return size
    }

    private var contentOverflows: Bool { pageSize.height > service.contentSize.height }

    private var scrollsVertically: Bool { contentOverflows }

    private var headerFeedback: NotchNotice? {
        guard let notice = service.notice, notice.level != nil,
              [.volume, .brightness, .keyboardLight].contains(notice.event) else { return nil }
        return notice
    }

    private var navigationTitle: String {
        let destination = service.reopeningDestination
        return destination.appPanel || destination.sections
            ? text.sectionsTitle : destination.module.title(l10n.language)
    }

    private var navigation: some View {
        Button(action: { service.open() }) {
            HStack(spacing: 9) {
                Image(systemName: service.reopeningDestination.module.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(navigationTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: NotchLayout.navigationHeight)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12, lifts: false))
        .accessibilityLabel(text.switchSection)
        .accessibilityValue(navigationTitle)
        .accessibilityIdentifier("notch.navigation")
        .help(text.open)
    }

    @ViewBuilder private var content: some View {
        switch service.selected {
        case .scratchpad: NotchScratchpadView(service: service)
        case .agents: NotchAgentsView(size: pageSize)
        default: NotchMusicView(size: pageSize, extrasHeight: service.geometry.musicExtrasHeight)
        }
    }
}

enum NotchRestingBattery {
    static func tint(for power: PowerReading, tint: Bool, threshold: Int,
                     early: Bool, earlyThreshold: Int) -> Color {
        switch NotchSupport.batteryWarning(percent: power.chargePercent,
                                           externalConnected: power.externalConnected,
                                           tint: tint, threshold: threshold,
                                           early: early, earlyThreshold: earlyThreshold) {
        case .low: return .red
        case .early: return .orange
        case .none: return .white.opacity(0.9)
        }
    }

    static func symbol(for power: PowerReading) -> String {
        BatteryPowerSupport.menuBarSymbol(percent: power.chargePercent ?? 100,
                                          isCharging: power.isCharging,
                                          externalConnected: power.externalConnected)
    }
}

struct NotchRestingStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.notchLowBatteryTint) private var lowBatteryTint = false
    @AppStorage(DefaultsKey.notchLowBatteryThreshold) private var lowBatteryThreshold = NotchSupport.defaultLowBatteryThreshold
    @AppStorage(DefaultsKey.notchLowBatteryEarly) private var earlyBatteryWarning = false
    @AppStorage(DefaultsKey.notchLowBatteryEarlyThreshold) private var earlyBatteryThreshold = NotchSupport.defaultEarlyBatteryThreshold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var geometry: NotchGeometry { displayGeometry ?? service.geometry }

    private var batteryTint: Color {
        NotchRestingBattery.tint(for: service.power, tint: lowBatteryTint, threshold: lowBatteryThreshold,
                                 early: earlyBatteryWarning, earlyThreshold: earlyBatteryThreshold)
    }

    private var batterySymbol: String { NotchRestingBattery.symbol(for: service.power) }

    private var restingBatteryInset: CGFloat {
        min(16, NotchLayout.shoulder(height: geometry.stripHeight) + NotchLayout.compactEdgeGap)
    }

    private func wingStepsAside(_ side: NotchMascotSide) -> Bool {
        guard service.mascotStepsAside, !service.mascotAtRest else { return false }
        return service.mascotVisit?.kind.takesOnlyItsWing != true || side == service.mascotSide
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if service.idleContent != .none, geometry.restingWingWidth > 0 {
                    ZStack(alignment: .trailing) {
                        Color.clear
                        switch service.idleContent {
                        case .music:
                            if let artwork = music.artwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                                    .frame(width: min(22, geometry.stripHeight - 6), height: min(22, geometry.stripHeight - 6))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        case .battery:
                            Image(systemName: batterySymbol).font(.system(size: 12))
                                .foregroundStyle(batteryTint)
                                .padding(.leading, restingBatteryInset)
                        case .agents:
                            NotchAgentRestingWing(leading: true)
                                .padding(.leading, restingBatteryInset)
                        case .none: EmptyView()
                        }
                    }
                    .frame(width: geometry.restingWingWidth)
                    .opacity(wingStepsAside(.left) ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: wingStepsAside(.left))
                    Color.clear.frame(width: geometry.cameraWidth)
                    ZStack(alignment: .leading) {
                        Color.clear
                        switch service.idleContent {
                        case .music:
                            if music.playback?.isPlaying == true {
                                NotchLiveEqualizerBars(bars: 3, barWidth: 2, height: 11,
                                                       tint: music.artworkTint?.color ?? .white)
                            }
                        case .battery:
                            if let percent = service.power.chargePercent {
                                Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(batteryTint)
                                    .lineLimit(1)
                                    .padding(.trailing, restingBatteryInset)
                            }
                        case .agents:
                            NotchAgentRestingWing(leading: false)
                                .padding(.trailing, restingBatteryInset)
                        case .none: EmptyView()
                        }
                    }
                    .frame(width: geometry.restingWingWidth)
                    .opacity(wingStepsAside(.right) ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: wingStepsAside(.right))
                } else { Color.clear }
            }
            if service.mascotShows(on: geometry) {
                NotchMascotTrackView(look: NotchMascotSupport.look(),
                                     track: NotchMascotSupport.track(stripWidth: geometry.collapsed.width,
                                                                     stripHeight: geometry.stripHeight,
                                                                     wing: geometry.restingWingWidth,
                                                                     cameraWidth: geometry.cameraWidth, floats: false,
                                                                     bodyHeight: geometry.stripBodyHeight,
                                                                     side: service.mascotSide),
                                     rests: service.mascotAtRest, visit: service.mascotVisit,
                                     mood: service.mascotRestingMood, reaction: service.mascotReaction,
                                     yieldsToActivities: true)
                    .frame(width: geometry.collapsed.width, height: geometry.stripHeight)
                    .opacity(service.mascotBridging && displayGeometry == nil ? 0 : 1)
                    .animation(nil, value: service.mascotBridging)
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(height: geometry.stripHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    var floatingGap: CGFloat? = nil
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    static func island(height: CGFloat, geometry: NotchGeometry) -> NotchShape {
        NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: height), floatingGap: geometry.floatingGap)
    }

    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        if let floatingGap { return Path(NotchLayout.capsulePath(in: rect, gap: floatingGap)) }
        let shoulder = NotchLayout.shoulder(height: rect.height)
        let bottom = min(radius, rect.height / 2, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                      control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
                      control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                      control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
                      control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
                      control2: CGPoint(x: shoulder * tangent, y: 0))
        path.closeSubpath()
        return path
    }
}

extension NotchModule: PanelOrderItem {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .timer: return FeatureStrings.notchActivities(language).timer
        case .camera: return FeatureStrings.notchActivities(language).camera
        case .notifications: return FeatureStrings.notchNotifications(language).title
        case .downloads: return FeatureStrings.notchFiles(language).downloadsTitle
        case .calendar: return FeatureStrings.notchCalendar(language).title
        case .controls: return FeatureStrings.notch(language).controls
        case .mixer: return Strings.localized(language).mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        case .scratchpad: return FeatureStrings.scratchpad(language).pageTitle
        case .agents: return FeatureStrings.notchAgents(language).title
        case .watch: return FeatureStrings.notchWatch(language).title
        }
    }
}

private struct NotchPageClip: Shape {
    let top: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - NotchLayout.horizontalInset, y: rect.minY - top,
                    width: rect.width + NotchLayout.horizontalInset * 2,
                    height: rect.height + top + NotchLayout.bottomInset))
    }
}

private struct NotchPickedStrip: Hashable {
    let activity: NotchCompactActivity
    let companion: NotchCompactActivity?
}

struct NotchActivityPicker: View {
    @Namespace private var choice
    let activities: [NotchCompactActivity]
    let selected: NotchCompactActivity
    let combinations: [NotchActivityCombination]
    let combination: NotchActivityCombination?
    let columns: Int
    let language: AppLanguage
    let select: (NotchCompactActivity) -> Void
    let combine: (NotchActivityCombination) -> Void

    var body: some View {
        VStack(spacing: NotchActivityPickerLayout.spacing) {
            individualChoices
            if !combinations.isEmpty {
                Menu {
                    ForEach(combinations) { pair in
                        Button { combine(pair) } label: {
                            Label(pair.title(language),
                                  systemImage: combination == pair ? "checkmark" : pair.companion.symbol)
                        }
                    }
                } label: {
                    Label(combination?.title(language) ?? FeatureStrings.notch(language).combineActivities,
                          systemImage: combination == nil ? "plus" : "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(combination == nil ? 0.75 : 1))
                        .frame(height: NotchActivityPickerLayout.combinationHeight)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("notch.activity.combine")
            }
        }
    }

    private var individualChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchActivityPickerLayout.spacing),
                                 count: columns), spacing: NotchActivityPickerLayout.spacing) {
            ForEach(activities) { activity in
                let chosen = activity == selected && combination == nil
                Button { select(activity) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: activity.symbol)
                        Text(activity.title(language)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: NotchActivityPickerLayout.rowHeight)
                    .foregroundStyle(chosen ? Color.black : Color.white)
                    .background {
                        ZStack {
                            Capsule(style: .continuous).fill(Color.white.opacity(0.12))
                            if chosen {
                                Capsule(style: .continuous).fill(Color.white)
                                    .matchedGeometryEffect(id: "choice", in: choice)
                            }
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activity.title(language))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("notch.activity.\(activity.rawValue)")
            }
        }
    }
}
