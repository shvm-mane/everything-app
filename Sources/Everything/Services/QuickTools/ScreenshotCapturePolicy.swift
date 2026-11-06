// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum ScreenshotCapturePolicy {
    static func protectedWindowIDs(workflowWindowIDs: Set<CGWindowID>,
                                   contentWindowIDs: Set<CGWindowID>,
                                   honoursVisibilityPreference: Bool) -> Set<CGWindowID> {
        honoursVisibilityPreference
            ? workflowWindowIDs
            : workflowWindowIDs.union(contentWindowIDs)
    }

    static func excludedWindowIDs(hideVorssaintWindows: Bool,
                                  ownWindowIDs: Set<CGWindowID>,
                                  protectedWindowIDs: Set<CGWindowID>,
                                  islandWindowIDs: Set<CGWindowID> = []) -> Set<CGWindowID> {
        let excluded = hideVorssaintWindows ? ownWindowIDs : ownWindowIDs.intersection(protectedWindowIDs)
        return excluded.subtracting(islandWindowIDs.subtracting(protectedWindowIDs))
    }

    static func islandCaptureWindowIDs(islandWindowIDs: Set<CGWindowID>,
                                       mainWindowID: CGWindowID?,
                                       showsInCaptures: Bool,
                                       showsCaptureTool: Bool) -> Set<CGWindowID> {
        guard showsInCaptures else { return [] }
        guard showsCaptureTool, let mainWindowID else { return islandWindowIDs }
        return islandWindowIDs.subtracting([mainWindowID])
    }

    static func canPickWindow(_ windowID: CGWindowID,
                              isOwnWindow: Bool,
                              hideVorssaintWindows: Bool,
                              protectedWindowIDs: Set<CGWindowID>) -> Bool {
        !isOwnWindow
            || (!hideVorssaintWindows && !protectedWindowIDs.contains(windowID))
    }

    struct CaptureWindow: Equatable {
        let id: CGWindowID
        let ownerPID: pid_t
        let frame: CGRect
        var isUntitled = false
    }

    static let decorationMargin: ClosedRange<CGFloat> = 1...32

    static func decorationWindowIDs(frontToBack windows: [CaptureWindow]) -> Set<CGWindowID> {
        var decorations: Set<CGWindowID> = []
        for (index, window) in windows.enumerated() where window.isUntitled {
            let neighbours = [index - 1, index + 1].filter(windows.indices.contains)
            if neighbours.contains(where: { frames(window, around: windows[$0]) }) {
                decorations.insert(window.id)
            }
        }
        return decorations
    }

    private static func frames(_ decoration: CaptureWindow, around window: CaptureWindow) -> Bool {
        guard decoration.ownerPID != window.ownerPID else { return false }
        let margins = [window.frame.minX - decoration.frame.minX,
                       window.frame.minY - decoration.frame.minY,
                       decoration.frame.maxX - window.frame.maxX,
                       decoration.frame.maxY - window.frame.maxY]
        guard let smallest = margins.min(), let largest = margins.max() else { return false }
        return decorationMargin.contains(smallest) && decorationMargin.contains(largest)
            && largest - smallest <= 1
    }

    struct AttachedCapturePlan: Equatable {
        let windowIDs: [CGWindowID]
        let bounds: CGRect
    }

    static func attachedCapturePlan(target: CaptureWindow,
                                    frontToBack: [CaptureWindow]) -> AttachedCapturePlan? {
        guard target.frame.width > 0, target.frame.height > 0,
              let position = frontToBack.firstIndex(where: { $0.id == target.id })
        else { return nil }
        let attached = frontToBack[..<position].filter { candidate in
            candidate.ownerPID == target.ownerPID
                && target.frame.contains(candidate.frame)
        }
        guard !attached.isEmpty else { return nil }
        let ordered = Array(attached.reversed())
        return AttachedCapturePlan(windowIDs: [target.id] + ordered.map(\.id),
                                   bounds: target.frame)
    }

    static func compositeRect(for frame: CGRect, in bounds: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (frame.minX - bounds.minX) * scale,
               y: (bounds.maxY - frame.maxY) * scale,
               width: frame.width * scale,
               height: frame.height * scale)
    }

    static func layerCoversFrame(imageWidth: Int, imageHeight: Int, frame: CGRect, scale: CGFloat) -> Bool {
        guard scale > 0, frame.width > 0, frame.height > 0 else { return false }
        return abs(CGFloat(imageWidth) - frame.width * scale) <= 1
            && abs(CGFloat(imageHeight) - frame.height * scale) <= 1
    }

    static func layerScale(imageWidth: Int, imageHeight: Int, frame: CGRect,
                           candidates: [CGFloat]) -> CGFloat? {
        candidates.sorted(by: >).first {
            layerCoversFrame(imageWidth: imageWidth, imageHeight: imageHeight, frame: frame, scale: $0)
        }
    }

    enum CompositeTargetCapture: Equatable {
        case buffer(scale: CGFloat)
        case recapture(scale: CGFloat)

        var scale: CGFloat {
            switch self {
            case .buffer(let scale), .recapture(let scale): return scale
            }
        }
    }

    static func compositeTargetCapture(buffer: (width: Int, height: Int)?, frame: CGRect,
                                       candidates: [CGFloat]) -> CompositeTargetCapture? {
        if let buffer, let scale = layerScale(imageWidth: buffer.width, imageHeight: buffer.height,
                                              frame: frame, candidates: candidates) {
            return .buffer(scale: scale)
        }
        return candidates.max().map { .recapture(scale: $0) }
    }

    static func confirmedAttachment(_ plan: AttachedCapturePlan,
                                    confirmedIDs: Set<CGWindowID>?) -> AttachedCapturePlan? {
        guard let confirmedIDs else { return plan }
        guard let targetID = plan.windowIDs.first else { return nil }
        let attachedIDs = plan.windowIDs.dropFirst().filter(confirmedIDs.contains)
        guard !attachedIDs.isEmpty else { return nil }
        return AttachedCapturePlan(windowIDs: [targetID] + attachedIDs,
                                   bounds: plan.bounds)
    }
}
