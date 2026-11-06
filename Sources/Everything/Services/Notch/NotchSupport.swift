// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import CoreGraphics

enum NotchModule: String, CaseIterable, Identifiable {
    case controls, mixer, music, clipboard, captures, files, system, tools, calendar, notifications, timer, camera, downloads, scratchpad, agents, watch
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .controls: return "slider.horizontal.3"
        case .mixer: return "speaker.wave.2"
        case .music: return "music.note"
        case .timer: return "timer"
        case .camera: return "web.camera"
        case .downloads: return "arrow.down.circle"
        case .notifications: return "bell"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        case .captures: return "camera.viewfinder"
        case .files: return "tray.full"
        case .system: return "gauge.with.dots.needle.50percent"
        case .tools: return AppFeature.quickLauncher.symbolName
        case .scratchpad: return "note.text"
        case .agents: return "sparkles"
        case .watch: return "eye"
        }
    }

    var shortcutKey: String {
        switch self {
        case .controls: return "c"
        case .mixer: return "v"
        case .music: return "m"
        case .clipboard: return "b"
        case .captures: return "s"
        case .files: return "f"
        case .system: return "i"
        case .tools: return "t"
        case .calendar: return "a"
        case .notifications: return "n"
        case .timer: return "r"
        case .camera: return "w"
        case .downloads: return "d"
        case .scratchpad: return "p"
        case .agents: return "g"
        case .watch: return "o"
        }
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .controls, .music: return true
        case .timer: return AppFeature.notchTimer.isAvailable(in: defaults)
        case .camera: return AppFeature.cameraPreview.isAvailable(in: defaults)
        case .downloads: return AppFeature.notchDownloads.isAvailable(in: defaults)
        case .notifications: return AppFeature.notchNotifications.isAvailable(in: defaults)
        case .calendar: return AppFeature.notchCalendar.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults)
        case .tools: return AppFeature.quickLauncher.isAvailable(in: defaults)
        case .clipboard: return AppFeature.clipboardHistory.isAvailable(in: defaults)
        case .captures:
            return AppFeature.screenshot.isAvailable(in: defaults)
                || AppFeature.screenRecorder.isAvailable(in: defaults)
                || AppFeature.screenOCR.isAvailable(in: defaults)
                || AppFeature.colorPicker.isAvailable(in: defaults)
        case .files: return AppFeature.shelf.isAvailable(in: defaults)
        case .scratchpad: return AppFeature.scratchpad.isAvailable(in: defaults)
        case .agents: return AppFeature.notchAgents.isAvailable(in: defaults)
        case .watch: return AppFeature.notchWatch.isAvailable(in: defaults)
        case .system:
            return [.monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork,
                    .monitorDisk, .monitorPower, .fanControl, .connectedDevices].contains { (feature: AppFeature) in
                feature.isAvailable(in: defaults)
            }
        }
    }
}

enum NotchReopeningDestination: String, CaseIterable {
    case appPanel
}

struct NotchClipboardPastePress: Equatable {
    let serial: Int
    let index: Int

    static func index(keyCode: UInt16, commandOnly: Bool) -> Int? {
        guard commandOnly else { return nil }
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keypadKeys: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]
        return digitKeys.firstIndex(of: keyCode) ?? keypadKeys.firstIndex(of: keyCode)
    }
}

enum NotchDisplay: String, CaseIterable {
    case automatic, builtIn, main, pointer, all
}

enum NotchSilhouette: String, CaseIterable {
    case capsule, notch

    static func current(in defaults: UserDefaults = .standard) -> NotchSilhouette {
        NotchSilhouette(rawValue: defaults.string(forKey: DefaultsKey.notchSilhouette) ?? "") ?? .capsule
    }
}

enum NotchSize: String, CaseIterable {
    case compact, spacious, custom

    static let widthRange = 360.0...600.0
    static let heightRange = 260.0...640.0
    static let defaultWidth = 440.0
    static let defaultHeight = 480.0

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

struct NotchCameraFit: Equatable {
    static let widthRange = -10.0...10.0
    static let heightRange = -6.0...6.0
    static let zero = NotchCameraFit(width: 0, height: 0)

    let width: CGFloat
    let height: CGFloat

    init(width: Double, height: Double) {
        self.width = NotchSize.clamped(width, to: Self.widthRange, fallback: 0).rounded()
        self.height = (NotchSize.clamped(height, to: Self.heightRange, fallback: 0) * 2).rounded() / 2
    }

    static func current(in defaults: UserDefaults = .standard) -> NotchCameraFit {
        NotchCameraFit(width: defaults.double(forKey: DefaultsKey.notchCameraFitWidth),
                       height: defaults.double(forKey: DefaultsKey.notchCameraFitHeight))
    }
}

struct NotchCapsuleFit: Equatable {
    static let widthRange = -40.0...40.0
    static let heightRange = -4.0...4.0
    static let dropRange = 0.0...20.0
    static let zero = NotchCapsuleFit(width: 0, height: 0, drop: 0)

    let width: CGFloat
    let height: CGFloat
    let drop: CGFloat

    init(width: Double, height: Double, drop: Double) {
        self.width = (NotchSize.clamped(width, to: Self.widthRange, fallback: 0) / 2).rounded() * 2
        self.height = NotchSize.clamped(height, to: Self.heightRange, fallback: 0).rounded()
        self.drop = NotchSize.clamped(drop, to: Self.dropRange, fallback: 0).rounded()
    }

    static func current(in defaults: UserDefaults = .standard) -> NotchCapsuleFit {
        NotchCapsuleFit(width: defaults.double(forKey: DefaultsKey.notchCapsuleFitWidth),
                        height: defaults.double(forKey: DefaultsKey.notchCapsuleFitHeight),
                        drop: defaults.double(forKey: DefaultsKey.notchCapsuleFitDrop))
    }
}

enum NotchPageTop: Equatable {
    case row
    case none
    case wrapsCamera
}

extension NotchModule {
    var pageTop: NotchPageTop {
        switch self {
        case .music: return .wrapsCamera
        case .system: return .none
        default: return .row
        }
    }
}

struct NotchBand: Equatable {
    static let cameraClearance: CGFloat = 8
    static let sectionsButtonRoom: CGFloat = 28 + 6

    var besideCamera = false
    var height: CGFloat = NotchLayout.headerHeight
    var side: CGFloat = 0
    var sectionsButton = false
    var trailingSectionsButton = false
    var pageSectionsButton = false

    init() {}

    init(geometry: NotchGeometry, contentWidth: CGFloat) {
        besideCamera = geometry.headerCameraGap > 0
        height = geometry.headerRowHeight
        side = besideCamera
            ? max(0, (contentWidth - geometry.headerCameraGap) / 2 - Self.cameraClearance) : max(0, contentWidth)
        sectionsButton = geometry.rowShowsSectionsButton
        trailingSectionsButton = geometry.sectionsButtonEndsRow && besideCamera && side >= geometry.trailingSectionsRoom
        pageSectionsButton = geometry.sectionsButtonEndsRow && !trailingSectionsButton
    }

    var leadingRoom: CGFloat { max(0, side - (sectionsButton ? Self.sectionsButtonRoom : 0)) }
}

enum NotchLayout {
    static let shoulder: CGFloat = 14
    static let horizontalInset: CGFloat = 28
    static let headerHeight: CGFloat = 36
    static let navigationHeight: CGFloat = 36
    static let spacing: CGFloat = 12
    static let bottomInset: CGFloat = 16
    static var chromeHeight: CGFloat { headerHeight + spacing + bottomInset }
    static let compactContentHeight: CGFloat = 180
    static let spaciousContentHeight: CGFloat = 264
    static let pageContentHeight: CGFloat = 320
    static let rowSpacing: CGFloat = 10
    static let cardHeight: CGFloat = 80
    static let minimumCardHeight: CGFloat = 68
    static let bandLevelMinimumWidth: CGFloat = 76
    static let bandLevelSpacing: CGFloat = 12
    static let levelRowHeight: CGFloat = 28
    static let shortcutHeight: CGFloat = 74
    static let shortcutWidth: CGFloat = 76
    static let shortcutSpacing: CGFloat = 8
    static let shortcutLeastSpacing: CGFloat = 0
    static let shortcutLeastRowSpacing: CGFloat = 6
    static let systemCardHeight: CGFloat = 72
    static let systemCardWidth: CGFloat = 128
    static func systemHoverInset(width: CGFloat) -> CGFloat { ceil(max(0, width) * 0.015) + 1 }
    static let toolHeight: CGFloat = 72
    static let toolWidth: CGFloat = 76
    static let toolSpacing: CGFloat = 6
    static let toolLeastSpacing: CGFloat = 0
    static let sectionTileHeight: CGFloat = 86
    static let sectionTileWidth: CGFloat = 92
    static let sectionSpacing: CGFloat = 8
    static let sectionIndicatorWidth: CGFloat = 12
    static let clipboardSearchHeight: CGFloat = 36
    static let clipboardCardHeight: CGFloat = 104
    static let clipboardCompactCardHeight: CGFloat = 52
    static let clipboardCardSpacing: CGFloat = 8
    static let emptyHeight: CGFloat = 140
    static let musicContentWidth: CGFloat = 344
    static let musicBandSide: CGFloat = 70
    static let musicArtworkSize: CGFloat = 56
    static let musicTitleHeight: CGFloat = 38
    static let musicTimelineHeight: CGFloat = 14
    static let musicTransportHeight: CGFloat = 44
    static let musicHeadSpacing: CGFloat = 14
    static let musicCameraClearance: CGFloat = 6
    static let musicBottomRoom: CGFloat = 8
    static let musicMinimumExtraHeight: CGFloat = 88
    static let timerContentWidth: CGFloat = 344
    static let agentsContentWidth: CGFloat = musicContentWidth
    static let timerRowSpacing: CGFloat = 8
    static let timerSettingsRowHeight: CGFloat = 28
    static let timerRulerHeight: CGFloat = 82
    static let timerMinimumRulerHeight: CGFloat = 56
    static let timerStartHeight: CGFloat = 28
    static let calendarMonthWeekdayHeight: CGFloat = 14
    static var calendarMonthMinimumHeight: CGFloat { calendarMonthWeekdayHeight + 6 * 16 }
    static func calendarMonthRowHeight(height: CGFloat) -> CGFloat {
        min(30, max(16, ((height - calendarMonthWeekdayHeight) / 6).rounded(.down)))
    }

    static func cameraPreviewSize(in size: CGSize) -> CGSize {
        let width = max(0, size.width), height = max(0, size.height)
        return CGSize(width: min(width, height * 16 / 9), height: min(height, width * 3 / 4))
    }
    static let mixerMinimumHeight: CGFloat = 104
    static let compactEdgeGap: CGFloat = 5
    static let compactMusicBarCount = 7
    static let compactMusicBarWidth: CGFloat = 1.8
    static var compactMusicBarsWidth: CGFloat {
        compactMusicBarWidth * (CGFloat(compactMusicBarCount) + CGFloat(compactMusicBarCount - 1) * 0.85)
    }
    static func surfaceRadius(height: CGFloat) -> CGFloat { min(28, height * 0.34) }
    static func shoulder(height: CGFloat) -> CGFloat { min(shoulder, height * 0.19) }
    static let outlineWidth: CGFloat = 2

    // MARK: Capsule

    static let capsuleMargin: CGFloat = 2

    static func capsuleGap(barHeight: CGFloat) -> CGFloat {
        guard barHeight.isFinite else { return 0 }
        return min(capsuleMargin, max(0, ((barHeight - 20) / 2).rounded(.down)))
    }

    static func capsuleRadius(height: CGFloat) -> CGFloat { min(max(0, height) / 2, 28) }

    static let capsuleRestingAspect: CGFloat = 5

    static func capsuleBody(in rect: CGRect, gap: CGFloat) -> CGRect {
        let width = max(0, rect.width), height = max(0, rect.height)
        let side = min(shoulder(height: height), width / 2)
        let inset = min(max(0, gap), height / 2)
        return CGRect(x: rect.minX + side, y: rect.minY + inset,
                      width: width - side * 2, height: height - inset * 2)
    }

    static func capsuleSurface(ofBody body: CGRect, gap: CGFloat) -> CGSize {
        let height = body.height > 0 ? body.maxY + max(0, gap) : body.minY * 2
        return CGSize(width: body.width + shoulder(height: height) * 2, height: max(0, height))
    }

    static func capsulePath(in rect: CGRect, gap: CGFloat) -> CGPath {
        let body = capsuleBody(in: rect, gap: gap)
        let corner = min(capsuleRadius(height: body.height), body.width / 2)
        let handle = corner * (1 - 0.55228475)
        let (left, right, top, bottom) = (body.minX, body.maxX, body.minY, body.maxY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + corner, y: top))
        path.addLine(to: CGPoint(x: right - corner, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + corner), control1: CGPoint(x: right - handle, y: top),
                      control2: CGPoint(x: right, y: top + handle))
        path.addLine(to: CGPoint(x: right, y: bottom - corner))
        path.addCurve(to: CGPoint(x: right - corner, y: bottom), control1: CGPoint(x: right, y: bottom - handle),
                      control2: CGPoint(x: right - handle, y: bottom))
        path.addLine(to: CGPoint(x: left + corner, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: bottom - corner), control1: CGPoint(x: left + handle, y: bottom),
                      control2: CGPoint(x: left, y: bottom - handle))
        path.addLine(to: CGPoint(x: left, y: top + corner))
        path.addCurve(to: CGPoint(x: left + corner, y: top), control1: CGPoint(x: left, y: top + handle),
                      control2: CGPoint(x: left + handle, y: top))
        path.closeSubpath()
        return path
    }

    static let nominalContentTop: CGFloat = 42

    static func preferredWidth(_ layout: NotchSize, custom: CGFloat) -> CGFloat {
        switch layout {
        case .compact: return 480
        case .spacious: return 560
        case .custom: return custom
        }
    }

    static func nominalHeight(_ layout: NotchSize, custom: CGFloat) -> CGFloat {
        switch layout {
        case .compact: return nominalContentTop + chromeHeight + compactContentHeight
        case .spacious: return nominalContentTop + chromeHeight + spaciousContentHeight
        case .custom: return custom
        }
    }

