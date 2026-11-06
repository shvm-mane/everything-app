// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct WindowMoveHandle: NSViewRepresentable {
    var acceptsDrops = false

    func makeNSView(context: Context) -> ShelfPanelMoveView {
        let view = ShelfPanelMoveView()
        view.acceptsDrops = acceptsDrops
        return view
    }

    func updateNSView(_ nsView: ShelfPanelMoveView, context: Context) {
        nsView.acceptsDrops = acceptsDrops
    }
}

class ShelfPanelMoveView: NSView {
    var acceptsDrops = false {
        didSet { syncDraggedTypes() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        syncDraggedTypes()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        ShelfService.shared.beginInteraction()
        defer { ShelfService.shared.endInteraction() }
        window?.performDrag(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender)
        ShelfService.shared.setDropTargeted(operation != [])
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender)
        ShelfService.shared.setDropTargeted(operation != [])
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        ShelfService.shared.setDropTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = acceptsDrops && ShelfService.shared.accept(draggingInfo: sender)
        ShelfService.shared.setDropTargeted(false)
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        ShelfService.shared.setDropTargeted(false)
    }

    private func syncDraggedTypes() {
        unregisterDraggedTypes()
        if acceptsDrops {
            registerForDraggedTypes(ShelfService.tileDropTypes)
        }
    }

    private func dropOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrops,
              !ShelfService.shared.isInternalDragActive,
              ShelfService.shared.canAcceptPasteboard(sender.draggingPasteboard) else {
            return []
        }
        return .copy
    }
}

struct ShelfTilesView: NSViewRepresentable {
    var items: [ShelfService.Item]
    var contentRevision: Int
    var selection: Set<UUID>
    var expandedBatches: Set<UUID>
    var pinnedIDs: Set<UUID>
    var revealID: UUID?
    var revealSerial: Int
    var sideways = false

