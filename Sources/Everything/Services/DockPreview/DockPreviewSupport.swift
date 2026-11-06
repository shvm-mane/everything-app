// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum DockPreviewFrameSupport {
    static func wasConstrained(_ current: CGRect, original: CGRect, visibleFrame: CGRect) -> Bool {
        guard !original.isEmpty, !visibleFrame.isEmpty,
              !visibleFrame.contains(original), !current.isEmpty else { return false }
        let size = CGSize(width: min(original.width, visibleFrame.width),
                          height: min(original.height, visibleFrame.height))
        let moved = CGRect(x: min(max(original.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
                           y: min(max(original.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
                           width: size.width, height: size.height)
        return [original.intersection(visibleFrame), moved].contains { expected in
            guard !expected.isEmpty, current != original else { return false }
            let matchesX = abs(current.minX - expected.minX) <= 2
            let matchesY = abs(current.minY - expected.minY) <= 2
            let matchesWidth = abs(current.width - expected.width) <= 2
            let matchesHeight = abs(current.height - expected.height) <= 2
            return matchesX && matchesY && matchesWidth && matchesHeight
        }
    }
}

enum DockPreviewOrientation: String, Equatable {
    case bottom
    case left
    case right

    static func sanitized(_ raw: String?) -> DockPreviewOrientation {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}

struct DockPreviewPreferences: Equatable {
    let orientation: DockPreviewOrientation
    let autohide: Bool
    let tileSize: CGFloat
    let magnification: Bool
    let magnifiedTileSize: CGFloat

    var hoverTileSize: CGFloat {
        magnification ? max(tileSize, magnifiedTileSize) : tileSize
    }

    static func sanitized(orientation rawOrientation: String?,
                          autohide: Bool?,
                          tileSize rawTileSize: Double?,
                          magnification: Bool?,
                          magnifiedTileSize rawMagnifiedTileSize: Double?) -> DockPreviewPreferences {
        let size = rawTileSize ?? 64
        let magnifiedSize = rawMagnifiedTileSize ?? 128
        return DockPreviewPreferences(
            orientation: DockPreviewOrientation.sanitized(rawOrientation),
            autohide: autohide ?? false,
            tileSize: CGFloat(min(max(size, 16), 256)),
            magnification: magnification ?? false,
            magnifiedTileSize: CGFloat(min(max(magnifiedSize, 16), 256))
        )
    }
}

enum DockPreviewBlockedReason: String, Equatable {
    case missingAccessibility
    case missingScreenRecording
    case dockUnavailable
}

struct DockPreviewAvailability: Equatable {
    let canRun: Bool
    let blockedReason: DockPreviewBlockedReason?
}

struct DockPreviewCloseState: Equatable {
    let remainingWindowIDs: [CGWindowID]
    let selectedWindowID: CGWindowID?
    let shouldEndSession: Bool
}

enum DockPreviewCloseAction: Equatable {
    case closeWindow
    case quitApp
}

struct DockPreviewMouseDownDecision: Equatable {
    let shouldEndSession: Bool
}

struct HoverCorridor: Equatable {
    let rects: [CGRect]

    func contains(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }
}

enum DockPreviewWindowOrder: Equatable {
    case lastUse
    case creation

    static func fromDefaults(orderByCreation: Bool) -> DockPreviewWindowOrder {
        orderByCreation ? .creation : .lastUse
    }
}

enum DockPreviewSupport {
    static func handlesMiddleClick(eventType: NSEvent.EventType, buttonNumber: Int,
                                   point: CGPoint, visibleRect: CGRect, isHidden: Bool) -> Bool {
        (eventType == .otherMouseDown || eventType == .otherMouseUp)
            && buttonNumber == 2 && !isHidden && visibleRect.contains(point)
    }

    static func closeAction(quitAppOnClose: Bool) -> DockPreviewCloseAction {
        quitAppOnClose ? .quitApp : .closeWindow
    }

    static func orderedWindows(_ windows: [SwitcherItem],
                               order: DockPreviewWindowOrder) -> [SwitcherItem] {
        switch order {
        case .lastUse:
            return windows
        case .creation:
            return windows.sorted { lhs, rhs in
                (lhs.windowID ?? 0) < (rhs.windowID ?? 0)
            }
        }
    }

    static func performCloseAction(quitAppOnClose: Bool,
                                   requestQuit: () -> Bool,
                                   closeWindow: () -> Void) {
        if closeAction(quitAppOnClose: quitAppOnClose) == .quitApp,
           requestQuit() {
            return
        }
        closeWindow()
    }

    static let defaultOpenDelayMilliseconds = 200
    static let openDelayMillisecondsRange: ClosedRange<Int> = 200 ... 900

    static func sanitizedOpenDelay(milliseconds: Int) -> Int {
        min(max(milliseconds, openDelayMillisecondsRange.lowerBound),
            openDelayMillisecondsRange.upperBound)
    }

    static func openDelay(milliseconds: Int) -> TimeInterval {
        TimeInterval(sanitizedOpenDelay(milliseconds: milliseconds)) / 1000
    }

    static let switchDelay: TimeInterval = 0.1

    static let prefetchLead: TimeInterval = 0.1

    static func prefetchDelay(openDelay: TimeInterval) -> TimeInterval {
        max(0, openDelay - prefetchLead)
    }
    static let hideDelay: TimeInterval = 0.22
    static let panelStayMargin: CGFloat = 6
    static let edgePadding: CGFloat = 8
    static let panelGap: CGFloat = 6
    static let autohidePanelGap: CGFloat = 0
    static let corridorMargin: CGFloat = 12
    static func canDragToPlace(hasWindowID: Bool, isFullscreen: Bool) -> Bool {
        hasWindowID && !isFullscreen
    }

    static let dragLiftDistance: CGFloat = 6

    static func dragOrigin(pointer: CGPoint,
                           windowSize: CGSize,
                           visibleFrame: CGRect) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0,
              windowSize.width > 0, windowSize.height > 0
        else { return pointer }

        let visibleWidth = min(windowSize.width, visibleFrame.width)
        let visibleHeight = min(windowSize.height, visibleFrame.height)
        return CGPoint(
            x: min(max(pointer.x, visibleFrame.minX), visibleFrame.maxX - visibleWidth),
            y: min(max(pointer.y, visibleFrame.minY + visibleHeight), visibleFrame.maxY)
        )
    }

    static var cardPadding: CGFloat { cardPadding(scale: PreviewSizing.scale) }
    static var cardTitleSpacing: CGFloat { cardTitleSpacing(scale: PreviewSizing.scale) }
    static let cardTitleHeight: CGFloat = 29
    static var cardSpacing: CGFloat { gap(8, scale: PreviewSizing.scale) }
    static var panelPadding: CGFloat { gap(10, scale: PreviewSizing.scale) }
    static let panelHeaderHeight: CGFloat = 28
    static var cardThumbnailInset: CGFloat { cardThumbnailInset(scale: PreviewSizing.scale) }

    private static func gap(_ normal: CGFloat, scale: CGFloat) -> CGFloat {
        (normal * min(scale, 1)).rounded()
    }
    static func cardPadding(scale: CGFloat) -> CGFloat { gap(10, scale: scale) }
    static func cardTitleSpacing(scale: CGFloat) -> CGFloat { gap(7, scale: scale) }
    static func cardThumbnailInset(scale: CGFloat) -> CGFloat { gap(5, scale: scale) }

    static func cardPictureSize(scale: CGFloat) -> CGSize {
        let width = (200 * scale / 8).rounded(.down) * 8
        return CGSize(width: width, height: width * 5 / 8)
    }

    static func cardThumbnailSize(scale: CGFloat) -> CGSize {
        let picture = cardPictureSize(scale: scale)
        let inset = cardThumbnailInset(scale: scale)
        return CGSize(width: picture.width + inset * 2,
                      height: picture.height + inset * 2)
    }

    static func cardSize(scale: CGFloat, minimal: Bool = false) -> CGSize {
        let thumbnail = cardThumbnailSize(scale: scale)
        let padding = cardPadding(scale: scale)
        return CGSize(width: thumbnail.width + padding * 2,
                      height: thumbnail.height + padding * 2
                          + (minimal ? 0 : cardTitleSpacing(scale: scale) + cardTitleHeight))
    }

    static var cardAppBadgeSize: CGFloat { (32 * PreviewSizing.scale).rounded() }
    static var cardAppBadgeArtworkInset: CGFloat { (cardAppBadgeSize * 0.094).rounded() }

    static func cardFallbackIconSize(scale: CGFloat) -> CGFloat {
        (52 * scale).rounded()
    }

    static var cardThumbnailWidth: CGFloat { cardThumbnailSize(scale: PreviewSizing.scale).width }
    static var cardThumbnailHeight: CGFloat { cardThumbnailSize(scale: PreviewSizing.scale).height }
    static var cardWidth: CGFloat { cardSize(scale: PreviewSizing.scale).width }
    static var cardHeight: CGFloat {
        cardSize(scale: PreviewSizing.scale,
                 minimal: UserDefaults.standard.bool(forKey: DefaultsKey.minimalWindowPreviews)).height
    }
    static var cardFallbackIconSize: CGFloat { cardFallbackIconSize(scale: PreviewSizing.scale) }

    static let backgroundOpacityRange: ClosedRange<Double> = 0.4...1

    static func sanitizedBackgroundOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return backgroundOpacityRange.upperBound }
        return min(max(value, backgroundOpacityRange.lowerBound), backgroundOpacityRange.upperBound)
    }

    static func dockProximityBand(tileSize: CGFloat) -> CGFloat {
        max(160, tileSize * 1.5 + 60)
    }

    static let mouseMoveSampleInterval: TimeInterval = 1.0 / 60

    static let dockHitTimeout: Float = 0.25

    static func availability(enabled: Bool,
                             hasAccessibility: Bool,
                             hasScreenRecording: Bool,
                             preferences: DockPreviewPreferences?) -> DockPreviewAvailability {
        guard enabled else {
            return DockPreviewAvailability(canRun: false, blockedReason: nil)
        }
        guard hasAccessibility else {
            return DockPreviewAvailability(canRun: false, blockedReason: .missingAccessibility)
        }
        guard hasScreenRecording else {
            return DockPreviewAvailability(canRun: false, blockedReason: .missingScreenRecording)
        }
        guard preferences != nil else {
            return DockPreviewAvailability(canRun: false, blockedReason: .dockUnavailable)
        }
        return DockPreviewAvailability(canRun: true, blockedReason: nil)
    }

    static func panelFrame(anchor: CGRect,
                           panelSize: CGSize,
                           screenVisibleFrame: CGRect,
                           orientation: DockPreviewOrientation,
                           gap: CGFloat = panelGap,
                           padding: CGFloat = edgePadding) -> CGRect {
        let width = min(panelSize.width, max(1, screenVisibleFrame.width - padding * 2))
        let height = min(panelSize.height, max(1, screenVisibleFrame.height - padding * 2))

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }

        let x: CGFloat
        let y: CGFloat
        switch orientation {
        case .bottom:
            x = clamped(anchor.midX - width / 2,
                        lower: screenVisibleFrame.minX + padding,
                        upper: screenVisibleFrame.maxX - width - padding)
            y = clamped(anchor.maxY + gap,
                        lower: screenVisibleFrame.minY + padding,
                        upper: screenVisibleFrame.maxY - height - padding)
        case .left:
            x = clamped(anchor.maxX + gap,
                        lower: screenVisibleFrame.minX + padding,
                        upper: screenVisibleFrame.maxX - width - padding)
            y = clamped(anchor.midY - height / 2,
                        lower: screenVisibleFrame.minY + padding,
                        upper: screenVisibleFrame.maxY - height - padding)
        case .right:
            x = clamped(anchor.minX - width - gap,
                        lower: screenVisibleFrame.minX + padding,
                        upper: screenVisibleFrame.maxX - width - padding)
            y = clamped(anchor.midY - height / 2,
                        lower: screenVisibleFrame.minY + padding,
                        upper: screenVisibleFrame.maxY - height - padding)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func showsPanelHeader(isPinned: Bool) -> Bool {
        isPinned
    }

    static var cardTitleTextWidth: CGFloat { cardThumbnailWidth - 40 }

    static func showsCardAppBadge(hasPreview: Bool) -> Bool {
        hasPreview
    }

    static func showsCardControls(isHovering: Bool, isSelected: Bool) -> Bool {
        isHovering || isSelected
    }

    static func stacksVertically(orientation: DockPreviewOrientation, isPinned: Bool) -> Bool {
        !isPinned && (orientation == .left || orientation == .right)
    }

    static func visibleCardCount(itemCount: Int,
                                 screenVisibleFrame: CGRect,
                                 orientation: DockPreviewOrientation,
                                 isPinned: Bool,
                                 padding: CGFloat = panelPadding,
                                 cardWidth: CGFloat = cardWidth,
                                 cardHeight: CGFloat = cardHeight,
                                 spacing: CGFloat = cardSpacing) -> Int {
        let vertical = stacksVertically(orientation: orientation, isPinned: isPinned)
        let cardExtent = vertical ? cardHeight : cardWidth
        let screenExtent = vertical ? screenVisibleFrame.height : screenVisibleFrame.width
        let maxExtent = max(cardExtent + padding * 2,
                            min(screenExtent * 0.9, screenExtent - edgePadding * 2))
        let available = max(1, Int((maxExtent - padding * 2 + spacing) / (cardExtent + spacing)))
        return min(max(1, itemCount), available)
    }

    static func panelSize(itemCount: Int,
                          screenVisibleFrame: CGRect,
                          isPinned: Bool,
                          orientation: DockPreviewOrientation = .bottom,
                          padding: CGFloat = panelPadding,
                          cardWidth: CGFloat = cardWidth,
                          cardHeight: CGFloat = cardHeight,
                          spacing: CGFloat = cardSpacing) -> CGSize {
        let count = max(1, itemCount)
        let vertical = stacksVertically(orientation: orientation, isPinned: isPinned)
        let visibleCards = visibleCardCount(itemCount: count,
                                            screenVisibleFrame: screenVisibleFrame,
                                            orientation: orientation,
                                            isPinned: isPinned,
                                            padding: padding,
                                            cardWidth: cardWidth,
                                            cardHeight: cardHeight,
                                            spacing: spacing)
        let run = CGFloat(visibleCards) * (vertical ? cardHeight : cardWidth)
            + CGFloat(max(0, visibleCards - 1)) * spacing + padding * 2
        let header = showsPanelHeader(isPinned: isPinned) ? panelHeaderHeight : 0
        if vertical {
            let maxHeight = max(cardHeight + padding * 2,
                                min(screenVisibleFrame.height * 0.9,
                                    screenVisibleFrame.height - edgePadding * 2))
            return CGSize(width: cardWidth + padding * 2,
                          height: min(run + header, maxHeight + header))
        }
        let maxWidth = max(cardWidth + padding * 2,
                           min(screenVisibleFrame.width * 0.9,
                               screenVisibleFrame.width - edgePadding * 2))
        return CGSize(width: min(run, maxWidth), height: cardHeight + padding * 2 + header)
    }

    static func windowPositionText(selectedWindowID: CGWindowID?, windowIDs: [CGWindowID]) -> String? {
        guard windowIDs.count > 1 else { return nil }
        guard let selectedWindowID,
              let index = windowIDs.firstIndex(of: selectedWindowID) else {
            return "\(windowIDs.count)"
        }
        return "\(index + 1)/\(windowIDs.count)"
    }

    static func adjacentWindowID(selectedWindowID: CGWindowID?,
                                 windowIDs: [CGWindowID],
                                 offset: Int) -> CGWindowID? {
        guard !windowIDs.isEmpty else { return nil }
        guard windowIDs.count > 1 else { return windowIDs.first }

        let currentIndex: Int
        if let selectedWindowID,
           let index = windowIDs.firstIndex(of: selectedWindowID) {
            currentIndex = index
        } else {
            currentIndex = offset < 0 ? 0 : -1
        }
        let nextIndex = (currentIndex + offset + windowIDs.count) % windowIDs.count
        return windowIDs[nextIndex]
    }

    static func mouseDownDecision(isVisible: Bool,
                                  isPinned: Bool,
                                  isInsidePanel: Bool) -> DockPreviewMouseDownDecision {
        guard isVisible, !isPinned, !isInsidePanel else {
            return DockPreviewMouseDownDecision(shouldEndSession: false)
        }
        return DockPreviewMouseDownDecision(shouldEndSession: true)
    }

    static func hoverCorridor(iconFrame: CGRect,
                              panelFrame: CGRect,
                              orientation: DockPreviewOrientation,
                              margin: CGFloat = corridorMargin) -> HoverCorridor {
        let icon = iconFrame.insetBy(dx: -margin, dy: -margin)
        let panel = panelFrame.insetBy(dx: -margin, dy: -margin)

        let bridge: CGRect
        switch orientation {
        case .bottom:
            let lowerY = min(iconFrame.maxY, panelFrame.minY)
            let upperY = max(iconFrame.maxY, panelFrame.minY)
            bridge = CGRect(x: iconFrame.minX - margin,
                            y: lowerY,
                            width: iconFrame.width + margin * 2,
                            height: max(0, upperY - lowerY))
        case .left:
            let lowerX = min(iconFrame.maxX, panelFrame.minX)
            let upperX = max(iconFrame.maxX, panelFrame.minX)
            bridge = CGRect(x: lowerX,
                            y: iconFrame.minY - margin,
                            width: max(0, upperX - lowerX),
                            height: iconFrame.height + margin * 2)
        case .right:
            let lowerX = min(panelFrame.maxX, iconFrame.minX)
            let upperX = max(panelFrame.maxX, iconFrame.minX)
            bridge = CGRect(x: lowerX,
                            y: iconFrame.minY - margin,
                            width: max(0, upperX - lowerX),
                            height: iconFrame.height + margin * 2)
        }

        return HoverCorridor(rects: [icon, panel, bridge])
    }

    static func closeState(afterRemoving closedWindowID: CGWindowID,
                           windowIDs: [CGWindowID],
                           selectedWindowID: CGWindowID?) -> DockPreviewCloseState {
        let remaining = windowIDs.filter { $0 != closedWindowID }
        let removedSelection = selectedWindowID == closedWindowID
        return DockPreviewCloseState(
            remainingWindowIDs: remaining,
            selectedWindowID: removedSelection ? nil : selectedWindowID,
            shouldEndSession: remaining.isEmpty
        )
    }
}