    static func systemRowRanges(count: Int, width: CGFloat) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let columns = railCapacity(width: width, itemWidth: systemCardWidth, spacing: rowSpacing)
        let rows = (count + columns - 1) / columns
        let base = count / rows
        let remainder = count % rows
        return (0..<rows).map { row in
            let start = row * base + min(row, remainder)
            return start..<(start + base + (row < remainder ? 1 : 0))
        }
    }

    // MARK: Rails

    static func railCapacity(width: CGFloat, itemWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, itemWidth > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (itemWidth + spacing)).rounded(.down)))
    }

    static func railRows(count: Int, perRow: Int, rowHeight: CGFloat, spacing: CGFloat, height: CGFloat) -> Int {
        let capacity = max(1, perRow)
        let needed = max(1, (max(0, count) + capacity - 1) / capacity)
        guard rowHeight > 0 else { return 1 }
        guard height.isFinite else { return height > 0 ? needed : 1 }
        let fitting = max(1, Int(((height + spacing) / (rowHeight + spacing)).rounded(.down)))
        return min(needed, fitting)
    }

    static func railHeight(rows: Int, rowHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        CGFloat(max(1, rows)) * rowHeight + CGFloat(max(0, rows - 1)) * spacing
    }

    static func railColumns(count: Int, rows: Int) -> Int {
        (max(0, count) + max(1, rows) - 1) / max(1, rows)
    }

    static func railFits(columns: Int, itemWidth: CGFloat, spacing: CGFloat, width: CGFloat) -> Bool {
        CGFloat(columns) * itemWidth + CGFloat(max(0, columns - 1)) * spacing <= width
    }

    static func railGap(columns: Int, itemWidth: CGFloat, spacing: CGFloat, least: CGFloat, width: CGFloat) -> CGFloat? {
        if railFits(columns: columns, itemWidth: itemWidth, spacing: spacing, width: width) { return spacing }
        guard columns > 1, railFits(columns: columns, itemWidth: itemWidth, spacing: least, width: width) else { return nil }
        return (width - CGFloat(columns) * itemWidth) / CGFloat(columns - 1)
    }

    static func toolTitleInset(count: Int, rows: Int, width: CGFloat) -> CGFloat {
        let gap = railGap(columns: railColumns(count: count, rows: rows), itemWidth: toolWidth, spacing: toolSpacing,
                          least: toolLeastSpacing, width: width)
        return max(0, toolSpacing - (gap ?? toolSpacing)) / 2
    }

    static func musicCardMinimumWidth(height: CGFloat) -> CGFloat {
        max(40, height - 24) + 12 + 132 + 24
    }

    static func naturalContentWidth(_ module: NotchModule, controls: [NotchControlItem], within width: CGFloat) -> CGFloat? {
        switch module {
        case .music: return musicContentWidth
        case .timer: return timerContentWidth
        case .agents: return agentsContentWidth
        case .controls:
            let shortcuts = controls.filter { !$0.isLevel && $0 != .music }.count
            guard shortcuts <= railCapacity(width: width, itemWidth: shortcutWidth, spacing: shortcutSpacing) else { return nil }
            let rail = CGFloat(shortcuts) * (shortcutWidth + shortcutSpacing) - (shortcuts > 0 ? shortcutSpacing : 0)
            let cards = controls.contains(.music) ? musicCardMinimumWidth(height: cardHeight) : 0
            return max(rail, cards, musicContentWidth)
        default: return nil
        }
    }

    static func bandLevelCount(_ levels: Int, band: NotchBand) -> Int {
        let count = max(0, levels)
        guard band.besideCamera else {
            let held = CGFloat(count) * bandLevelMinimumWidth + CGFloat(max(0, count - 1)) * bandLevelSpacing
            return held + bandLevelSpacing <= band.leadingRoom ? count : 0
        }
        return count <= 2 && band.leadingRoom >= bandLevelMinimumWidth ? count : 0
    }

    static let homeReadingWidth: CGFloat = 220
    static let homeReadingMinimumWidth: CGFloat = 160
    static let levelReadingDetailWidth: CGFloat = 92

    static func homeReadingWidth(levels: Int, side: CGFloat) -> CGFloat? {
        let count = max(0, levels)
        let held = count > 0 ? CGFloat(count) * bandLevelMinimumWidth + CGFloat(count - 1) * bandLevelSpacing : 0
        let width = min(homeReadingWidth, side - bandLevelSpacing - held)
        return width >= homeReadingMinimumWidth ? width : nil
    }

    static func controls(hasCards: Bool, levelRow: Bool = false, shortcutCount: Int,
                         width: CGFloat, height: CGFloat) -> NotchControlsLayout {
        let levels = levelRow ? levelRowHeight : 0
        guard hasCards || shortcutCount > 0 else { return NotchControlsLayout(levelRow: levels, cardRow: 0, shortcutRows: 0) }
        let budget = height - (levels > 0 ? levels + rowSpacing : 0)
        var rows = 0, rowGap = shortcutSpacing
        if shortcutCount > 0 {
            let remaining = hasCards ? budget - minimumCardHeight - rowSpacing : budget
            rows = railRows(count: shortcutCount,
                            perRow: railCapacity(width: width, itemWidth: shortcutWidth, spacing: shortcutSpacing),
                            rowHeight: shortcutHeight, spacing: shortcutSpacing, height: remaining)
            if railGap(columns: railColumns(count: shortcutCount, rows: rows), itemWidth: shortcutWidth,
                       spacing: shortcutSpacing, least: shortcutLeastSpacing, width: width) == nil,
               let gap = railGap(columns: rows + 1, itemWidth: shortcutHeight, spacing: shortcutSpacing,
                                 least: shortcutLeastRowSpacing, width: remaining) {
                rows += 1
                rowGap = gap
            }
        }
        let rail = rows > 0 ? railHeight(rows: rows, rowHeight: shortcutHeight, spacing: rowGap) + rowSpacing : 0
        let cardRow = hasCards ? min(cardHeight, max(minimumCardHeight, budget - rail)) : 0
        return NotchControlsLayout(levelRow: levels, cardRow: cardRow, shortcutRows: rows, shortcutRowSpacing: rowGap)
    }

    static func timer(mode: NotchTimerMode, hasSession: Bool, height: CGFloat) -> CGFloat {
        if hasSession { return timerRulerHeight }
        return timerRulerHeight(mode: mode, height: height) + timerBottomRowHeight(mode: mode)
    }

    static func timerBottomRowHeight(mode: NotchTimerMode) -> CGFloat {
        mode == .pomodoro ? timerRowSpacing + timerSettingsRowHeight : 0
    }

    static func timerRulerHeight(mode: NotchTimerMode = .timer, height: CGFloat) -> CGFloat {
        let below = timerBottomRowHeight(mode: mode)
        guard below > 0 else { return timerRulerHeight }
        return min(timerRulerHeight, max(timerMinimumRulerHeight, height - below))
    }

    static func musicHeadHeight(band: CGFloat) -> CGFloat {
        max(musicArtworkSize, band > 0 ? band + musicCameraClearance + musicTitleHeight : 0)
    }
    static func musicPlayerHeight(band: CGFloat, playing: Bool = true, showVolume: Bool = false) -> CGFloat {
        musicHeadHeight(band: band) + musicHeadSpacing
            + (playing ? musicTimelineHeight + rowSpacing : 0) + musicTransportHeight + musicBottomRoom
            + (showVolume ? rowSpacing + levelRowHeight : 0)
    }

    static func musicSplit(height: CGFloat, extras: CGFloat, resting: CGFloat,
                           keepsPlayer: Bool, extraOpen: Bool = true) -> (player: CGFloat, extra: CGFloat, showsPlayer: Bool) {
        let page = max(0, height)
        guard extraOpen else { return (page, 0, true) }
        let room = page - resting - rowSpacing
        if keepsPlayer || room >= musicMinimumExtraHeight {
            return (resting, min(extras, max(0, room)), true)
        }
        return (0, min(extras, page), false)
    }}

enum NotchClipboardKey: Equatable {
    case move(backwards: Bool)
    case paste
    case reveal
}

struct NotchControlsLayout: Equatable {
    var levelRow: CGFloat = 0
    let cardRow: CGFloat
    let shortcutRows: Int
    var shortcutRowSpacing = NotchLayout.shortcutSpacing

    var height: CGFloat {
        let rail = shortcutRows > 0
            ? NotchLayout.railHeight(rows: shortcutRows, rowHeight: NotchLayout.shortcutHeight, spacing: shortcutRowSpacing) : 0
        let rows = [levelRow, cardRow, rail].filter { $0 > 0 }
        return rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * NotchLayout.rowSpacing
    }
}

enum NotchIdleContent: String, CaseIterable {
    case none, battery, music, agents
}

enum BatteryWarning: Equatable {
    case none, early, low
}

struct NotchHoverState {
    private(set) var suppressed = false

    mutating func close(pointerInside: Bool) { suppressed = pointerInside }
    mutating func open() { suppressed = false }
    mutating func update(pointerInside: Bool) {
        if !pointerInside { suppressed = false }
    }
}

enum NotchHoverEmphasis {
    static func size(from resting: CGSize, geometry: NotchGeometry, reach: CGFloat = 0) -> CGSize {
        let occupiedWing = max(0, (resting.width - geometry.cameraWidth) / 2) + reach
        let freeSide = max(0, (geometry.compactSideRoom ?? 0) - occupiedWing)
        guard !geometry.floats else {
            return CGSize(width: resting.width + min(10, freeSide) * 2, height: resting.height)
        }
        if resting.width <= geometry.cameraWidth + 0.5, geometry.cameraWidth > 0, reach == 0 {
            let height = resting.height + 3
            let scale = height / max(1, resting.height)
            let visibleWidth = geometry.cameraWidth * scale
            let width = visibleWidth + NotchLayout.shoulder(height: height) * 2
            let perSide = min(max(0, (width - resting.width) / 2), freeSide)
            return CGSize(width: (resting.width + perSide * 2).rounded(), height: height)
        }
        return CGSize(width: resting.width + min(10, freeSide) * 2, height: resting.height + 5)
    }
}

enum NotchMusicStripPart: Equatable {
    case cover, bars
}

enum NotchMusicStripLayout {
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let artistFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    static let endInset = NotchNotificationBannerLayout.inset
    static let spacing: CGFloat = 8
    static let maximumWing: CGFloat = 240
    static let namingDelay: TimeInterval = 0.3

    static func innerInset(_ geometry: NotchGeometry) -> CGFloat { geometry.isNotched ? 0 : 8 }

    static func coverInset(_ geometry: NotchGeometry) -> CGFloat {
        max(0, min(geometry.compactMusicArtworkInset, geometry.compactActivityWingWidth
                   - min(geometry.compactMusicArtworkSide, 20) - innerInset(geometry)))
    }

    static func coverSide(_ geometry: NotchGeometry) -> CGFloat {
        max(0, min(geometry.compactMusicArtworkSide,
                   geometry.compactActivityWingWidth - coverInset(geometry) - innerInset(geometry)))
    }

    static func fillsCameraGap(_ geometry: NotchGeometry) -> Bool {
        !geometry.isNotched && geometry.compactActivityCameraGap >= 56
    }

    static func showsArtist(_ geometry: NotchGeometry) -> Bool { geometry.compactActivityContentHeight >= 28 }

    private static var measuredWords: (title: String, artist: String?, width: CGFloat)?

    static func wordsWidth(title: String, artist: String?) -> CGFloat {
        if let measured = measuredWords, measured.title == title, measured.artist == artist { return measured.width }
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (String(text.prefix(120)) as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let width = max(width(title, titleFont), artist.map { width($0, artistFont) } ?? 0) + NotchCapsuleLayout.air
        measuredWords = (title, artist, width)
        return width
    }

    static func namedWing(title: String, artist: String?, geometry: NotchGeometry) -> CGFloat {
        let wing = geometry.compactActivityWingWidth
        let shown = showsArtist(geometry) ? artist : nil
        let named = endInset + wordsWidth(title: title, artist: shown) + spacing + wing - coverInset(geometry)
        return max(wing, min(maximumWing, named.rounded(.up)))
    }

    static func namedWings(title: String?, artist: String?, geometry: NotchGeometry,
                           room: CGFloat) -> NotchNoticeWings? {
        let wing = geometry.compactActivityWingWidth
        guard wing > 0, !fillsCameraGap(geometry), let title, !title.isEmpty else { return nil }
        let artist = artist?.trimmingCharacters(in: .whitespaces)
        let named = namedWing(title: title, artist: artist?.isEmpty == false ? artist : nil, geometry: geometry)
        let leading = min(named, geometry.noticeWingWidth(preferred: named), max(0, room).rounded(.down))
        return leading > wing ? NotchNoticeWings(leading: leading, trailing: wing) : nil
    }
}

enum NotchCompactActivity: String, Identifiable {
    case timer, watch, downloads, agents, calendar, music, keepAwake

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .timer: return FeatureStrings.notchActivities(language).timer
        case .watch: return FeatureStrings.notchWatch(language).title
        case .downloads: return FeatureStrings.notchFiles(language).downloadsTitle
        case .agents: return FeatureStrings.notchAgents(language).title
        case .calendar: return FeatureStrings.notchCalendar(language).title
        case .music: return FeatureStrings.notch(language).music
        case .keepAwake: return Strings.localized(language).keepAwakeTitle
        }
    }

    var module: NotchModule {
        switch self {
        case .timer: return .timer
        case .watch: return .watch
        case .downloads: return .downloads
        case .agents: return .agents
        case .calendar: return .calendar
        case .music: return .music
        case .keepAwake: return .controls
        }
    }

    var symbol: String {
        self == .keepAwake ? NotchControlItem.keepAwake.symbol : module.symbol
    }
}

struct NotchActivityCombination: Hashable, Identifiable {
    let primary: NotchCompactActivity
    let companion: NotchCompactActivity

    var id: String { primary.rawValue + "+" + companion.rawValue }

    func title(_ language: AppLanguage) -> String {
        companion.title(language) + " + " + primary.title(language)
    }
}

final class NotchMirrorModel: ObservableObject {
    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var strip: NotchGeometry
    @Published private(set) var size: CGSize
    @Published private(set) var activity: NotchCompactActivity?
    var shown = false
    var outline: Bool?
    var timerOutline = false

    init(geometry: NotchGeometry, size: CGSize) {
        self.geometry = geometry
        strip = geometry
        self.size = size
    }