    static let tileSize = NSSize(width: 78, height: 88)
    static let spacing: CGFloat = 10
    static let inset: CGFloat = 4

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.revealedSerial = revealSerial
        let scroll = ResizingScrollView()
        let coordinator = context.coordinator
        scroll.sizeChanged = { [weak scroll, sideways] in
            guard sideways, let scroll, let items = coordinator.lastRebuiltItems,
                  !ShelfService.shared.isInternalDragActive else { return }
            Self.rebuildTiles(scroll: scroll, items: items,
                              selection: coordinator.lastRebuiltSelection ?? [],
                              expandedBatches: coordinator.lastRebuiltExpandedBatches ?? [],
                              pinnedIDs: coordinator.lastRebuiltPinnedIDs ?? [],
                              coordinator: coordinator)
        }
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = sideways ? .allowed : .none
        scroll.verticalScrollElasticity = sideways ? .none : .allowed
        scroll.contentView.drawsBackground = false
        let document = FlippedView()
        document.acceptsDrops = !sideways
        document.sideways = sideways
        scroll.documentView = document
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        Self.rebuildTiles(scroll: scroll, items: items, selection: selection, expandedBatches: expandedBatches,
                          pinnedIDs: pinnedIDs, revealID: revealID, revealSerial: revealSerial, coordinator: context.coordinator)
    }

    static func rebuildTiles(scroll: NSScrollView,
                             items: [ShelfService.Item],
                             selection: Set<UUID>,
                             expandedBatches: Set<UUID>,
                             pinnedIDs: Set<UUID>,
                             revealID: UUID? = nil,
                             revealSerial: Int = 0,
                             coordinator: Coordinator? = nil) {
        guard let document = scroll.documentView else { return }

        let tile = Self.tileSize
        let inset = Self.inset
        let spacing = Self.spacing
        let sideways = (document as? FlippedView)?.sideways == true
        let contentWidth = max(scroll.contentSize.width, 276)
        let columns = ShelfTileLayout.columnCount(contentWidth: contentWidth,
                                                   tileWidth: tile.width,
                                                   spacing: spacing,
                                                   inset: inset)
        let rows = sideways
            ? ShelfTileLayout.rowCount(contentHeight: scroll.contentSize.height, tileHeight: tile.height,
                                       spacing: spacing, inset: inset)
            : max(1, Int(ceil(Double(items.count) / Double(columns))))
        let frame: (Int) -> CGRect = { index in
            sideways
                ? ShelfTileLayout.sidewaysTileFrame(index: index, rows: rows, tileSize: tile, spacing: spacing, inset: inset)
                : ShelfTileLayout.tileFrame(index: index, columns: columns, tileSize: tile, spacing: spacing, inset: inset)
        }

        let unchanged = coordinator.map {
            items.count == $0.lastRebuiltItems?.count
                && zip(items, $0.lastRebuiltItems ?? []).allSatisfy { $0.hasSameContent(as: $1) }
                && selection == $0.lastRebuiltSelection
                && expandedBatches == $0.lastRebuiltExpandedBatches
                && pinnedIDs == $0.lastRebuiltPinnedIDs
                && scroll.contentSize == $0.lastRebuiltContentSize
        } ?? false
        if unchanged {
            if let coordinator {
                revealIfNeeded(in: document, frame: frame, items: items,
                               revealID: revealID, revealSerial: revealSerial, coordinator: coordinator)
            }
            return
        }
        coordinator?.lastRebuiltItems = items
        coordinator?.lastRebuiltSelection = selection
        coordinator?.lastRebuiltExpandedBatches = expandedBatches
        coordinator?.lastRebuiltPinnedIDs = pinnedIDs
        coordinator?.lastRebuiltContentSize = scroll.contentSize

        document.subviews.forEach { $0.removeFromSuperview() }

        for (index, item) in items.enumerated() {
            let view = ShelfTileView(item: item,
                                     isSelected: selection.contains(item.id),
                                     isExpanded: expandedBatches.contains(item.id),
                                     isPinned: pinnedIDs.contains(item.id))
            view.frame = frame(index)
            document.addSubview(view)
        }
        if sideways {
            let size = ShelfTileLayout.sidewaysDocumentSize(itemCount: items.count, rows: rows,
                                                             visibleSize: scroll.contentSize, tileSize: tile,
                                                             spacing: spacing, inset: inset)
            scroll.hasHorizontalScroller = size.width > scroll.contentSize.width + 1
            document.frame = NSRect(origin: .zero, size: size)
        } else {
            let contentHeight = inset * 2 + CGFloat(rows) * tile.height + CGFloat(max(0, rows - 1)) * spacing
            scroll.hasVerticalScroller = contentHeight > scroll.contentSize.height + 1
            document.frame = NSRect(x: 0,
                                    y: 0,
                                    width: contentWidth,
                                    height: max(contentHeight, scroll.contentSize.height))
        }
        if let coordinator {
            revealIfNeeded(in: document, frame: frame, items: items,
                           revealID: revealID, revealSerial: revealSerial, coordinator: coordinator)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var revealedSerial: Int?
        var lastRebuiltItems: [ShelfService.Item]?
        var lastRebuiltSelection: Set<UUID>?
        var lastRebuiltExpandedBatches: Set<UUID>?
        var lastRebuiltPinnedIDs: Set<UUID>?
        var lastRebuiltContentSize: NSSize?
    }

    private static func revealIfNeeded(in document: NSView,
                                       frame: (Int) -> CGRect,
                                       items: [ShelfService.Item],
                                       revealID: UUID?,
                                       revealSerial: Int,
                                       coordinator: Coordinator) {
        guard let revealID,
              ShelfRevealSupport.shouldReveal(serial: revealSerial, lastHonored: coordinator.revealedSerial)
        else { return }
        guard let index = items.firstIndex(where: { $0.id == revealID }) else { return }
        coordinator.revealedSerial = revealSerial
        let target = frame(index)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            document.scrollToVisible(target)
        }
        if let scrollView = document.enclosingScrollView {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private final class ResizingScrollView: NSScrollView {
        var sizeChanged: (() -> Void)?

        override func setFrameSize(_ newSize: NSSize) {
            let oldSize = frame.size
            super.setFrameSize(newSize)
            if newSize != oldSize { sizeChanged?() }
        }
    }

    private final class FlippedView: ShelfPanelMoveView {
        var sideways = false
        override var isFlipped: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard !sideways else { return }
            super.mouseDown(with: event)
        }
    }
}