    func update(geometry: NotchGeometry, strip: NotchGeometry, size: CGSize, activity: NotchCompactActivity?) -> Bool {
        guard self.geometry != geometry || self.strip != strip || self.size != size || self.activity != activity else {
            return false
        }
        self.geometry = geometry
        self.strip = strip
        self.size = size
        self.activity = activity
        return true
    }
}

struct NotchActivitySelection {
    private(set) var preferred: NotchCompactActivity?
    private(set) var companion: NotchCompactActivity?

    mutating func select(_ activity: NotchCompactActivity, companion: NotchCompactActivity? = nil,
                         available: [NotchCompactActivity], companions: [NotchCompactActivity] = []) {
        guard available.contains(activity) else { return }
        if let companion, !companions.contains(companion) { return }
        preferred = activity
        self.companion = companion
    }

    private var lastAvailable: [NotchCompactActivity] = []

    mutating func reconcile(available: [NotchCompactActivity]) {
        defer { lastAvailable = available }
        guard available.isEmpty || available != lastAvailable else { return }
        preferred = nil
        companion = nil
    }

    func companion(available companions: [NotchCompactActivity]) -> NotchCompactActivity? {
        guard preferred != nil, let companion, companions.contains(companion) else { return nil }
        return companion
    }

    func current(available: [NotchCompactActivity]) -> NotchCompactActivity? {
        if let preferred, available.contains(preferred) { return preferred }
        return available.first
    }
}

enum NotchCapsuleLayout {
    static let endPadding: CGFloat = 8
    static let spacing: CGFloat = 6
    static let groupSpacing: CGFloat = 10
    static let symbolSize: CGFloat = 12
    static let symbolWidth: CGFloat = 16
    static let meterWidth: CGFloat = 56
    static let meterHeight: CGFloat = 4
    static var barsWidth: CGFloat { NotchLayout.compactMusicBarsWidth }
    static let air: CGFloat = 2
    static let markSpacing: CGFloat = 4
    static let calendarDotSide: CGFloat = 6
    static let downloadMeterWidth: CGFloat = 36
    static let spinnerWidth: CGFloat = 16
    static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let detailFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let levelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    static let readingFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    enum Maximum {
        static let notification: CGFloat = 380
        static let notice: CGFloat = 340
        static let music: CGFloat = 260
        static let calendar: CGFloat = 300
        static let download: CGFloat = 280
        static let activity: CGFloat = 220
    }

    static func width(_ text: String, font: NSFont) -> CGFloat {
        text.isEmpty ? 0 : (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + air
    }

    private static var symbolDrops: [String: CGFloat] = [:]

    static func symbolDrop(_ name: String, size: CGFloat = symbolSize, weight: NSFont.Weight = .medium) -> CGFloat {
        let key = "\(name) \(size) \(weight.rawValue)"
        if let drop = symbolDrops[key] { return drop }
        let drop = measuredSymbolDrop(name, size: size, weight: weight)
        symbolDrops[key] = drop
        return drop
    }

    private static func measuredSymbolDrop(_ name: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let scale: CGFloat = 4
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight)),
              image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((image.size.width * scale).rounded(.up)),
                                         pixelsHigh: Int((image.size.height * scale).rounded(.up)),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else { return 0 }
        rep.size = image.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return 0 }
        var top: Int?, bottom = 0
        for y in 0..<rep.pixelsHigh {
            let row = data + y * rep.bytesPerRow
            if (0..<rep.pixelsWide).contains(where: { row[$0 * 4 + 3] > 80 }) { top = top ?? y; bottom = y + 1 }
        }
        guard let top else { return 0 }
        return CGFloat(top + bottom) / 2 / scale - image.size.height / 2
    }

    static func artworkSide(_ geometry: NotchGeometry) -> CGFloat { max(0, geometry.stripBodyHeight - 6) }
    static func artworkInset(_ geometry: NotchGeometry) -> CGFloat { (geometry.stripBodyHeight - artworkSide(geometry)) / 2 }

    static func side(_ geometry: NotchGeometry) -> CGFloat { NotchLayout.shoulder(height: geometry.stripHeight) }

    static func availableWidth(_ geometry: NotchGeometry) -> CGFloat {
        let room = geometry.compactSideRoom ?? 0
        return max(0, min(geometry.screen.width - 24, geometry.cameraWidth + 2 * (room.isFinite ? max(0, room) : 0)))
    }

    static func surface(content: CGFloat, leading: CGFloat = endPadding, trailing: CGFloat = endPadding,
                        maximum: CGFloat, geometry: NotchGeometry) -> CGSize {
        let side = side(geometry)
        let resting = geometry.restingSize(showsContent: false).width
        let limit = max(resting, min(maximum + side * 2, availableWidth(geometry)).rounded(.down))
        let wanted = (max(0, content.isFinite ? content : 0) + leading + trailing + side * 2).rounded(.up)
        return CGSize(width: min(limit, max(resting, wanted)), height: geometry.stripHeight)
    }

    static func barsHeight(_ geometry: NotchGeometry) -> CGFloat { min(16, max(6, geometry.stripBodyHeight - 8)) }

    static func agentMarkSize(working: Int) -> CGFloat { working > 1 ? 10 : 12 }
    static func agentMarksWidth(working: Int) -> CGFloat {
        let count = max(1, working)
        return CGFloat(count) * (agentMarkSize(working: count) * 1.45 + 1) + CGFloat(count - 1)
    }

    static func levelReadingWidth(_ detail: String) -> CGFloat {
        max(width(detail, font: levelFont), width("100%", font: levelFont))
    }

    static func downloadPercentWidth(_ language: AppLanguage) -> CGFloat {
        width((1.0).formatted(NotchDownloadSupport.percentFormat(language)), font: smallFont)
    }

    static func calendarTitle(_ countdown: NotchCalendarCountdown, language: AppLanguage) -> String {
        let title = countdown.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? FeatureStrings.notchCalendar(language).untitled : title
    }

    static func noticeContent(title: String, detail: String, level: Bool) -> CGFloat {
        if level { return symbolWidth + spacing + meterWidth + spacing + levelReadingWidth(detail) }
        let detailWidth = width(detail, font: detailFont)
        return symbolWidth + spacing + width(title, font: titleFont) + (detailWidth > 0 ? groupSpacing + detailWidth : 0)
    }

    static func notificationContent(title: String, message: String, geometry: NotchGeometry) -> CGFloat {
        let messageWidth = width(message, font: detailFont)
        return notificationIconSide(geometry) + spacing + width(title, font: titleFont)
            + (messageWidth > 0 ? groupSpacing + messageWidth : 0)
    }

    static func notificationIconSide(_ geometry: NotchGeometry) -> CGFloat { min(16, max(0, geometry.stripBodyHeight - 4)) }

    static func musicSurface(title: String?, geometry: NotchGeometry) -> CGSize {
        let named = title.map { endPadding + width($0, font: titleFont) + endPadding } ?? endPadding
        let content = artworkSide(geometry) + named + barsWidth
        return surface(content: content, leading: artworkInset(geometry), maximum: Maximum.music, geometry: geometry)
    }

    static func timerMarkWidth(companion: NotchCompactActivity?, workingAgents: Int, downloadPercent: Bool,
                               geometry: NotchGeometry, language: AppLanguage,
                               calendarLeadTime: TimeInterval = NotchCalendarSupport.timeLeftLeadTime) -> CGFloat {
        switch companion {
        case .downloads:
            return symbolWidth + (downloadPercent ? markSpacing + downloadPercentWidth(language) : 0)
        case .agents: return agentMarksWidth(working: workingAgents)
        case .music: return artworkSide(geometry)
        case .calendar: return calendarClockWidth(leadTime: calendarLeadTime)
        default: return symbolWidth
        }
    }

    static func calendarClockWidth(leadTime: TimeInterval = NotchCalendarSupport.timeLeftLeadTime) -> CGFloat {
        calendarDotSide + markSpacing + width(NotchCalendarSupport.countdownShape(leadTime: leadTime), font: readingFont)
    }

    static func markGap(_ companion: NotchCompactActivity?) -> CGFloat { companion == .calendar ? groupSpacing : spacing }

    static func timerSurface(reading: String, companion: NotchCompactActivity?, workingAgents: Int,
                             downloadPercent: Bool, geometry: NotchGeometry, language: AppLanguage,
                             calendarLeadTime: TimeInterval = NotchCalendarSupport.timeLeftLeadTime) -> CGSize {
        let mark = timerMarkWidth(companion: companion, workingAgents: workingAgents, downloadPercent: downloadPercent,
                                  geometry: geometry, language: language, calendarLeadTime: calendarLeadTime)
        let content = mark + markGap(companion) + width(NotchAgentSupport.readingShape(reading), font: readingFont)
        return surface(content: content, leading: companion == .music ? artworkInset(geometry) : endPadding,
                       maximum: Maximum.activity, geometry: geometry)
    }

    static func calendarPairSurface(companion: NotchCompactActivity, workingAgents: Int, downloadPercent: Bool,
                                    geometry: NotchGeometry, language: AppLanguage,
                                    calendarLeadTime: TimeInterval = NotchCalendarSupport.timeLeftLeadTime) -> CGSize {
        let mark = timerMarkWidth(companion: companion, workingAgents: workingAgents, downloadPercent: downloadPercent,
                                  geometry: geometry, language: language)
        return surface(content: mark + markGap(.calendar) + calendarClockWidth(leadTime: calendarLeadTime),
                       leading: companion == .music ? artworkInset(geometry) : endPadding,
                       maximum: Maximum.activity, geometry: geometry)
    }

    static func keepAwakeSurface(reading: String?, geometry: NotchGeometry) -> CGSize {
        let cup = NotchKeepAwakeSupport.symbolWidth(NotchKeepAwakeSupport.symbol, size: symbolSize)
        let right = reading.map { width(NotchAgentSupport.readingShape($0), font: readingFont) }
            ?? NotchKeepAwakeSupport.symbolWidth(NotchKeepAwakeSupport.openSymbol, size: readingFont.pointSize) + air
        return surface(content: cup + spacing + right, maximum: Maximum.activity, geometry: geometry)
    }

    static func agentSurface(reading: String, working: Int, geometry: NotchGeometry) -> CGSize {
        let content = agentMarksWidth(working: working) + spacing
            + width(NotchAgentSupport.readingShape(reading), font: readingFont)
        return surface(content: content, maximum: Maximum.activity, geometry: geometry)
    }

    static func downloadSurface(name: String, hasProgress: Bool, geometry: NotchGeometry, language: AppLanguage) -> CGSize {
        let progress = hasProgress ? groupSpacing + downloadMeterWidth + spacing + downloadPercentWidth(language)
            : spacing + spinnerWidth
        let content = symbolWidth + spacing + width(name, font: detailFont) + progress
        return surface(content: content, maximum: Maximum.download, geometry: geometry)
    }

    static func calendarSurface(title: String, time: String, geometry: NotchGeometry,
                                calendarLeadTime: TimeInterval = NotchCalendarSupport.timeLeftLeadTime) -> CGSize {
        let content = calendarDotSide + spacing + width(title, font: titleFont) + groupSpacing
            + width(NotchCalendarSupport.countdownShape(leadTime: calendarLeadTime), font: readingFont)
            + markSpacing + width(time, font: smallFont)
        return surface(content: content, maximum: Maximum.calendar, geometry: geometry)
    }

    static func watchSurface(reading: String, thumbnail: Bool, geometry: NotchGeometry) -> CGSize {
        let right = thumbnail ? NotchWatchSupport.thumbnailWidth
            : reading.isEmpty ? spinnerWidth : width(reading, font: levelFont)
        return surface(content: symbolWidth + spacing + right, maximum: Maximum.activity, geometry: geometry)
    }

    static func captureSurface(geometry: NotchGeometry) -> CGSize {
        surface(content: symbolWidth * 2 + spacing, maximum: Maximum.activity, geometry: geometry)
    }
}

struct NotchActivityPickerLayout {
    static let rowHeight: CGFloat = 32
    static let spacing: CGFloat = 6
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 12
    static let combinationHeight: CGFloat = 24
    let columns: Int
    let headerHeight: CGFloat
    let size: CGSize

    init(count: Int, labelWidth: CGFloat, stripSize: CGSize, screenWidth: CGFloat,
         hasCombinations: Bool = false) {
        columns = min(3, max(1, count))
        headerHeight = stripSize.height
        let rows = (max(1, count) + columns - 1) / columns
        let width = CGFloat(columns) * (labelWidth + 48)
            + CGFloat(columns - 1) * Self.spacing + Self.horizontalInset * 2
        size = CGSize(width: min(max(stripSize.width + Self.horizontalInset * 2, width), max(1, screenWidth - 24)),
                      height: headerHeight + CGFloat(rows) * Self.rowHeight
                        + CGFloat(rows - 1) * Self.spacing + Self.verticalInset * 2
                        + (hasCombinations ? Self.combinationHeight + Self.spacing : 0))
    }
}

struct NotchCaptureControlsLayout {
    static let rowHeight: CGFloat = 28
    static let buttonSpacing: CGFloat = 6
    static let narrowButtonsWidth: CGFloat = 28 * 3 + buttonSpacing * 2
    static let cameraClearance: CGFloat = 8
    static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    static func titleWidth(_ title: String) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: titleFont]).width.rounded(.up)
    }
    let headerTop: CGFloat
    let headerHeight: CGFloat
    let cameraGap: CGFloat
    let sideWidth: CGFloat
    let size: CGSize

    init(geometry: NotchGeometry, titleWidth: CGFloat, capturesAudio: Bool) {
        let side = (geometry.contentWidth - geometry.headerCameraGap) / 2
        let fits = max(titleWidth, Self.narrowButtonsWidth) + Self.cameraClearance <= side
        if geometry.headerTopInset == 0 || geometry.floats, geometry.headerCameraGap == 0 || fits {
            headerTop = geometry.headerTopInset
            headerHeight = geometry.headerRowHeight
            cameraGap = geometry.headerCameraGap
        } else {
            headerTop = geometry.safeContentTop
            headerHeight = Self.rowHeight
            cameraGap = 0
        }
        sideWidth = cameraGap > 0 ? side : 0
        size = CGSize(width: geometry.expandedWidth,
                      height: headerTop + headerHeight + 12 + NotchLayout.shortcutHeight + 16
                        + (capturesAudio ? 40 : 0))
    }
}

enum NotchControlSetupRequirement: Equatable {
    case feature(AppFeature)
    case page(NotchModule, feature: AppFeature?)
    case none
}

enum NotchControlItem: String, CaseIterable, Identifiable {
    case volume, brightness, keyboardLight, music, mixer, keepAwake, timer, calendar, microphone, screenshot, recording, speedTest, panel, commandBar, scratchpad
    static let defaultHidden = "keyboardLight,microphone,screenshot,recording,speedTest,panel,commandBar,scratchpad"
    var id: String { rawValue }

    var isLevel: Bool { self == .volume || self == .brightness || self == .keyboardLight }

    static var keyboardLightIsSupported: () -> Bool = { true }

    var symbol: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .keyboardLight: return "light.max"
        case .keepAwake: return "cup.and.saucer"
        case .microphone: return "mic.fill"
        case .screenshot: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .speedTest: return "speedometer"
        case .panel: return "bubble.middle.top"
        case .mixer: return NotchModule.mixer.symbol
        case .commandBar: return "command"
        case .scratchpad: return "note.text"
        case .music: return NotchModule.music.symbol
        case .timer: return NotchModule.timer.symbol
        case .calendar: return NotchModule.calendar.symbol
        }
    }

    var setupRequirement: NotchControlSetupRequirement {
        switch self {
        case .volume: return .feature(.mixer)
        case .brightness, .keyboardLight: return .feature(.brightness)
        case .keepAwake: return .feature(.keepAwake)
        case .microphone: return .feature(.micMute)
        case .screenshot: return .feature(.screenshot)
        case .recording: return .feature(.screenRecorder)
        case .commandBar: return .feature(.commandBar)
        case .scratchpad: return .feature(.scratchpad)
        case .panel: return .none
        case .mixer: return .page(.mixer, feature: .mixer)
        case .speedTest: return .page(.system, feature: .monitorNetwork)
        case .music: return .page(.music, feature: nil)
        case .timer: return .page(.timer, feature: .notchTimer)
        case .calendar: return .page(.calendar, feature: .notchCalendar)
        }
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .mixer: return AppFeature.mixer.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.mixer)
        case .brightness: return AppFeature.brightness.isAvailable(in: defaults)
        case .keyboardLight: return AppFeature.brightness.isAvailable(in: defaults) && Self.keyboardLightIsSupported()
        case .keepAwake: return AppFeature.keepAwake.isAvailable(in: defaults)
        case .microphone: return AppFeature.micMute.isAvailable(in: defaults)
        case .screenshot: return AppFeature.screenshot.isAvailable(in: defaults)
        case .recording: return AppFeature.screenRecorder.isAvailable(in: defaults)
        case .speedTest: return AppFeature.monitorNetwork.isAvailable(in: defaults) && NotchSupport.modules(in: defaults).contains(.system)
        case .commandBar: return AppFeature.commandBar.isAvailable(in: defaults)
        case .scratchpad: return AppFeature.scratchpad.isAvailable(in: defaults)
        case .panel: return true
        case .music: return NotchSupport.modules(in: defaults).contains(.music)
        case .timer: return NotchSupport.modules(in: defaults).contains(.timer)
        case .calendar: return NotchSupport.modules(in: defaults).contains(.calendar)
        }
    }
}

enum NotchQuickAccessSide: String, CaseIterable, Codable {
    case left, right, bottom
}

enum NotchQuickAction: Hashable, Identifiable {
    case settings, pin, module(NotchModule), control(NotchControlItem)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .pin: return "pin"
        case .module(let module): return module.rawValue
        case .control(let item): return "control." + item.rawValue
        }
    }

    init?(id: String) {
        switch id {
        case "settings": self = .settings
        case "pin": self = .pin
        default:
            if id.hasPrefix("control."), let item = NotchControlItem(rawValue: String(id.dropFirst(8))) {
                self = .control(item)
            } else if let module = NotchModule(rawValue: id) { self = .module(module) }
            else { return nil }
        }
    }

    static var optionalActions: [Self] {
        [.settings, .pin] + NotchModule.allCases.map(Self.module)
            + NotchControlItem.allCases.filter { !$0.isLevel }.map(Self.control)
    }

    func isAvailable(in defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .module(let module): return NotchSupport.modules(in: defaults).contains(module)
        case .control(let item): return item.isAvailable(in: defaults)
        default: return true
        }
    }
}

struct NotchQuickButton: Codable, Equatable, Identifiable {
    var id: UUID
    var actionID: String
    var side: NotchQuickAccessSide
    var label: String

    init(id: UUID = UUID(), action: NotchQuickAction, side: NotchQuickAccessSide, label: String = "") {
        self.id = id
        actionID = action.id
        self.side = side
        self.label = label
    }

    var action: NotchQuickAction? { NotchQuickAction(id: actionID) }
}

struct NotchQuickAccessConfiguration: Equatable, Codable {
    var buttons: [NotchQuickButton]
    private var version = 1
    static let maximumPerSide = 3
    static let initial = Self(buttons: [
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, action: .module(.scratchpad), side: .left),
        NotchQuickButton(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, action: .module(.agents), side: .right),
    ])
    var actions: [NotchQuickAction] { buttons.compactMap(\.action) }
    var hasBottom: Bool { buttons.contains { $0.side == .bottom } }

    init(buttons: [NotchQuickButton]) { self.buttons = buttons }

    init(side: NotchQuickAccessSide, actions: [NotchQuickAction]) {
        buttons = actions.enumerated().map { index, action in
            NotchQuickButton(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                             action: action, side: side)
        }
    }

    func sanitized() -> Self {
        var ids = Set<UUID>()
        var counts: [NotchQuickAccessSide: Int] = [:]
        let safe = buttons.prefix(64).compactMap { button -> NotchQuickButton? in
            guard button.action != nil, ids.insert(button.id).inserted,
                  counts[button.side, default: 0] < Self.maximumPerSide else { return nil }
            counts[button.side, default: 0] += 1
            var result = button
            result.label = String(button.label.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            return result
        }
        return Self(buttons: safe)
    }

    var encoded: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(sanitized())) ?? Data()
    }

    static func stored(in defaults: UserDefaults = .standard) -> Self {
        return .initial
    }

    static func current(in defaults: UserDefaults = .standard) -> Self {
        var configuration = stored(in: defaults)
        configuration.buttons = configuration.shown(in: defaults)
        return configuration
    }

    func shown(in defaults: UserDefaults = .standard) -> [NotchQuickButton] {
        buttons.filter { $0.action?.isAvailable(in: defaults) == true }
    }

    func hasRoom(on side: NotchQuickAccessSide) -> Bool {
        buttons.filter { $0.side == side }.count < Self.maximumPerSide
    }

    @discardableResult
    mutating func reorder(_ id: UUID, by offset: Int) -> Bool {
        guard let from = buttons.firstIndex(where: { $0.id == id }) else { return false }
        let side = buttons[from].side
        let items = buttons.filter { $0.side == side }
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset),
              let to = buttons.firstIndex(where: { $0.id == items[index + offset].id }) else { return false }
        buttons.swapAt(from, to)
        return true
    }

    mutating func move(_ id: UUID, to side: NotchQuickAccessSide, before target: UUID? = nil) {
        guard let index = buttons.firstIndex(where: { $0.id == id }),
              buttons[index].side == side || hasRoom(on: side) else { return }
        var item = buttons.remove(at: index)
        item.side = side
        let destination = target.flatMap { target in buttons.firstIndex(where: { $0.id == target && $0.side == side }) }
        buttons.insert(item, at: destination ?? buttons.endIndex)
    }
}

struct NotchQuickAccessPlacement: Equatable, Identifiable {
    let button: NotchQuickButton
    let index: Int
    let edge: CGFloat
    let top: CGFloat
    var height: CGFloat = NotchQuickAccessLayout.width
    var id: UUID { button.id }
    var side: NotchQuickAccessSide { button.side }
    func center(progress: CGFloat) -> CGPoint {
        NotchQuickAccessLayout.center(index: index, progress: progress, edge: edge, top: top, side: side)
    }
}

enum NotchQuickAccessLayout {
    static let width: CGFloat = 40
    static let maximumHeight: CGFloat = 92
    static let diameter: CGFloat = width
    static let gap: CGFloat = 10
    static let gutter: CGFloat = 64
    static let rowSpacing: CGFloat = 54
    static let withdrawalDuration = 0.06
    static let hoverMargin: CGFloat = 16
    static let hoverExitDelay = 0.18

    static func center(index: Int, progress: CGFloat, edge: CGFloat, top: CGFloat,
                       side: NotchQuickAccessSide) -> CGPoint {
        let phase = progress.isFinite ? min(1.1, max(0, progress)) : 0
        let offset = -14 + phase * (14 + gap + width / 2)
        if side == .bottom { return CGPoint(x: top + CGFloat(index) * rowSpacing, y: edge + offset) }
        return CGPoint(x: edge + (side == .left ? -offset : offset), y: top)
    }

    static func frame(of placement: NotchQuickAccessPlacement) -> CGRect {
        let center = center(index: placement.index, progress: 1, edge: placement.edge, top: placement.top,
                            side: placement.side)
        return CGRect(x: center.x - width / 2, y: center.y - placement.height / 2,
                      width: width, height: placement.height)
    }

    static func hoverRect(_ placement: NotchQuickAccessPlacement) -> CGRect {
        frame(of: placement).union(CGRect(x: placement.edge, y: placement.top - placement.height / 2,
                                          width: 0, height: placement.height))
            .insetBy(dx: -hoverMargin, dy: -hoverMargin)
    }

    static func placements(_ configuration: NotchQuickAccessConfiguration, body: CGRect, headerTop: CGFloat) -> [NotchQuickAccessPlacement] {
        var indices: [NotchQuickAccessSide: Int] = [:]
        return configuration.buttons.map { button in
            let index = indices[button.side, default: 0]
            indices[button.side] = index + 1
            let edge = button.side == .bottom ? body.maxY : button.side == .left ? body.minX : body.maxX
            let pillTop = headerTop - width / 2
            let pillBottom = min(body.maxY - 14, pillTop + maximumHeight)
            let height = max(width, pillBottom - pillTop)
            return NotchQuickAccessPlacement(button: button, index: index, edge: edge,
                                             top: pillTop + height / 2, height: height)
        }
    }

    static func contains(_ point: CGPoint, placement: NotchQuickAccessPlacement) -> Bool {
        frame(of: placement).contains(point)
    }
}

enum NotchEvent: String, CaseIterable {
    case volume, brightness, battery, clipboard, capture, systemNotification, keyboardLight, timer, accessory, download, agents, track, microphone, watch, inputSource

    var preferenceKey: String {
        switch self {
        case .microphone: return DefaultsKey.notchMicrophone
        case .track: return DefaultsKey.notchTrackChange
        case .timer: return DefaultsKey.notchTimerEnabled
        case .watch: return DefaultsKey.notchWatchEnabled
        case .accessory: return DefaultsKey.notchAccessoriesEnabled
        case .download: return DefaultsKey.notchDownloadsEnabled
        case .agents: return DefaultsKey.notchAgentsEnabled
        case .systemNotification: return DefaultsKey.notchNotificationsEnabled
        case .keyboardLight: return DefaultsKey.notchKeyboardLight
        case .inputSource: return DefaultsKey.notchInputSource
        case .volume: return DefaultsKey.notchVolume
        case .brightness: return DefaultsKey.notchBrightness
        case .battery: return DefaultsKey.notchBattery
        case .clipboard: return DefaultsKey.notchClipboard
        case .capture: return DefaultsKey.notchCapture
        }
    }

    var priority: Int {
        switch self {
        case .volume, .brightness, .keyboardLight, .microphone, .inputSource: return 3
        case .capture, .timer, .watch: return 2
        case .battery, .systemNotification, .accessory, .agents: return 1
        case .clipboard, .download, .track: return 0
        }
    }

    var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardLight, .microphone, .inputSource: return 1.6
        case .systemNotification, .track: return 3
        case .timer, .download, .watch: return 6
        case .agents: return 5
        case .battery, .accessory: return 4
        case .clipboard: return 2.5
        case .capture: return 12
        }
    }
}

enum NotchSupport {
    static var hasNotchedDisplay: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    static var hasDisplayWithoutNotch: Bool {
        NSScreen.screens.contains { !($0.safeAreaInsets.top > 0) }
    }

    static let toolColumns = 5
    static let defaultHoverDelay = 0.25
    static let hoverDelayRange = 0.10...1.0