final class ShelfTileView: NSView, NSDraggingSource {
    private let item: ShelfService.Item
    private let isSelected: Bool
    private let isExpanded: Bool
    private let isPinned: Bool
    private var mouseDownPoint: NSPoint = .zero
    private var didDrag = false
    private var draggedIDs: [UUID] = []
    private var isDropTargeted = false
    private var pendingRebuildAfterDrag = false
    private var closeButton: NSButton!
    private var pinBadge: NSImageView?
    private var expandButton: NSButton?
    private let sharePresenter = ShelfSharePresenter()

    init(item: ShelfService.Item, isSelected: Bool, isExpanded: Bool, isPinned: Bool) {
        self.item = item
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        super.init(frame: NSRect(origin: .zero, size: ShelfTilesView.tileSize))
        wantsLayer = true
        layer?.cornerRadius = 10
        syncChrome()
        registerForDraggedTypes(ShelfService.tileDropTypes)
        buildSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func syncChrome() {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : nil
        if isSelected || isDropTargeted {
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    private func setDropTargeted(_ targeted: Bool) {
        guard isDropTargeted != targeted else { return }
        isDropTargeted = targeted
        syncChrome()
    }

    private func buildSubviews() {
        if item.isBatch { addStackBackplates() }

        let iconWell = NSView(frame: NSRect(x: 7, y: 6, width: 64, height: 50))
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        addSubview(iconWell)

        let hasThumbnail = item.hasContentThumbnail
        let imageView = NSImageView(frame: iconWell.bounds.insetBy(dx: hasThumbnail ? 4 : 13,
                                                                   dy: hasThumbnail ? 4 : 8))
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        iconWell.addSubview(imageView)

        if item.isBatch {
            let badge = NSTextField(labelWithString: "\(item.leafCount)")
            badge.frame = NSRect(x: 50, y: 39, width: 22, height: 15)
            badge.font = .systemFont(ofSize: 9, weight: .bold)
            badge.alignment = .center
            badge.textColor = .white
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 7.5
            badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            addSubview(badge)

            let expand = NSButton(frame: NSRect(x: 4, y: 4, width: 17, height: 17))
            expand.image = NSImage(systemSymbolName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill",
                                   accessibilityDescription: nil)
            expand.isBordered = false
            expand.bezelStyle = .regularSquare
            expand.imagePosition = .imageOnly
            expand.contentTintColor = .secondaryLabelColor
            expand.target = self
            expand.action = #selector(toggleBatchExpansion)
            expandButton = expand
            addSubview(expand)
        }

        let label = NSTextField(labelWithString: item.title)
        label.frame = NSRect(x: 3, y: 59, width: 72, height: 24)
        label.font = .systemFont(ofSize: 10)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.textColor = .secondaryLabelColor
        addSubview(label)

        if isSelected {
            let badgeY: CGFloat = item.isBatch ? 22 : 4
            let badge = NSImageView(frame: NSRect(x: 4, y: badgeY, width: 16, height: 16))
            badge.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            badge.contentTintColor = .controlAccentColor
            addSubview(badge)
        }

        if isPinned {
            let badge = NSImageView(frame: NSRect(x: 58, y: 4, width: 17, height: 17))
            badge.image = NSImage(systemSymbolName: "pin.circle.fill", accessibilityDescription: nil)
            badge.contentTintColor = .controlAccentColor
            pinBadge = badge
            addSubview(badge)
        }

        closeButton = NSButton(frame: NSRect(x: 58, y: 4, width: 17, height: 17))
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(removeSelf)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    private static func tooltipText(for item: ShelfService.Item) -> String {
        switch item.payload {
        case let .file(url):
            return ShelfTooltipSupport.text(forFileNamed: item.title, resolvedKind: resolvedFileKind(for: url))
        case let .text(string):
            return ShelfTooltipSupport.text(forText: string)
        case let .link(url):
            return ShelfTooltipSupport.text(forLink: url)
        case .batch:
            let breakdown = ShelfTooltipSupport.breakdown(of: item.tooltipLeafKinds)
            let s = L10n.shared.s
            let strings = ShelfTooltipStrings(itemsFormat: s.shelfTooltipItemsFormat,
                                              itemsFew: s.shelfTooltipItemsFew,
                                              imageSingular: s.shelfTooltipImageSingular,
                                              imageFew: s.shelfTooltipImageFew,
                                              imagePlural: s.shelfTooltipImagePlural,
                                              fileSingular: s.shelfTooltipFileSingular,
                                              fileFew: s.shelfTooltipFileFew,
                                              filePlural: s.shelfTooltipFilePlural,
                                              noteSingular: s.shelfTooltipNoteSingular,
                                              noteFew: s.shelfTooltipNoteFew,
                                              notePlural: s.shelfTooltipNotePlural,
                                              linkSingular: s.shelfTooltipLinkSingular,
                                              linkFew: s.shelfTooltipLinkFew,
                                              linkPlural: s.shelfTooltipLinkPlural,
                                              agreement: L10n.shared.language.countAgreement)
            return ShelfTooltipSupport.text(forPile: breakdown, strings: strings)
        }
    }

    private static func resolvedFileKind(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
    }

    private func addStackBackplates() {
        for (index, offset) in [2, 1].enumerated() {
            let view = NSView(frame: NSRect(x: 7 + CGFloat(offset) * 3,
                                           y: 6 + CGFloat(offset) * 3,
                                           width: 64,
                                           height: 50))
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
            view.layer?.backgroundColor = NSColor.white.withAlphaComponent(index == 0 ? 0.035 : 0.055).cgColor
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
            addSubview(view)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
        pinBadge?.isHidden = true
        ShelfTooltipPopover.shared.scheduleShow(text: Self.tooltipText(for: item), for: self)
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        pinBadge?.isHidden = false
        ShelfTooltipPopover.shared.hide()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        ShelfService.shared.noteInteraction()
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        ShelfTooltipPopover.shared.hide()

        let strings = L10n.shared.s
        let menu = NSMenu()
        let pin = NSMenuItem(title: isPinned ? strings.shelfActionUnpin : strings.shelfActionPin,
                             action: #selector(togglePin),
                             keyEquivalent: "")
        pin.target = self
        pin.image = NSImage(systemSymbolName: isPinned ? "pin.slash" : "pin", accessibilityDescription: nil)
        menu.addItem(pin)
        guard !urls.isEmpty else { return menu }
        menu.addItem(.separator())

        let open = NSMenuItem(title: strings.shelfActionOpen,
                              action: #selector(openFiles),
                              keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let openWith = NSMenuItem(title: strings.shelfActionOpenWith,
                                  action: nil,
                                  keyEquivalent: "")
        let applications = commonApplications(for: urls)
        if applications.isEmpty {
            openWith.isEnabled = false
        } else {
            let submenu = NSMenu(title: strings.shelfActionOpenWith)
            for applicationURL in applications.prefix(40) {
                let entry = NSMenuItem(title: FileManager.default.displayName(atPath: applicationURL.path),
                                       action: #selector(openFilesWithApplication(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = applicationURL
                let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
                submenu.addItem(entry)
            }
            openWith.submenu = submenu
        }
        menu.addItem(openWith)

        if AppFeature.screenshot.isAvailable, ShelfInteractionSupport.editableImage(in: urls) != nil {
            let edit = NSMenuItem(title: FeatureStrings.screenshot(L10n.shared.language).editButton,
                                  action: #selector(editImage),
                                  keyEquivalent: "")
            edit.target = self
            menu.addItem(edit)
        }

        menu.addItem(sharePresenter.shareMenuItem(for: urls, title: strings.shelfActionShare))
        menu.addItem(.separator())

        let reveal = NSMenuItem(title: strings.cleanerRevealInFinder,
                                action: #selector(revealFiles),
                                keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        ShelfService.shared.noteInteraction()
        window?.makeKey()
        ShelfTooltipPopover.shared.hide()
        mouseDownPoint = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        let point = event.locationInWindow
        if hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 4 {
            didDrag = true
            beginItemDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        if item.isBatch, event.clickCount >= 2 {
            ShelfService.shared.toggleBatchExpansion(item.id)
        } else if event.modifierFlags.contains(.shift) {
            ShelfService.shared.extendSelection(to: item.id)
        } else {
            ShelfService.shared.toggleSelection(item.id)
        }
    }

    @objc private func removeSelf() {
        ShelfService.shared.removeItem(item.id)
    }

    @objc private func togglePin() {
        ShelfService.shared.toggleItemPin(item.id)
    }

    @objc private func toggleBatchExpansion() {
        ShelfService.shared.toggleBatchExpansion(item.id)
    }

    @objc private func openFiles() {
        for url in ShelfService.shared.fileURLsForActions(startingAt: item) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openFilesWithApplication(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL else { return }
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        guard !urls.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls,
                                withApplicationAt: applicationURL,
                                configuration: configuration)
    }

    @objc private func editImage() {
        guard let url = ShelfInteractionSupport.editableImage(
            in: ShelfService.shared.fileURLsForActions(startingAt: item)) else { return }
        ScreenshotService.shared.editImage(at: url)
    }

    @objc private func revealFiles() {
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func commonApplications(for urls: [URL]) -> [URL] {
        guard let first = urls.first else { return [] }
        var common = Set(NSWorkspace.shared.urlsForApplications(toOpen: first))
        for url in urls.dropFirst() {
            common.formIntersection(NSWorkspace.shared.urlsForApplications(toOpen: url))
        }
        return common.filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                FileManager.default.displayName(atPath: $0.path)
                    .localizedCaseInsensitiveCompare(
                        FileManager.default.displayName(atPath: $1.path)) == .orderedAscending
            }
    }

    private func beginItemDrag(with event: NSEvent) {
        let shelf = ShelfService.shared
        let candidates = shelf.selection.contains(item.id) ? shelf.selectedItems() : [item]
        let dragged = shelf.dragItems(for: candidates)
        guard !dragged.isEmpty else { return }
        let living = shelf.livingDragItems(in: dragged)
        guard !living.isEmpty else {
            shelf.handleDeadDrag(dragged)
            return
        }
        draggedIDs = living.map(\.id)

        let draggingItems: [NSDraggingItem] = living.map { entry in
            let draggingItem = NSDraggingItem(pasteboardWriter: shelf.pasteboardWriter(for: entry))
            draggingItem.setDraggingFrame(bounds, contents: entry.icon)
            return draggingItem
        }
        shelf.beginInternalDrag(items: living, from: window)
        shelf.beginInteraction()
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        ShelfService.shared.sourceOperationMask(for: context)
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        ShelfService.shared.internalDragMoved(to: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.async {
            ShelfService.shared.completeInternalDrag(dropAccepted: operation != [])
            ShelfService.shared.absorbOwnDrag()
        }
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = mergeOperation(for: sender)
        setDropTargeted(operation != [])
        if operation != [] { ShelfService.shared.noteInteraction() }
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = mergeOperation(for: sender)
        setDropTargeted(operation != [])
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ShelfService.shared.canMergePasteboard(sender.draggingPasteboard, into: item.id)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let merged = ShelfService.shared.merge(draggingInfo: sender, into: item.id)
        setDropTargeted(false)
        pendingRebuildAfterDrag = merged
        return merged
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
        guard pendingRebuildAfterDrag, let scroll = superview?.enclosingScrollView else { return }
        pendingRebuildAfterDrag = false
        ShelfTilesView.rebuildTiles(scroll: scroll,
                                   items: ShelfService.shared.visibleItems,
                                   selection: ShelfService.shared.selection,
                                   expandedBatches: ShelfService.shared.expandedBatches,
                                   pinnedIDs: ShelfService.shared.pinnedIDs)
    }

    private func mergeOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard ShelfService.shared.canMergePasteboard(sender.draggingPasteboard, into: item.id) else {
            return []
        }
        return ShelfService.shared.isInternalDragActive ? .move : .copy
    }
}