    static func screenEdgeArea(_ area: CGRect, contains point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: area.size).contains(CGPoint(x: point.x - area.minX, y: area.maxY - point.y))
    }

    static func sanitizedHoverDelay(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(hoverDelayRange.upperBound, max(hoverDelayRange.lowerBound, value)) : defaultHoverDelay
    }

    static let defaultCloseDelay = NotchQuickAccessLayout.hoverExitDelay
    static let closeDelayRange = 0.10...2.0

    static func sanitizedCloseDelay(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(closeDelayRange.upperBound, max(closeDelayRange.lowerBound, value)) : defaultCloseDelay
    }

    static func closeDelay(in defaults: UserDefaults = .standard) -> TimeInterval {
        sanitizedCloseDelay(defaults.object(forKey: DefaultsKey.notchCloseDelay) as? Double ?? defaultCloseDelay)
    }

    static func moduleShortcut(_ characters: String, modules: [NotchModule]) -> NotchModule? {
        modules.first { $0.shortcutKey == characters.lowercased() }
    }

    static func filteredModules(_ modules: [NotchModule], query: String,
                                title: (NotchModule) -> String) -> [NotchModule] {
        let terms = CommandBarSearch.normalized(query).split(separator: " ")
        guard !terms.isEmpty else { return modules }
        return modules.filter { module in
            let name = CommandBarSearch.normalized(title(module))
            return terms.allSatisfy { name.contains($0) }
        }
    }

    static func adjacentModule(to selected: NotchModule?, modules: [NotchModule], backwards: Bool) -> NotchModule? {
        guard !modules.isEmpty else { return nil }
        guard let selected, let index = modules.firstIndex(of: selected) else { return modules.first }
        return modules[(index + (backwards ? modules.count - 1 : 1)) % modules.count]
    }

    static func steppedItem<ID: Equatable>(from current: ID?, in ids: [ID], backwards: Bool) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[min(max(index + (backwards ? -1 : 1), 0), ids.count - 1)]
    }

    static func clipboardPasteTarget<ID: Equatable>(highlighted: ID?, in ids: [ID]) -> ID? {
        if let highlighted, ids.contains(highlighted) { return highlighted }
        return ids.first
    }

    static func searchHighlight<ID: Equatable>(keeping current: ID?, in ids: [ID], query: String) -> ID? {
        if let current, ids.contains(current) { return current }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ids.first
    }

    static func restingClipboardHighlight<ID>(_ entries: [(ID, Bool)]) -> ID? {
        (entries.first { !$0.1 } ?? entries.first)?.0
    }

    static func clipboardKey(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags,
                             composing: Bool) -> NotchClipboardKey? {
        let shortcutModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if !composing, shortcutModifiers == .control {
            switch characters.lowercased() {
            case "n": return .move(backwards: false)
            case "p": return .move(backwards: true)
            default: break
            }
        }
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        guard !composing else { return .reveal }
        switch keyCode {
        case 125, 126: return modifiers.contains(.shift) ? nil : .move(backwards: keyCode == 126)
        case 36, 76: return modifiers.contains(.shift) ? nil : .paste
        default: break
        }
        let typed = !characters.isEmpty && !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && characters.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }
        return typed ? .reveal : nil
    }

    static func clipboardOpenOffset(rowTop: CGFloat, rowHeight: CGFloat, height: CGFloat,
                                    visibleHeight: CGFloat) -> CGFloat {
        min(rowHeight, max(-height, max(-rowTop, min(0, visibleHeight - rowTop - height))))
    }

    static func clipboardOpeningScroll(index: Int, rowHeight: CGFloat, spacing: CGFloat, shown: CGFloat,
                                       visibleHeight: CGFloat) -> Int {
        let lowest = ((visibleHeight - min(shown, rowHeight)) / (rowHeight + spacing)).rounded(.down)
        return min(max(0, index), max(0, index - Int(lowest)))
    }

    static func compactActivity(timer: Bool, downloads: Bool, agents: Bool = false,
                                calendar: Bool = false, music: Bool, keepAwake: Bool = false) -> NotchCompactActivity? {
        compactActivities(timer: timer, downloads: downloads, agents: agents,
                          calendar: calendar, music: music, keepAwake: keepAwake).first
    }

    static func compactActivities(timer: Bool, watch: Bool = false, downloads: Bool, agents: Bool,
                                  calendar: Bool, music: Bool, keepAwake: Bool = false) -> [NotchCompactActivity] {
        let candidates: [(Bool, NotchCompactActivity)] = [
            (timer, .timer), (watch, .watch), (downloads, .downloads), (agents, .agents),
            (calendar, .calendar), (music, .music), (keepAwake, .keepAwake)
        ]
        return candidates.compactMap { $0.0 ? $0.1 : nil }
    }

    static func compactCompanions(of primary: NotchCompactActivity, timer: Bool, running: Bool, downloads: Bool,
                                  agents: Bool, calendar: Bool, music: Bool) -> [NotchCompactActivity] {
        let pairs: [(Bool, NotchCompactActivity)]
        switch primary {
        case .timer where timer:
            pairs = [(downloads, .downloads), (running && agents, .agents), (running && calendar, .calendar),
                     (running && music, .music)]
        case .calendar where calendar:
            pairs = [(downloads, .downloads), (agents, .agents), (music, .music)]
        default:
            pairs = []
        }
        return pairs.compactMap { $0.0 ? $0.1 : nil }
    }

    static func gestureIsOverHeader(expanded: Bool, peeking: Bool, fromTop: CGFloat, safeTop: CGFloat,
                                    height: CGFloat = NotchLayout.headerHeight) -> Bool {
        (expanded || peeking) && (safeTop...safeTop + height).contains(fromTop)
    }

    static func keepsPermissionSurface(requesting: Bool, resolvedAt: TimeInterval?, now: TimeInterval) -> Bool {
        if requesting { return true }
        guard let resolvedAt, now.isFinite, resolvedAt.isFinite else { return false }
        return (0..<1).contains(now - resolvedAt)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notch.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchEnabled)
    }

    static func usesHapticFeedback(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchHapticFeedback)
    }

    static func holdsShortcut(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchShortcutEnabled)
    }

    static func modules(in defaults: UserDefaults = .standard) -> [NotchModule] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenModules) ?? "")
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchModuleOrder) ?? "")
            .split(separator: ",").compactMap { NotchModule(rawValue: String($0)) }
        var seen = Set<NotchModule>()
        let everything: [NotchModule] = [.music, .scratchpad, .agents]
        _ = stored
        return everything.filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
                && ($0 != .timer || defaults.bool(forKey: DefaultsKey.notchTimerEnabled))
                && ($0 != .camera || defaults.bool(forKey: DefaultsKey.notchCameraEnabled))
                && ($0 != .calendar || defaults.bool(forKey: DefaultsKey.notchCalendarEnabled))
                && ($0 != .notifications || defaults.bool(forKey: DefaultsKey.notchNotificationsEnabled))
                && ($0 != .agents || defaults.bool(forKey: DefaultsKey.notchAgentsEnabled))
                && ($0 != .watch || defaults.bool(forKey: DefaultsKey.notchWatchEnabled))
        }
    }

    static func watchesMusicActivity(in defaults: UserDefaults = .standard) -> Bool {
        let choice = idleContent(in: defaults)
        let companionOccupiesRest = choice == .none && NotchMascotSupport.isEnabled(in: defaults)
        return isEnabled(in: defaults) && modules(in: defaults).contains(.music)
            && (choice != .none || companionOccupiesRest)
            && (defaults.object(forKey: DefaultsKey.notchShowPlayingMusic) as? Bool ?? true)
    }

    static func showsMusicActivity(isPlaying: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isPlaying && watchesMusicActivity(in: defaults)
    }

    static func showsMusicVolume(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchMusicShowVolume) && AppFeature.mixer.isAvailable(in: defaults)
    }

    static func showsInCaptures(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchShowInCaptures) as? Bool ?? true
    }

    static func coversMenus(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchCoversMenus) as? Bool ?? true
    }

    static let defaultLowBatteryThreshold = 10
    static let batteryLevelScale = 1...100
    static let lowBatteryThresholdRange = 1...99
    static let defaultEarlyBatteryThreshold = 20
    static let earlyBatteryThresholdRange = 2...100

    static func sanitizedLowBatteryThreshold(_ value: Int) -> Int {
        min(lowBatteryThresholdRange.upperBound, max(lowBatteryThresholdRange.lowerBound, value))
    }

    static func sanitizedEarlyBatteryThreshold(_ value: Int) -> Int {
        min(earlyBatteryThresholdRange.upperBound, max(earlyBatteryThresholdRange.lowerBound, value))
    }

    static func earlyBatteryThreshold(_ value: Int, above red: Int) -> Int {
        max(sanitizedEarlyBatteryThreshold(value), sanitizedLowBatteryThreshold(red) + 1)
    }

    static func batteryWarning(percent: Int?, externalConnected: Bool, tint: Bool, threshold: Int,
                               early: Bool = false, earlyThreshold: Int = defaultEarlyBatteryThreshold) -> BatteryWarning {
        guard tint, !externalConnected, let percent else { return .none }
        if percent <= sanitizedLowBatteryThreshold(threshold) { return .low }
        if early, percent <= sanitizedEarlyBatteryThreshold(earlyThreshold) { return .early }
        return .none
    }

    static func batteryWarning(percent: Int?, externalConnected: Bool,
                               in defaults: UserDefaults = .standard) -> BatteryWarning {
        batteryWarning(percent: percent, externalConnected: externalConnected,
                       tint: defaults.bool(forKey: DefaultsKey.notchLowBatteryTint),
                       threshold: defaults.object(forKey: DefaultsKey.notchLowBatteryThreshold) as? Int
                           ?? defaultLowBatteryThreshold,
                       early: defaults.bool(forKey: DefaultsKey.notchLowBatteryEarly),
                       earlyThreshold: defaults.object(forKey: DefaultsKey.notchLowBatteryEarlyThreshold) as? Int
                           ?? defaultEarlyBatteryThreshold)
    }

    static func menuBarBatteryWarning(percent: Int?, externalConnected: Bool,
                                      in defaults: UserDefaults = .standard) -> BatteryWarning {
        guard defaults.object(forKey: DefaultsKey.notchLowBatteryMenuBar) as? Bool ?? true else { return .none }
        return batteryWarning(percent: percent, externalConnected: externalConnected, in: defaults)
    }

    static func hidesUntilHover(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchHideUntilHover) && defaults.bool(forKey: DefaultsKey.notchOpenOnHover)
    }

    static func hiddenShowsActivity(in defaults: UserDefaults = .standard) -> Bool {
        hidesUntilHover(in: defaults) && defaults.bool(forKey: DefaultsKey.notchHiddenShowsActivity)
    }

    static func hidesNoticesUntilHover(in defaults: UserDefaults = .standard) -> Bool {
        hidesUntilHover(in: defaults) && !defaults.bool(forKey: DefaultsKey.notchHiddenShowsActivity)
    }

    static func idleContent(in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = NotchIdleContent(rawValue: defaults.string(forKey: DefaultsKey.notchIdleContent) ?? "") ?? .none
        return canRest(with: choice, in: defaults) ? choice : .none
    }

    static func canRest(with content: NotchIdleContent, in defaults: UserDefaults = .standard) -> Bool {
        switch content {
        case .none: return true
        case .battery: return AppFeature.monitorPower.isAvailable(in: defaults)
        case .music: return modules(in: defaults).contains(.music)
        case .agents: return NotchAgentSupport.sectionShows(in: defaults)
        }
    }

    static func visibleIdleContent(isPlaying: Bool, in defaults: UserDefaults = .standard) -> NotchIdleContent {
        let choice = idleContent(in: defaults)
        if showsMusicActivity(isPlaying: isPlaying, in: defaults),
           choice == .music || (choice == .none && NotchMascotSupport.isEnabled(in: defaults)) {
            return .music
        }
        return choice == .music ? .none : choice
    }

    static func controls(in defaults: UserDefaults = .standard) -> [NotchControlItem] {
        let hidden = Set((defaults.string(forKey: DefaultsKey.notchHiddenControls) ?? NotchControlItem.defaultHidden)
            .split(separator: ",").map(String.init))
        let stored = (defaults.string(forKey: DefaultsKey.notchControlOrder) ?? "")
            .split(separator: ",").compactMap { NotchControlItem(rawValue: String($0)) }
        var seen = Set<NotchControlItem>()
        return (stored + NotchControlItem.allCases).filter {
            seen.insert($0).inserted && !hidden.contains($0.rawValue) && $0.isAvailable(in: defaults)
        }
    }

    static func systemCardCount(hasBattery: Bool, fans: Int = 0, in defaults: UserDefaults = .standard) -> Int {
        [.monitorCPU, .monitorGPU, .monitorMemory, .monitorDisk].filter {
            (feature: AppFeature) in feature.isAvailable(in: defaults)
        }.count + (AppFeature.monitorNetwork.isAvailable(in: defaults) ? 1 : 0)
            + (hasBattery && AppFeature.monitorPower.isAvailable(in: defaults) ? 1 : 0)
            + (AppFeature.monitorPower.isAvailable(in: defaults) ? 1 : 0)
            + (fans > 0 && AppFeature.fanControl.isAvailable(in: defaults) ? 1 : 0)
            + (AppFeature.connectedDevices.isAvailable(in: defaults) ? 1 : 0)
    }

    static func closesOnPointerExit(expanded: Bool, peeking: Bool, openedByHover: Bool) -> Bool {
        peeking || (expanded && openedByHover)
    }

    static func closesOnActivation(openedByHover: Bool, clicked: Bool, pointerInside: Bool) -> Bool {
        !openedByHover || clicked || !pointerInside
    }

    static func routes(_ event: NotchEvent, in defaults: UserDefaults = .standard) -> Bool {
        guard isEnabled(in: defaults), defaults.bool(forKey: event.preferenceKey) else { return false }
        switch event {
        case .timer: return NotchTimerSupport.isEnabled(in: defaults)
        case .watch: return NotchWatchSupport.isEnabled(in: defaults)
        case .accessory: return NotchAccessorySupport.isEnabled(in: defaults)
        case .download: return AppFeature.notchDownloads.isAvailable(in: defaults)
            && modules(in: defaults).contains(.downloads)
        case .agents: return AppFeature.notchAgents.isAvailable(in: defaults)
            && modules(in: defaults).contains(.agents)
        case .systemNotification: return NotchNotificationSupport.isEnabled(in: defaults)
        case .keyboardLight: return AppFeature.brightness.isAvailable(in: defaults)
        case .volume: return AppFeature.mixer.isAvailable(in: defaults)
        case .microphone: return AppFeature.micMute.isAvailable(in: defaults)
        case .brightness:
            return AppFeature.brightness.isAvailable(in: defaults)
                && defaults.bool(forKey: DefaultsKey.brightnessControlEnabled)
        case .battery: return true
        case .clipboard:
            return modules(in: defaults).contains(.clipboard)
                && defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
        case .capture:
            return AppFeature.screenshot.isAvailable(in: defaults)
                && modules(in: defaults).contains(.captures)
        case .track: return modules(in: defaults).contains(.music)
        case .inputSource: return true
        }
    }

    static func routesClipboardWindow(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchClipboardWindow)
            && modules(in: defaults).contains(.clipboard)
    }

    static func showsFiles(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && modules(in: defaults).contains(.files)
    }

    static func routesShelf(in defaults: UserDefaults = .standard) -> Bool {
        showsFiles(in: defaults) && defaults.bool(forKey: DefaultsKey.notchShelf)
    }

    static func revealsShelfDrag(in defaults: UserDefaults = .standard) -> Bool {
        routesShelf(in: defaults) && defaults.bool(forKey: DefaultsKey.notchDragReveal)
    }

    static func routesCaptureControls(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCaptureControls)
            && modules(in: defaults).contains(.captures)
    }

    static func routesQuickPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchQuickPanel)
            && AppFeature.quickLauncher.isAvailable(in: defaults)
            && modules(in: defaults).contains(.tools)
    }

    static func routesAppPanel(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchAppPanel)
    }

    static func routesScratchpad(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (defaults.object(forKey: DefaultsKey.notchScratchpad) as? Bool ?? true)
            && modules(in: defaults).contains(.scratchpad)
    }

    static func shouldReplace(_ current: NotchEvent?, with incoming: NotchEvent, held: Bool = false) -> Bool {
        guard let current else { return true }
        if held { return incoming == current || incoming.priority > current.priority }
        return incoming.priority >= current.priority
    }

    static func volumeLevel(current: Double, direction: Int, fine: Bool) -> Double {
        guard current.isFinite else { return 0 }
        return min(1, max(0, current + Double(direction.signum()) / (fine ? 64 : 16)))
    }

    static let fullVolumeKeyStep = 1.0 / 16
    static let finestVolumeKeyStep = 1.0 / 64

    static let volumeRideWindow: TimeInterval = 2

    enum VolumeChangeOrigin: Equatable {
        case announces
        case rides
    }

    static func volumeChangeOrigin(from previous: Double, to next: Double,
                                   sinceRide: TimeInterval) -> VolumeChangeOrigin {
        guard previous.isFinite, next.isFinite else { return .announces }
        if next <= 0 || next >= 1 { return .announces }
        let delta = abs(next - previous)
        if delta + finestVolumeKeyStep / 2 >= fullVolumeKeyStep { return .announces }
        if delta + 1e-9 < finestVolumeKeyStep { return .rides }
        return sinceRide < volumeRideWindow ? .rides : .announces
    }

    static func screenIndex(preference: NotchDisplay, builtIn: [Bool], notched: [Bool], main: Int,
                            pointer: Int? = nil, hasLid: Bool = true) -> Int? {
        guard !builtIn.isEmpty, builtIn.count == notched.count else { return nil }
        let fallback = builtIn.indices.contains(main) ? main : 0
        switch preference {
        case .main: return fallback
        case .builtIn: return builtIn.firstIndex(of: true) ?? (hasLid ? nil : fallback)
        case .automatic:
            return builtIn.indices.first { builtIn[$0] && notched[$0] }
                ?? notched.firstIndex(of: true) ?? fallback
        case .pointer, .all: return pointer.flatMap { builtIn.indices.contains($0) ? $0 : nil } ?? fallback
        }
    }

    static func reachesDisplayWithoutNotch(preference: NotchDisplay, builtIn: [Bool], notched: [Bool], main: Int,
                                           hasLid: Bool = true) -> Bool {
        guard notched.contains(false) else { return false }
        if preference == .pointer || preference == .all { return true }
        guard let index = screenIndex(preference: preference, builtIn: builtIn, notched: notched, main: main,
                                      hasLid: hasLid) else { return false }
        return !notched[index]
    }
}

struct NotchMenuBarMeasurements {
    private struct Reading {
        let size: CGSize
        let scale: CGFloat
        let height: CGFloat
    }
    private static let range: ClosedRange<CGFloat> = 16...64
    private var readings: [UInt32: Reading] = [:]

    static func showsBar(frame: CGRect, visibleTop: CGFloat) -> Bool {
        let gap = frame.maxY - visibleTop
        return gap.isFinite && range.contains(gap)
    }

    mutating func retainDisplays(_ ids: [UInt32]) {
        readings = readings.filter { ids.contains($0.key) }
    }

    mutating func height(displayID: UInt32, frame: CGRect, visibleTop: CGFloat,
                         scale: CGFloat, statusBarThickness: CGFloat) -> CGFloat {
        let range = Self.range
        let gap = frame.maxY - visibleTop
        let canRemember = displayID != 0 && scale.isFinite && scale > 0
        if let previous = readings[displayID], previous.size != frame.size || previous.scale != scale {
            readings[displayID] = nil
        }
        if Self.showsBar(frame: frame, visibleTop: visibleTop) {
            if canRemember { readings[displayID] = Reading(size: frame.size, scale: scale, height: gap) }
            return gap
        }
        if canRemember, let previous = readings[displayID] { return previous.height }
        return statusBarThickness.isFinite && range.contains(statusBarThickness) ? statusBarThickness : 24
    }
}

struct NotchNoticeWings: Equatable {
    var leading: CGFloat
    var trailing: CGFloat
    static let zero = NotchNoticeWings(leading: 0, trailing: 0)
    var widest: CGFloat { max(leading, trailing) }
}

struct NotchGeometry: Equatable {
    let screen: CGRect
    var surfaceShift: CGFloat = 0
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let isNotched: Bool
    let layout: NotchSize
    let customWidth: CGFloat
    let customHeight: CGFloat
    let menuBarHeight: CGFloat
    let floatingGap: CGFloat?
    let floatingDrop: CGFloat
    let outlineRoom: CGFloat
    private let capsuleWidthFit: CGFloat
    var compactSideRoom: CGFloat?
    var quickAccessBottomInset: CGFloat = 0
    var requiresFullWidthHeader = false
    var pageTop: NotchPageTop = .row
    var startsUnderCamera = false
    var pageContentWidth: CGFloat? = nil
    var sectionsButtonInRow = false
    var pageTrailingControls = 0
    private var allowsActivityFooter = true
    private var minimumCompactWidth: CGFloat = 0
    private var minimumWing: CGFloat = 44

    init(screen: CGRect, safeAreaTop: CGFloat, cameraWidth: CGFloat, layout: NotchSize = .compact,
         menuBarHeight: CGFloat = 24, compactSideRoom: CGFloat? = nil,
         customWidth: Double = NotchSize.defaultWidth, customHeight: Double = NotchSize.defaultHeight,
         cameraFit: NotchCameraFit = .zero, silhouette: NotchSilhouette = .notch, capsuleFit: NotchCapsuleFit = .zero,
         hideMenuBarGap: Bool = false, outline: Bool = false, barEdge: CGFloat = 0) {
        self.screen = screen
        self.layout = layout
        self.customWidth = NotchSize.clamped(customWidth, to: NotchSize.widthRange, fallback: NotchSize.defaultWidth)
        self.customHeight = NotchSize.clamped(customHeight, to: NotchSize.heightRange, fallback: NotchSize.defaultHeight)
        let barHeight = menuBarHeight.isFinite ? min(64, max(16, menuBarHeight)) : 24
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && cameraWidth.isFinite && cameraWidth > 0
        let fit = isNotched ? cameraFit : .zero
        let gap: CGFloat? = !isNotched && silhouette == .capsule ? NotchLayout.capsuleGap(barHeight: barHeight) : nil
        floatingGap = gap
        let capsuleFit = gap == nil ? NotchCapsuleFit.zero : capsuleFit
        floatingDrop = capsuleFit.drop
        capsuleWidthFit = capsuleFit.width
        let edge = barEdge.isFinite ? min(max(0, barEdge), 1) : 0
        let fullStrip = gap.map { max(barHeight + capsuleFit.height, $0 * 2 + 12) }
        let stripHeight = gap.map { max(barHeight - edge + capsuleFit.height, $0 * 2 + 12) } ?? barHeight
        let profileHeight = gap.flatMap { gap in fullStrip.map { $0 - (gap - NotchLayout.capsuleMargin) * 2 } }
            ?? barHeight
        let simulated = 180 * profileHeight / 32
        let room = isNotched && outline ? NotchLayout.outlineWidth : 0
        outlineRoom = room
        self.cameraWidth = min(isNotched ? max(0, cameraWidth + fit.width + room * 2)
                               : gap == nil ? simulated : (simulated + capsuleFit.width).rounded(),
                               screen.width * 0.7)
        if isNotched {
            let baseHeight = hideMenuBarGap ? max(safeAreaTop, barHeight) : safeAreaTop
            cameraHeight = min(max(0, baseHeight + fit.height + room), 64)
        } else {
            cameraHeight = stripHeight
        }
        self.menuBarHeight = max(cameraHeight, barHeight)
        self.compactSideRoom = compactSideRoom
    }

    var floats: Bool { floatingGap != nil }

    func hasSameMenuBar(as other: NotchGeometry) -> Bool {
        screen == other.screen && cameraWidth == other.cameraWidth
            && menuBarHeight == other.menuBarHeight && isNotched == other.isNotched
    }

    var safeContentTop: CGFloat { floats ? NotchLayout.bottomInset : cameraHeight + 10 }
    var headerCameraGap: CGFloat {
        isNotched && !requiresFullWidthHeader && contentWidth >= cameraWidth + pageBandSide * 2 ? cameraWidth : 0
    }
    var pageBandSide: CGFloat { pageTop == .wrapsCamera ? NotchLayout.musicBandSide : 100 }
    var rowShowsSectionsButton: Bool { sectionsButtonInRow && pageTop != .wrapsCamera }
    var sectionsButtonEndsRow: Bool { sectionsButtonInRow && pageTop == .wrapsCamera }
    var trailingSectionsRoom: CGFloat { CGFloat(pageTrailingControls) * NotchBand.sectionsButtonRoom + 28 }

    func page(_ module: NotchModule, controls: [NotchControlItem], sectionsButton: Bool) -> NotchGeometry {
        var result = self
        result.pageTop = module.pageTop
        result.startsUnderCamera = module == .scratchpad
        result.pageContentWidth = NotchLayout.naturalContentWidth(module, controls: controls, within: contentWidth)
        result.sectionsButtonInRow = sectionsButton
        return result
    }
    var headerTopInset: CGFloat {
        if isNotched, !floats { return headerCameraGap > 0 ? 0 : safeContentTop }
        guard headerRowHeight > 0 else { return NotchLayout.bottomInset }
        return floats ? NotchLayout.bottomInset - (NotchLayout.headerHeight - 28) / 2 : 0
    }
    var headerRowHeight: CGFloat {
        if headerCameraGap > 0 { return max(cameraHeight, NotchLayout.headerHeight) }
        return pageTop == .row || rowShowsSectionsButton ? NotchLayout.headerHeight : 0
    }
    var pageTopInset: CGFloat {
        guard pageTop != .wrapsCamera, headerRowHeight > 0 else { return headerTopInset }
        if startsUnderCamera, headerCameraGap > 0 { return headerTopInset + cameraHeight + 2 }
        return headerTopInset + headerRowHeight + NotchLayout.spacing
    }
    var headerChromeHeight: CGFloat { pageTopInset - headerTopInset + NotchLayout.bottomInset }
    var quickAccessCenterY: CGFloat {
        max(headerTopInset + headerRowHeight / 2,
            menuBarHeight + 6 + NotchQuickAccessLayout.width / 2)
    }
    var stripHeight: CGFloat { cameraHeight }
    var stripBodyHeight: CGFloat { max(0, stripHeight - (floatingGap ?? 0) * 2) }
    func activationArea(in size: CGSize, hasHeader: Bool, compactActivity: Bool, expandedHeader: Bool = false) -> CGRect {
        if expandedHeader, headerCameraGap > 0 || !isNotched || floats {
            return CGRect(x: (size.width - headerCameraGap) / 2, y: 0,
                          width: headerCameraGap, height: min(cameraHeight, size.height))
        }
        let width = compactActivity && !floats ? cameraWidth : size.width
        let height = hasHeader ? min(safeContentTop, size.height)
            : compactActivity && compactActivityUsesFooter ? compactActivityTopPadding : size.height
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
    }

    var restingWingWidth: CGFloat {
        let available = min(44, max(0, compactSideRoom ?? 0)).rounded(.down)
        return available >= 44 ? available : 0
    }
    var collapsed: CGSize {
        CGSize(width: min(screen.width - 24, cameraWidth + restingWingWidth * 2), height: stripHeight)
    }
    func restingSize(showsContent: Bool) -> CGSize {
        if showsContent { return collapsed }
        guard floats else { return CGSize(width: cameraWidth, height: cameraHeight) }
        let shoulders = NotchLayout.shoulder(height: stripHeight) * 2
        let capsule = max(NotchLayout.capsuleRestingAspect * stripBodyHeight + capsuleWidthFit, stripBodyHeight * 2)
        return CGSize(width: min(cameraWidth, (capsule + shoulders).rounded()), height: cameraHeight)
    }
    var bareCutout: CGSize {
        let resting = restingSize(showsContent: false)
        return CGSize(width: max(0, resting.width - outlineRoom * 2), height: max(0, resting.height - outlineRoom))
    }
    var compactMusicGeometry: NotchGeometry {
        var compact = self
        compact.allowsActivityFooter = false
        let room = compactSideRoom ?? 0
        let wing = isNotched ? compact.compactMusicContentWing : 44
        compact.compactSideRoom = room.isFinite && room >= wing ? min(isNotched ? wing : 56, room) : 0
        compact.minimumWing = wing
        return compact
    }
    var lockScreenMusicGeometry: NotchGeometry {
        var unobstructed = self
        unobstructed.compactSideRoom = screen.width
        return unobstructed.compactMusicGeometry
    }
    var compactMusicArtworkSide: CGFloat {
        max(0, min(26, compactActivityContentHeight - NotchLayout.compactEdgeGap * 2))
    }
    private var compactMusicArtworkFills: Bool {
        compactActivityContentHeight - compactMusicArtworkSide <= NotchLayout.compactEdgeGap * 4
    }
    var compactMusicArtworkRadius: CGFloat {
        let side = compactMusicArtworkSide
        guard compactMusicArtworkFills else { return side * 0.28 }
        let concentric = NotchLayout.surfaceRadius(height: compactActivitySize.height)
            - (compactActivityContentHeight - side) / 2
        return min(side / 2, max(side * 0.2, concentric))
    }
    var compactMusicArtworkInset: CGFloat {
        let gap = compactMusicArtworkFills ? (compactActivityContentHeight - compactMusicArtworkSide) / 2
            : NotchLayout.compactEdgeGap
        return compactActivityEdgeInset(boxHeight: compactMusicArtworkSide, radius: compactMusicArtworkRadius, gap: gap)
    }
    var compactMusicBarHeight: CGFloat {
        min(16, max(6, compactActivityContentHeight - NotchLayout.compactEdgeGap * 2))
    }
    var compactMusicBarsInset: CGFloat {
        compactActivityEdgeInset(boxHeight: compactMusicBarHeight, radius: NotchLayout.compactMusicBarWidth / 2)
    }
    private var compactMusicContentWing: CGFloat {
        max(compactMusicArtworkInset + compactMusicArtworkSide,
            compactMusicBarsInset + NotchLayout.compactMusicBarsWidth).rounded(.up)
    }
    var musicCameraGap: CGFloat { cameraWidth }
    var compactMusicLabelInset: CGFloat {
        let height = compactActivityContentHeight
        let shoulder = NotchLayout.shoulder(height: height)
        let bottom = NotchLayout.surfaceRadius(height: height)
        return max(4, shoulder + bottom + 4 - compactActivityWingWidth)
    }
    func compactTimerGeometry(showsDownloads: Bool,
                              wing fitted: CGFloat = NotchTimerSupport.stripWingRange.upperBound) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let range = NotchTimerSupport.stripWingRange
        let wing = showsDownloads ? 80 : min(range.upperBound, max(range.lowerBound, fitted.isFinite ? fitted.rounded(.up) : 0))
        compact.compactSideRoom = room.isFinite && room >= 64 ? min(wing, room) : 0
        compact.minimumCompactWidth = cameraWidth + wing * 2
        compact.allowsActivityFooter = false
        return compact
    }
    func compactDownloadGeometry(wing: CGFloat = 56) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        compact.compactSideRoom = room.isFinite && room >= 44 ? min(wing, room) : 0
        compact.minimumCompactWidth = cameraWidth + wing * 2
        return compact
    }
    static let calendarWingRange: ClosedRange<CGFloat> = 72...120
    var compactCalendarGeometry: NotchGeometry { compactCalendarGeometry(wing: Self.calendarWingRange.upperBound) }
    func compactCalendarGeometry(wing: CGFloat, paired: Bool = false) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let range = Self.calendarWingRange
        let lowest = paired ? NotchTimerSupport.stripWingRange.lowerBound : range.lowerBound
        let fitted = min(range.upperBound, max(lowest, wing.isFinite ? wing.rounded(.up) : 0))
        let readable = min(fitted, range.lowerBound)
        compact.compactSideRoom = room.isFinite && room >= readable ? min(fitted, room) : 0
        compact.minimumCompactWidth = cameraWidth + fitted * 2
        compact.minimumWing = readable
        return compact
    }
    func compactAgentGeometry(wing: CGFloat) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let fitted = min(NotchAgentSupport.stripWingRange.upperBound,
                         max(NotchAgentSupport.stripWingRange.lowerBound, wing.isFinite ? wing.rounded(.up) : 0))
        compact.compactSideRoom = room.isFinite && room >= NotchAgentSupport.stripWingRange.lowerBound ? min(fitted, room) : 0
        compact.minimumCompactWidth = cameraWidth + fitted * 2
        compact.allowsActivityFooter = false
        return compact
    }
    func compactWatchGeometry(wing: CGFloat) -> NotchGeometry {
        var compact = self
        let room = compactSideRoom ?? 0
        let range = NotchWatchSupport.stripWingRange
        let fitted = min(range.upperBound, max(range.lowerBound, wing.isFinite ? wing.rounded(.up) : 0))
        compact.compactSideRoom = room.isFinite && room >= range.lowerBound ? min(fitted, room) : 0
        compact.minimumCompactWidth = cameraWidth + fitted * 2
        compact.allowsActivityFooter = false
        return compact
    }
    var musicStrip: CGSize {
        let preferred = min(max(layout == .spacious ? 520 : 440, cameraWidth + 88, minimumCompactWidth), screen.width - 24)
        let measuredRoom = compactSideRoom ?? 0
        let room = measuredRoom.isFinite ? max(0, measuredRoom).rounded(.down) : 0
        let wings = min(max(0, preferred - cameraWidth), room * 2)
        return CGSize(width: cameraWidth + (wings >= minimumWing * 2 ? wings : 0), height: stripHeight)
    }
    var musicWingWidth: CGFloat { max(0, (musicStrip.width - musicCameraGap) / 2) }

    var compactActivityUsesFooter: Bool { isNotched && allowsActivityFooter && musicWingWidth < 44 }
    var compactActivityContentHeight: CGFloat { compactActivityUsesFooter ? 32 : stripHeight }
    var compactActivityTopPadding: CGFloat { compactActivityUsesFooter ? stripHeight : 0 }
    var compactActivityHorizontalPadding: CGFloat { compactActivityUsesFooter ? 4 : 0 }
    var compactActivityCameraGap: CGFloat { compactActivityUsesFooter ? 0 : musicCameraGap }
    var compactActivitySize: CGSize {
        compactActivityUsesFooter
            ? CGSize(width: cameraWidth, height: compactActivityTopPadding + compactActivityContentHeight)
            : musicStrip
    }
    var compactActivityWingWidth: CGFloat {
        max(0, (compactActivitySize.width - compactActivityCameraGap - compactActivityHorizontalPadding * 2) / 2)
    }
    var compactActivityShoulder: CGFloat {
        NotchLayout.shoulder(height: compactActivitySize.height)
    }
    func compactActivityEdgeInset(boxHeight: CGFloat, radius: CGFloat,
                                  gap: CGFloat = NotchLayout.compactEdgeGap) -> CGFloat {
        let shoulder = compactActivityShoulder
        let corner = min(NotchLayout.surfaceRadius(height: compactActivitySize.height),
                         (compactActivitySize.width - shoulder * 2) / 2)
        let flat = shoulder + gap - compactActivityHorizontalPadding
        let below = (compactActivityContentHeight - boxHeight) / 2
        let reach = corner - radius - gap
        let drop = corner - radius - below
        guard reach > 0, drop > 0 else { return max(0, flat) }
        let span = reach > drop ? (reach * reach - drop * drop).squareRoot() : 0
        return max(0, flat, shoulder + corner - radius - span - compactActivityHorizontalPadding)
    }
    var notice: CGSize {
        noticeSize(wingWidth: 80)
    }
    var noticeCameraGap: CGFloat { cameraWidth }

    func noticeSize(wingWidth: CGFloat) -> CGSize {
        CGSize(width: min(screen.width - 24, noticeCameraGap + wingWidth * 2), height: stripHeight)
    }

    func noticeWingWidth(preferred: CGFloat) -> CGFloat {
        max(0, (noticeSize(wingWidth: preferred).width - noticeCameraGap) / 2)
    }

    func noticeWings(_ preferred: NotchNoticeWings) -> NotchNoticeWings {
        NotchNoticeWings(leading: noticeWingWidth(preferred: preferred.leading),
                         trailing: noticeWingWidth(preferred: preferred.trailing))
    }

    func noticeSize(wings preferred: NotchNoticeWings) -> CGSize {
        let wings = noticeWings(preferred)
        return CGSize(width: noticeCameraGap + wings.leading + wings.trailing, height: stripHeight)
    }

    func noticeShift(_ preferred: NotchNoticeWings) -> CGFloat {
        let wings = noticeWings(preferred)
        return (wings.trailing - wings.leading) / 2
    }
    var notificationPreviewWidth: CGFloat { min(max(400, cameraWidth + 200), expandedWidth) }
    var notificationPreviewContentWidth: CGFloat {
        max(0, notificationPreviewWidth - NotchLayout.horizontalInset * 2)
    }
    func notificationPreviewSize(contentHeight: CGFloat) -> CGSize {
        let height = safeContentTop + max(0, contentHeight) + NotchLayout.bottomInset
        return CGSize(width: notificationPreviewWidth, height: min(height, screen.height - 48))
    }
    var peek: CGSize {
        CGSize(width: min(screen.width - 24, max(cameraWidth + 110, 340)), height: safeContentTop + 52)
    }
    var expanded: CGSize { expandedSize(module: .controls) }
    var expandedWidth: CGFloat {
        let chosen = NotchLayout.preferredWidth(layout, custom: customWidth)
        var wing = pageBandSide + (rowShowsSectionsButton ? NotchBand.sectionsButtonRoom : 0)
        let ending = max(wing, trailingSectionsRoom + NotchBand.cameraClearance)
        if sectionsButtonEndsRow, cameraWidth + ending * 2 + NotchLayout.horizontalInset * 2 <= chosen { wing = ending }
        let preferred = layout == .custom ? chosen : pageContentWidth.map { natural in
            min(chosen, max(natural, isNotched ? cameraWidth + wing * 2 : 0) + NotchLayout.horizontalInset * 2)
        } ?? chosen
        return min(max(preferred, cameraWidth + 36), screen.width - 24 - NotchQuickAccessLayout.gutter * 2)
    }
    var contentWidth: CGFloat { max(0, expandedWidth - NotchLayout.horizontalInset * 2) }
    var contentBudget: CGFloat {
        switch layout {
        case .compact: return NotchLayout.compactContentHeight
        case .spacious: return NotchLayout.spaciousContentHeight
        case .custom: return max(0, customHeight - headerTopInset - headerChromeHeight)
        }
    }
    var pageBudget: CGFloat { layout == .custom ? contentBudget : max(contentBudget, NotchLayout.pageContentHeight) }
    var musicExtrasHeight: CGFloat { layout == .custom ? min(216, contentBudget) : 216 }
    var musicBandHeight: CGFloat { headerCameraGap > 0 ? headerRowHeight : 0 }
    var musicPlayerHeight: CGFloat { NotchLayout.musicPlayerHeight(band: musicBandHeight) }

    func systemRows(cards: Int) -> Int {
        NotchLayout.systemRowRanges(count: cards, width: contentWidth - NotchLayout.systemHoverInset(width: contentWidth) * 2).count
    }

    func toolRows(count: Int) -> Int {
        NotchLayout.railRows(count: count,
                             perRow: NotchLayout.railCapacity(width: contentWidth, itemWidth: NotchLayout.toolWidth, spacing: NotchLayout.toolSpacing),
                             rowHeight: NotchLayout.toolHeight, spacing: NotchLayout.toolSpacing, height: contentBudget)
    }

    func toolFlow(count: Int) -> QuickToolsSupport.GridFlow {
        let rows = toolRows(count: count)
        let columns = NotchLayout.railColumns(count: count, rows: rows)
        return NotchLayout.railGap(columns: columns, itemWidth: NotchLayout.toolWidth, spacing: NotchLayout.toolSpacing,
                                   least: NotchLayout.toolLeastSpacing, width: contentWidth) != nil
            ? .rows(columns: columns) : .columns(rows: rows)
    }

    func expandedSize(module: NotchModule, detail: Bool = false, panel: Bool = false,
                      detailHeight: CGFloat? = nil, shortcutCount: Int = 4,
                      sliderCount: Int = 2, controlsHaveMusic: Bool = true, musicHasContent: Bool = true,
                      musicShowsVolume: Bool = false,
                      musicExtraHeight: CGFloat = 0,
                      fileMediaHeight: CGFloat? = nil, systemCards: Int = 6, toolCount: Int? = 8,
                      capturePreviewHeight: CGFloat? = nil,
                      timerHasSession: Bool = false, timerMode: NotchTimerMode = .timer,
                      agentsHeight: CGFloat? = nil) -> CGSize {
        let budget = contentBudget
        let showsCapturePreview = module == .captures && !detail && capturePreviewHeight != nil
        let showsFileMedia = module == .files && !detail && fileMediaHeight != nil
        let contentHeight: CGFloat
        if detail, !panel, let detailHeight {
            contentHeight = min(pageBudget, max(0, detailHeight) + 4)
        } else if detail || panel {
            contentHeight = pageBudget
        } else if showsFileMedia {
            contentHeight = max(0, fileMediaHeight ?? 0)
        } else if showsCapturePreview {
            contentHeight = max(0, capturePreviewHeight ?? 0) + 4
        } else {
            switch module {
            case .controls:
                let levels = max(0, sliderCount)
                let band = NotchBand(geometry: self, contentWidth: contentWidth)
                let levelRow = NotchLayout.bandLevelCount(levels, band: band) < levels
                let room = budget + (levelRow && layout != .custom ? NotchLayout.levelRowHeight + NotchLayout.rowSpacing : 0)
                let home = NotchLayout.controls(hasCards: controlsHaveMusic, levelRow: levelRow,
                                                shortcutCount: max(0, shortcutCount), width: contentWidth, height: room)
                let empty = !controlsHaveMusic && sliderCount <= 0 && shortcutCount <= 0
                contentHeight = min(room, empty ? NotchLayout.emptyHeight : home.height)
            case .music:
                let player = NotchLayout.musicPlayerHeight(band: musicBandHeight, playing: musicHasContent)
                let volume = musicShowsVolume ? NotchLayout.rowSpacing + NotchLayout.levelRowHeight : 0
                let room = budget + (layout == .custom ? 0 : volume)
                contentHeight = min(room, player + volume) + max(0, musicExtraHeight)
            case .system:
                let cards = max(0, systemCards)
                contentHeight = min(budget, cards == 0 ? NotchLayout.emptyHeight
                    : NotchLayout.railHeight(rows: systemRows(cards: cards), rowHeight: NotchLayout.systemCardHeight, spacing: NotchLayout.rowSpacing)
                        + NotchLayout.systemHoverInset(width: contentWidth) * 2)
            case .tools:
                guard let toolCount else { contentHeight = pageBudget; break }
                contentHeight = min(budget, toolCount == 0 ? NotchLayout.emptyHeight
                    : NotchLayout.railHeight(rows: toolRows(count: toolCount), rowHeight: NotchLayout.toolHeight, spacing: NotchLayout.toolSpacing))
            case .timer:
                contentHeight = min(budget, NotchLayout.timer(mode: timerMode, hasSession: timerHasSession, height: budget))
            case .agents:
                contentHeight = min(budget, agentsHeight.map { $0 > 0 ? $0 : NotchLayout.emptyHeight } ?? budget)
            case .scratchpad:
                let usualTop = headerTopInset + headerRowHeight + NotchLayout.spacing
                contentHeight = budget + (startsUnderCamera ? max(0, usualTop - pageTopInset) : 0)
            case .mixer, .calendar, .clipboard, .captures, .files, .notifications, .downloads, .camera, .watch:
                contentHeight = budget
            }
        }
        var preferredHeight = headerTopInset + headerChromeHeight + contentHeight
        if layout == .custom { preferredHeight = min(preferredHeight, customHeight) }
        return CGSize(width: expandedWidth,
                      height: min(preferredHeight, screen.height - 48 - quickAccessBottomInset))
    }

    var sectionColumns: Int {
        NotchLayout.railCapacity(width: contentWidth - NotchLayout.sectionIndicatorWidth, itemWidth: NotchLayout.sectionTileWidth,
                                 spacing: NotchLayout.sectionSpacing)
    }

    func sectionRows(count: Int) -> Int {
        NotchLayout.railRows(count: count,
                             perRow: sectionColumns,
                             rowHeight: NotchLayout.sectionTileHeight, spacing: NotchLayout.sectionSpacing, height: pageBudget)
    }

    func sectionPickerSize(count: Int) -> CGSize {
        let content = min(pageBudget, count == 0 ? NotchLayout.emptyHeight
            : NotchLayout.railHeight(rows: sectionRows(count: count), rowHeight: NotchLayout.sectionTileHeight, spacing: NotchLayout.sectionSpacing))
        let desiredHeight = headerTopInset + headerChromeHeight + content
        return CGSize(width: expandedWidth, height: min(desiredHeight, screen.height - 48 - quickAccessBottomInset))
    }

    func contentSize(for size: CGSize) -> CGSize {
        CGSize(width: max(0, size.width - NotchLayout.horizontalInset * 2),
               height: max(0, size.height - headerTopInset - headerChromeHeight))
    }
    var appPanelSize: CGSize { contentSize(for: expandedSize(module: .tools, panel: true)) }
    func frame(for size: CGSize) -> CGRect {
        CGRect(x: screen.midX + surfaceShift - size.width / 2,
               y: screen.maxY - floatingDrop - size.height,
               width: size.width, height: size.height)
    }

    func contains(_ point: CGPoint, in size: CGSize) -> Bool {
        let frame = self.frame(for: size)
        return CGRect(origin: .zero, size: size).contains(
            CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y))
    }
}

struct NotchSessionState {
    var locked = false
    var sleeping = false
    var displaysSleeping = false
    var onConsole = true
    var screenSaverRunning = false
    var canRunTimer: Bool { !locked && !sleeping && onConsole }
    var canPresent: Bool { canRunTimer && !displaysSleeping }
    var showsLockScreen: Bool { locked && !sleeping && onConsole && !displaysSleeping && !screenSaverRunning }
    var hearsLockChange: Bool { !sleeping && onConsole && !displaysSleeping && !screenSaverRunning }
}

enum NotchMotion {
    static let departureHidden: TimeInterval = 0.1

    struct Spring: Equatable {
        var duration: TimeInterval
        var bounce: Double

        func progress(at time: TimeInterval) -> Double {
            guard time > 0 else { return 0 }
            let natural = 2 * Double.pi / duration
            let damping = 1 - bounce
            if damping >= 1 { return 1 - exp(-natural * time) * (1 + natural * time) }
            let damped = natural * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * natural * time)
                * (cos(damped * time) + damping * natural / damped * sin(damped * time))
        }

        var overshoot: Double {
            guard bounce > 0 else { return 0 }
            let damping = 1 - bounce
            return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
        }

        func limited(travel: CGFloat, limit: CGFloat) -> Spring {
            guard bounce > 0, travel > 0, Double(travel) * overshoot > Double(limit) else { return self }
            let share = log(Double(max(limit, 0.01) / travel))
            return Spring(duration: duration, bounce: 1 + share / (Double.pi * Double.pi + share * share).squareRoot())
        }
    }

    static let growingWidth = Spring(duration: 0.3, bounce: 0.15)
    static let growingHeight = growingWidth
    static let shrinkingWidth = Spring(duration: 0.26, bounce: 0)
    static let shrinkingHeight = shrinkingWidth
    static let steadyWidth = Spring(duration: 0.5, bounce: 0)
    static let overshootLimit: CGFloat = 12
    static let settledDistance: CGFloat = 0.5

    static func spring(from: CGFloat, to: CGFloat, width: Bool, steady: Bool = false) -> Spring {
        if steady && width { return steadyWidth }
        let spring = to > from ? (width ? growingWidth : growingHeight) : (width ? shrinkingWidth : shrinkingHeight)
        return spring
    }

    static func sideSpring(from: CGSize, to: CGSize) -> Spring {
        from.width != to.width ? spring(from: from.width, to: to.width, width: true)
            : spring(from: from.height, to: to.height, width: false)
    }

    static func duration(from: CGSize, to: CGSize) -> TimeInterval {
        var durations: [TimeInterval] = []
        if from.width != to.width { durations.append(spring(from: from.width, to: to.width, width: true).duration) }
        if from.height != to.height { durations.append(spring(from: from.height, to: to.height, width: false).duration) }
        return durations.max() ?? growingWidth.duration
    }

    static func size(at time: TimeInterval, from: CGSize, to: CGSize, steady: Bool = false) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            guard start != end else { return end }
            let spring = spring(from: start, to: end, width: width, steady: steady)
            return max(0, start + (end - start) * CGFloat(spring.progress(at: time)))
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }

    static func arrivalTime(from: CGSize, to: CGSize) -> TimeInterval {
        let sides = [(from.width, to.width, true), (from.height, to.height, false)].filter { $0.0 != $0.1 }
        let step = 1.0 / 240
        var time = step
        while time < 2, !sides.allSatisfy({ spring(from: $0.0, to: $0.1, width: $0.2).progress(at: time) >= 0.99 }) {
            time += step
        }
        return sides.isEmpty ? 0 : time
    }

    static func settlingTime(from: CGSize, to: CGSize, steady: Bool = false, offset startOffset: CGFloat = 0) -> TimeInterval {
        let step = 1.0 / 240
        var settled = step
        var time = step
        while time < 2 {
            let size = size(at: time, from: from, to: to, steady: steady)
            let offset = offset(at: time, from: from, to: to, start: startOffset, steady: steady)
            if abs(size.width - to.width) > settledDistance || abs(size.height - to.height) > settledDistance
                || abs(offset) > settledDistance {
                settled = time + step
            }
            time += step
        }
        return settled
    }

    static func offset(at time: TimeInterval, from: CGSize, to: CGSize, start: CGFloat, steady: Bool = false) -> CGFloat {
        guard start != 0 else { return 0 }
        let spring = from.width == to.width ? steadyWidth : spring(from: from.width, to: to.width, width: true, steady: steady)
        return start * CGFloat(1 - spring.progress(at: time))
    }

    static func frames(from: CGSize, to: CGSize,
                       steady: Bool = false, offset: CGFloat = 0) -> (sizes: [CGSize], keyTimes: [Double], duration: TimeInterval) {
        let duration = settlingTime(from: from, to: to, steady: steady, offset: offset)
        let count = max(1, Int((duration * 120).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        let sizes = keyTimes.map { $0 == 1 ? to : size(at: duration * $0, from: from, to: to, steady: steady) }
        return (sizes, keyTimes, duration)
    }

    static func reservation(_ reserved: CGSize, centring size: CGSize) -> CGSize {
        CGSize(width: size.width + 2 * max(0, (reserved.width - size.width) / 2).rounded(.up),
               height: max(reserved.height, size.height))
    }

    static func envelope(from: CGSize, to: CGSize) -> CGSize {
        func side(_ start: CGFloat, _ end: CGFloat, width: Bool) -> CGFloat {
            let swing = end > start ? spring(from: start, to: end, width: width).overshoot : 0
            guard swing > 0 else { return max(start, end) }
            return (end + (end - start) * CGFloat(swing)).rounded(.up)
        }
        return CGSize(width: side(from.width, to.width, width: true), height: side(from.height, to.height, width: false))
    }
}

struct NotchMotionTimeline: Equatable {
    struct Leg: Equatable {
        var begin: CFTimeInterval
        var from: CGFloat
        var to: CGFloat
    }

    private(set) var width: [Leg]
    private(set) var height: [Leg]
    private(set) var begin: CFTimeInterval
    private(set) var start: CGSize
    let steady: Bool
    let offset: CGFloat

    init(from: CGSize, to: CGSize, begin: CFTimeInterval, steady: Bool = false, offset: CGFloat = 0) {
        width = [Leg(begin: begin, from: from.width, to: to.width)]
        height = [Leg(begin: begin, from: from.height, to: to.height)]
        self.begin = begin
        start = from
        self.steady = steady
        self.offset = offset
    }

    var target: CGSize { CGSize(width: width.last?.to ?? start.width, height: height.last?.to ?? start.height) }

    func size(at time: CFTimeInterval) -> CGSize {
        CGSize(width: value(of: width, at: time, width: true), height: value(of: height, at: time, width: false))
    }

    func offset(at time: CFTimeInterval) -> CGFloat {
        NotchMotion.offset(at: time - begin, from: start, to: target, start: offset, steady: steady)
    }

    func rebased(to time: CFTimeInterval) -> NotchMotionTimeline {
        func moved(_ legs: [Leg]) -> [Leg] {
            legs.map { $0.begin == begin ? Leg(begin: time, from: $0.from, to: $0.to) : $0 }
        }
        var rebased = self
        rebased.width = moved(width)
        rebased.height = moved(height)
        rebased.begin = time
        return rebased
    }

    func continued(to size: CGSize, at time: CFTimeInterval) -> NotchMotionTimeline? {
        guard !steady, offset == 0, let width = continued(width, to: size.width, at: time),
              let height = continued(height, to: size.height, at: time) else { return nil }
        var next = self
        next.width = width
        next.height = height
        next.begin = time
        next.start = self.size(at: time)
        return next
    }

    func frames() -> (sizes: [CGSize], keyTimes: [Double], duration: TimeInterval) {
        let target = target
        let step = 1.0 / 240
        var duration = step
        var time = step
        while time < 2 {
            let size = size(at: begin + time)
            if abs(size.width - target.width) > NotchMotion.settledDistance
                || abs(size.height - target.height) > NotchMotion.settledDistance {
                duration = time + step
            }
            time += step
        }
        let count = max(1, Int((duration * 120).rounded(.up)))
        let keyTimes = (0...count).map { Double($0) / Double(count) }
        let sizes = keyTimes.map { $0 == 1 ? target : size(at: begin + duration * $0) }
        return (sizes, keyTimes, duration)
    }

    private func value(of legs: [Leg], at time: CFTimeInterval, width: Bool) -> CGFloat {
        guard let first = legs.first, let last = legs.last else { return 0 }
        let value = legs.reduce(first.from) { value, leg in
            guard leg.from != leg.to else { return value }
            let spring = NotchMotion.spring(from: leg.from, to: leg.to, width: width, steady: steady)
            return value + (leg.to - leg.from) * CGFloat(spring.progress(at: time - leg.begin))
        }
        return max(0, min(value, max(first.from, last.to) + NotchMotion.overshootLimit))
    }

    private func continued(_ legs: [Leg], to end: CGFloat, at time: CFTimeInterval) -> [Leg]? {
        guard let last = legs.last, end != last.to else { return legs }
        let heading = legs.first { $0.from != $0.to }.map { $0.to - $0.from } ?? 0
        guard heading == 0 || (end > last.to) == (heading > 0) else { return nil }
        return legs + [Leg(begin: time, from: last.to, to: end)]
    }
}

struct NotchGlassFade: Equatable {
    var solidHeight: CGFloat = 0
    var range: CGFloat = 1

    static let open = NotchGlassFade()
    static let stretch: CGFloat = 48

    func openness(atHeight height: CGFloat) -> CGFloat {
        guard height.isFinite, range > 0 else { return 1 }
        return min(1, max(0, (height - solidHeight) / range))
    }

    static func plan(from start: CGFloat, to end: CGFloat, endsInGlass: Bool, current: CGFloat) -> NotchGlassFade {
        guard start.isFinite, end.isFinite else { return .open }
        let current = min(1, max(0, current.isFinite ? current : 1))
        let travel = abs(end - start)
        if endsInGlass {
            guard end > start, current < 1 else { return .open }
            if current == 0 {
                let range = min(stretch, travel)
                return NotchGlassFade(solidHeight: end - range, range: max(1, range))
            }
            let range = travel / (1 - current)
            return NotchGlassFade(solidHeight: start - current * range, range: max(1, range))
        }
        if current >= 1 { return .open }
        return NotchGlassFade(solidHeight: max(start, end), range: 1)
    }
}

enum NotchMenuBarLayout {
    static func measuredSideRoom(screen: CGRect, cameraWidth: CGFloat, barHeight: CGFloat,
                                 menuItems: [CGRect], statusItems: [CGRect]) -> CGFloat? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
        guard menuItems.contains(where: { $0.intersects(bar) }) else { return nil }
        return sideRoom(screen: screen, cameraWidth: cameraWidth, barHeight: barHeight,
                        occupied: menuItems + statusItems)
    }

    static func sideRoom(screen: CGRect, cameraWidth: CGFloat, barHeight: CGFloat,
                         occupied: [CGRect]) -> CGFloat? {
        let bar = CGRect(x: screen.minX, y: screen.maxY - barHeight, width: screen.width, height: barHeight)
        let camera = CGRect(x: screen.midX - cameraWidth / 2, y: bar.minY,
                            width: cameraWidth, height: barHeight)
        var left = screen.minX + 8
        var right = screen.maxX - 8
        for rect in occupied where rect.intersects(bar) {
            guard rect.minX.isFinite, rect.maxX.isFinite, rect.width > 0 else { return nil }
            if rect.intersects(camera) { return nil }
            if rect.maxX <= camera.minX { left = max(left, rect.maxX + 8) }
            if rect.minX >= camera.maxX { right = min(right, rect.minX - 8) }
        }
        return max(0, min(camera.minX - left, right - camera.maxX))
    }
}

enum NotchTranslucentTint {
    static let rampLength: CGFloat = 36

    static func opacity(atDepth depth: CGFloat, stripHeight: CGFloat,
                        openness: Double, increasedContrast: Bool) -> Double {
        guard depth > stripHeight else { return 1 }
        let ramp = Double(min(1, (depth - stripHeight) / rampLength))
        let eased = ramp * ramp * (3 - 2 * ramp)
        return 1 - min(1, max(0, openness)) * (increasedContrast ? 0.3 : 0.62) * eased
    }

    static func stops(height: CGFloat, stripHeight: CGFloat, openness: Double,
                      increasedContrast: Bool) -> [(location: Double, opacity: Double)] {
        guard height > 0 else { return [(0, 1), (1, 1)] }
        let depths = [0, stripHeight] + (1...8).map { stripHeight + rampLength * CGFloat($0) / 8 } + [height]
        return depths.filter { $0 >= 0 && $0 <= height }.map {
            (Double($0 / height), opacity(atDepth: $0, stripHeight: stripHeight,
                                          openness: openness, increasedContrast: increasedContrast))
        }
    }
}
