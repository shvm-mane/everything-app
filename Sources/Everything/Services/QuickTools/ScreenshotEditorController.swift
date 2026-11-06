// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import Vision

final class ScreenshotEditorModel: ObservableObject, BackdropEditing {
    @Published private(set) var baseImage: CGImage
    @Published var annotations: [ScreenshotSupport.Annotation] = []
    @Published var spotlightDimStrength: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(spotlightDimStrength),
                                      forKey: DefaultsKey.screenshotSpotlightDim)
            refreshDirtyState()
        }
    }
    @Published var expansionFill = ScreenshotCanvasSupport.Fill.white
    @Published private(set) var expansionDraft: CGRect?
    @Published private(set) var expansionRejected = false
    private var expansionHandle: ScreenshotSupport.Handle?
    private var expansionStartPoint: CGPoint?

    @Published var selectedID: UUID?
    @Published var editingTextID: UUID?
    @Published var tool: ScreenshotSupport.Tool {
        didSet {
            UserDefaults.standard.set(tool.rawValue, forKey: DefaultsKey.screenshotLastTool)
            if oldValue == .expandCanvas, tool != .expandCanvas { cancelCanvasExpansion() }
            if tool != .select { clearTextSelection() }
            if tool != oldValue, tool != .select {
                selectedID = nil
                editingTextID = nil
            }
            if tool == .crop, oldValue != .crop {
                selectedID = nil
                cropDraft = CGRect(origin: .zero, size: imageSize)
            } else if oldValue == .crop {
                cropDraft = nil
                cropLoupePoint = nil
            }
        }
    }
    @Published private(set) var textWords: [ScreenshotSupport.RecognizedWord] = []
    @Published private(set) var textRuns: [CGRect]?
    private var carriedRuns: [ObjectIdentifier: [CGRect]] = [:]
    @Published private(set) var selectedWordIndexes: [Int] = []
    private var textSelectionAnchor: CGPoint?
    @Published private(set) var qrReading: BarcodeDetector.Reading?
    @Published var color: ScreenshotSupport.ColorID {
        didSet {
            UserDefaults.standard.set(color.rawValue, forKey: DefaultsKey.screenshotLastColor)
            applyStyleToSelection()
        }
    }
    @Published var stroke: ScreenshotSupport.StrokeID {
        didSet {
            UserDefaults.standard.set(stroke.rawValue, forKey: DefaultsKey.screenshotLastStroke)
            applyStyleToSelection()
        }
    }
    @Published var textSize: Int {
        didSet {
            UserDefaults.standard.set(textSize, forKey: DefaultsKey.screenshotLastTextSize)
            applyStyleToSelection()
        }
    }
    @Published var blurLevel: Int {
        didSet {
            UserDefaults.standard.set(blurLevel, forKey: DefaultsKey.screenshotLastBlurLevel)
            applyBlurToSelection()
        }
    }
    @Published var blurStyle: ScreenshotSupport.BlurStyleID {
        didSet {
            UserDefaults.standard.set(blurStyle.rawValue, forKey: DefaultsKey.screenshotLastBlurStyle)
            applyBlurToSelection()
        }
    }
    @Published var blurTextOnly: Bool {
        didSet {
            UserDefaults.standard.set(blurTextOnly, forKey: DefaultsKey.screenshotLastBlurTextOnly)
            applyBlurToSelection()
        }
    }
    @Published var arrowStyle: ScreenshotSupport.ArrowStyleID {
        didSet {
            UserDefaults.standard.set(arrowStyle.rawValue,
                                      forKey: DefaultsKey.screenshotLastArrowStyle)
            applyStyleToSelection()
        }
    }
    @Published var sticker: ScreenshotSupport.StickerID {
        didSet {
            UserDefaults.standard.set(sticker.rawValue,
                                      forKey: DefaultsKey.screenshotLastSticker)
            applyStickerToSelection()
        }
    }
    @Published var annotationShadowsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(annotationShadowsEnabled,
                                      forKey: DefaultsKey.screenshotAnnotationShadows)
            refreshDirtyState()
        }
    }
    @Published var backdropStyle: ScreenshotSupport.BackdropStyle {
        didSet {
            UserDefaults.standard.set(backdropStyle.encoded(),
                                      forKey: DefaultsKey.screenshotBackdropStyle)
            reloadBackdropImageIfNeeded()
            refreshDirtyState()
        }
    }
    @Published private(set) var backdropPresets: [ScreenshotSupport.BackdropStyle] {
        didSet {
            UserDefaults.standard.set(
                ScreenshotSupport.encodedBackdropPresets(backdropPresets),
                forKey: DefaultsKey.screenshotBackdropPresets)
        }
    }
    @Published private(set) var backdropImage: CGImage?
    @Published var watermarkStyle: ScreenshotSupport.WatermarkStyle {
        didSet {
            UserDefaults.standard.set(watermarkStyle.encoded(),
                                      forKey: DefaultsKey.screenshotWatermarkStyle)
            reloadWatermarkImageIfNeeded()
            refreshDirtyState()
        }
    }
    @Published private(set) var watermarkImage: CGImage?
    @Published private(set) var watermarkPresets: [ScreenshotSupport.WatermarkStyle] {
        didSet {
            UserDefaults.standard.set(
                ScreenshotSupport.encodedWatermarkPresets(watermarkPresets),
                forKey: DefaultsKey.screenshotWatermarkPresets)
        }
    }
    @Published var cropDraft: CGRect?
    @Published private(set) var cropLoupePoint: CGPoint?
    @Published var zoomOverride: CGFloat?
    var currentDisplayZoom: CGFloat = 0.5
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var isDirty = false

    let scale: CGFloat
    private(set) var pixelated: [Int: CGImage] = [:]
    private(set) var softBlurred: [Int: CGImage] = [:]
    private let eraseCache = ScreenshotRenderer.EraseCache()
    private let imageLayerCache = ScreenshotRenderer.ImageLayerCache()

    var blurSources: ScreenshotRenderer.BlurSources {
        ScreenshotRenderer.BlurSources(mosaics: pixelated,
                                       softBlurs: softBlurred,
                                       image: baseImage,
                                       eraseCache: eraseCache,
                                       textRuns: textRuns,
                                       imageLayerCache: imageLayerCache)
    }

    private var undoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
    private var redoStack: [(image: CGImage, annotations: [ScreenshotSupport.Annotation])] = []
    private static let undoLimit = 60
    private var cleanImage: CGImage?
    private var cleanAnnotations: [ScreenshotSupport.Annotation] = []
    private var cleanBackdropStyle = ScreenshotSupport.BackdropStyle()
    private var cleanWatermarkStyle = ScreenshotSupport.WatermarkStyle()
    private var cleanAnnotationShadowsEnabled = false
    private var cleanSpotlightDimStrength: CGFloat = 0.5

    private var dragStart: CGPoint = .zero
    @Published private(set) var draftID: UUID?
    private var moveOrigin: CGRect = .zero
    private var movePoints: [CGPoint] = []
    private var activeHandle: ScreenshotSupport.Handle?
    private var cropResizeOrigin: CGRect?
    private var cropMoveOrigin: CGRect?
    private var cropSelectionOrigin: CGRect?
    private var dragRegistered = false
    private var editingSelectedAnnotation = false
    private var newTextID: UUID?
    private(set) var lastPointerActivityUptime: TimeInterval = -.infinity

    func notePointerActivity() {
        lastPointerActivityUptime = ProcessInfo.processInfo.systemUptime
    }

    var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    var pointSize: CGSize {
        CGSize(width: CGFloat(baseImage.width) / scale, height: CGFloat(baseImage.height) / scale)
    }

    init(image: CGImage, scale: CGFloat) {
        baseImage = image
        self.scale = scale
        let defaults = UserDefaults.standard
        tool = ScreenshotSupport.Tool.startingTool(
            remembered: defaults.string(forKey: DefaultsKey.screenshotLastTool))
        color = ScreenshotSupport.ColorID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastColor))
        stroke = ScreenshotSupport.StrokeID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastStroke))
        textSize = ScreenshotSupport.sanitizedTextSize(
            defaults.integer(forKey: DefaultsKey.screenshotLastTextSize))
        blurLevel = ScreenshotSupport.BlurStrength.startingLevel(
            remembered: defaults.integer(forKey: DefaultsKey.screenshotLastBlurLevel))
        blurStyle = ScreenshotSupport.BlurStyleID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastBlurStyle))
        blurTextOnly = defaults.bool(forKey: DefaultsKey.screenshotLastBlurTextOnly)
        spotlightDimStrength = ScreenshotSupport.sanitizedSpotlightDim(
            CGFloat(defaults.double(forKey: DefaultsKey.screenshotSpotlightDim)))
        arrowStyle = ScreenshotSupport.ArrowStyleID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastArrowStyle))
        sticker = ScreenshotSupport.StickerID.sanitized(
            defaults.string(forKey: DefaultsKey.screenshotLastSticker))
        annotationShadowsEnabled = defaults.bool(
            forKey: DefaultsKey.screenshotAnnotationShadows)
        let rawStyle = defaults.string(forKey: DefaultsKey.screenshotBackdropStyle) ?? ""
        backdropStyle = ScreenshotSupport.BackdropStyle.decoded(rawStyle)
        backdropPresets = ScreenshotSupport.decodedBackdropPresets(
            defaults.string(forKey: DefaultsKey.screenshotBackdropPresets))
        watermarkStyle = ScreenshotSupport.WatermarkStyle.decoded(
            defaults.string(forKey: DefaultsKey.screenshotWatermarkStyle))
        watermarkPresets = ScreenshotSupport.decodedWatermarkPresets(
            defaults.string(forKey: DefaultsKey.screenshotWatermarkPresets))
        pixelated = [:]
        reloadBackdropImageIfNeeded()
        reloadWatermarkImageIfNeeded()
        recordCleanState()
    }

    var backdropPaddingPixels: CGFloat {
        showsBackdrop
            ? ScreenshotSupport.backdropPadding(for: imageSize,
                                                factor: CGFloat(backdropStyle.padding))
            : 0
    }

    var cardCornerPixels: CGFloat {
        ScreenshotSupport.cardCornerRadius(for: imageSize,
                                           factor: CGFloat(backdropStyle.cornerRadius))
    }

    var cardOutlineCornerPixels: CGFloat {
        max(cardCornerPixels, baseImageCornerPixels)
    }

    private var measuredBaseImageCorner: (image: CGImage, radius: CGFloat)?

    private var baseImageCornerPixels: CGFloat {
        if let measured = measuredBaseImageCorner, measured.image === baseImage { return measured.radius }
        let radius = ScreenshotSupport.transparentCornerRadius(of: baseImage)
        measuredBaseImageCorner = (baseImage, radius)
        return radius
    }

    var showsBackdrop: Bool {
        if case .none = backdropFill { return false }
        return true
    }

    var backdropFill: ScreenshotRenderer.BackdropFill {
        let style = backdropStyle.sanitized()
        switch style.kind {
        case .none:
            return .none
        case .preset:
            guard let id = style.presetID,
                  let preset = ScreenshotSupport.BackdropID(rawValue: id)
            else { return .none }
            return .colors(preset.stops)
        case .solid, .gradient:
            let colors = (style.colors ?? []).map {
                (red: $0[0], green: $0[1], blue: $0[2])
            }
            return colors.isEmpty ? .none : .colors(colors)
        case .image:
            guard let backdropImage else { return .none }
            return .image(backdropImage)
        }
    }

    private func reloadBackdropImageIfNeeded() {
        guard backdropStyle.kind == .image, let path = backdropStyle.imagePath else {
            backdropImage = nil
            return
        }
        if backdropImage != nil, loadedBackdropPath == path { return }
        loadedBackdropPath = path
        backdropImage = Self.loadImageFile(path)
    }

    private var loadedBackdropPath: String?

    var showsWatermark: Bool {
        switch watermarkStyle.sanitized().kind {
        case .none: return false
        case .text: return true
        case .image: return watermarkImage != nil
        }
    }

    private func reloadWatermarkImageIfNeeded() {
        guard watermarkStyle.kind == .image, let path = watermarkStyle.imagePath else {
            watermarkImage = nil
            return
        }
        if watermarkImage != nil, loadedWatermarkPath == path { return }
        loadedWatermarkPath = path
        watermarkImage = Self.loadImageFile(path)
    }

    private var loadedWatermarkPath: String?

    private static func loadImageFile(_ path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Backdrop presets

    func saveCurrentBackdropAsPreset() {
        let style = backdropStyle.sanitized()
        guard style.kind != .none, style.kind != .preset else { return }
        var snapshot = style
        snapshot.padding = 0.5
        snapshot.cornerRadius = 0.1
        snapshot.blur = 0
        guard !backdropPresets.contains(where: {
            var candidate = $0
            candidate.padding = 0.5
            candidate.cornerRadius = 0.1
            candidate.blur = 0
            return candidate == snapshot
        }) else { return }
        backdropPresets = Array((backdropPresets + [snapshot])
            .suffix(ScreenshotSupport.backdropPresetLimit))
    }

    func removeBackdropPreset(at index: Int) {
        guard backdropPresets.indices.contains(index) else { return }
        backdropPresets.remove(at: index)
    }

    // MARK: - Watermark presets

    func saveCurrentWatermarkAsPreset() {
        let style = watermarkStyle.sanitized()
        guard style.kind != .none, !watermarkPresets.contains(style) else { return }
        watermarkPresets = Array((watermarkPresets + [style])
            .suffix(ScreenshotSupport.backdropPresetLimit))
    }

    func removeWatermarkPreset(at index: Int) {
        guard watermarkPresets.indices.contains(index) else { return }
        watermarkPresets.remove(at: index)
    }

    // MARK: - Selectable text on the canvas

    var selectedText: String {
        ScreenshotSupport.joinedWords(textWords, selected: selectedWordIndexes)
    }

    func clearTextSelection() {
        textSelectionAnchor = nil
        if !selectedWordIndexes.isEmpty { selectedWordIndexes = [] }
    }

    func wordIndex(at point: CGPoint) -> Int? {
        textWords.firstIndex { $0.rect.insetBy(dx: -2 * scale, dy: -2 * scale).contains(point) }
    }

    func recognizeText() {
        let image = baseImage
        let width = CGFloat(image.width)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tiles = ScreenshotSupport.recognitionTiles(width: image.width, height: image.height)
            var reads: [[ScreenshotSupport.BandWord]?] = []
            var lineOffset = 0
            for band in tiles {
                guard let current = self, image === current.baseImage else { return }
                let tileY = band.rect.minY
                let currentHeight = band.rect.height
                guard let tile = image.cropping(to: band.rect) else { break }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: tile, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    reads.append(nil)
                    continue
                }
                func imageRect(_ box: CGRect) -> CGRect {
                    CGRect(x: box.minX * width,
                           y: tileY + (1 - box.maxY) * currentHeight,
                           width: box.width * width,
                           height: box.height * currentHeight)
                }
                let observations = request.results ?? []
                var read: [ScreenshotSupport.BandWord] = []
                for (line, observation) in observations.enumerated() {
                    let lineBox = imageRect(observation.boundingBox)
                    guard let candidate = observation.topCandidates(1).first else {
                        read.append(ScreenshotSupport.BandWord(text: "", rect: nil, lineBox: lineBox,
                                                               line: lineOffset + line))
                        continue
                    }
                    let text = candidate.string
                    var searchStart = text.startIndex
                    for raw in text.split(separator: " ") {
                        let word = String(raw)
                        guard let range = text.range(of: word,
                                                   range: searchStart..<text.endIndex)
                        else { continue }
                        searchStart = range.upperBound
                        let box = try? candidate.boundingBox(for: range)?.boundingBox
                        read.append(ScreenshotSupport.BandWord(
                            text: word,
                            rect: box.map(imageRect),
                            lineBox: lineBox,
                            line: lineOffset + line))
                    }
                }
                reads.append(read)
                lineOffset += observations.count
            }
            let merged = ScreenshotSupport.mergedRecognition(reads, tiles: tiles)
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                self.textWords = merged.words
                self.textRuns = merged.runs.map { $0 + (self.carriedRuns[ObjectIdentifier(image)] ?? []) }
            }
        }
    }

    func recognizeQRCodes() {
        let image = baseImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let current = self, image === current.baseImage else { return }
            let reading = BarcodeDetector.read(image)
            DispatchQueue.main.async { [weak self] in
                guard let self, image === self.baseImage else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.qrReading = reading
                }
            }
        }
    }

    // MARK: - Zoom

    static let zoomRange: ClosedRange<CGFloat> = 0.05...3

    func adjustZoom(by factor: CGFloat) {
        let current = zoomOverride ?? currentDisplayZoom
        zoomOverride = min(max(current * factor, Self.zoomRange.lowerBound),
                           Self.zoomRange.upperBound)
    }

    func setZoom(_ zoom: CGFloat) {
        zoomOverride = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    func pasteImage(_ image: CGImage) -> Bool {
        guard ScreenshotCanvasSupport.validSize(CGSize(width: image.width, height: image.height))
        else { return false }
        let annotation = ScreenshotSupport.Annotation(
            tool: .image,
            rect: ScreenshotCanvasSupport.fittedImageRect(image, canvas: imageSize),
            imageAsset: ScreenshotSupport.ImageAsset(image: image))
        registerUndo()
        clearTextSelection()
        tool = .select
        annotations.append(annotation)
        selectedID = annotation.id
        return true
    }

    func commitCanvasExpansion(to rect: CGRect) -> Bool {
        let oldSize = CGSize(width: baseImage.width, height: baseImage.height)
        guard rect != CGRect(origin: .zero, size: oldSize),
              let expanded = ScreenshotCanvasSupport.expandedImage(baseImage, to: rect, fill: expansionFill)
        else { return false }
        registerUndo()
        let oldBounds = CGRect(origin: .zero, size: oldSize)
        annotations = annotations.compactMap { annotation in
            var moved = annotation
            if moved.tool == .spotlight {
                let lit = moved.rect.standardized.intersection(oldBounds)
                guard !lit.isEmpty else { return nil }
                moved.rect = lit
            }
            moved.rect = moved.rect.offsetBy(dx: -rect.minX, dy: -rect.minY)
            moved.points = moved.points.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
            if moved.tool == .counter || moved.tool == .pixelate {
                moved.renderReferenceSize = moved.renderReferenceSize ?? oldSize
            }
            return moved
        }
        let previousRuns = textRuns
        baseImage = expanded
        if let previousRuns {
            carriedRuns[ObjectIdentifier(expanded)] =
                previousRuns.map { $0.offsetBy(dx: -rect.minX, dy: -rect.minY) }
        }
        pixelated = [:]
        softBlurred = [:]
        textRuns = nil
        textWords = []
        clearTextSelection()
        selectedID = nil
        editingTextID = nil
        cropDraft = nil
        pruneCarriedRuns()
        ensureBlurSamplesForAnnotations()
        recognizeText()
        recognizeQRCodes()
        return true
    }

    // MARK: - Undo

    private func registerUndo() {
        undoStack.append((baseImage, annotations))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        refreshUndoFlags()
        isDirty = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((baseImage, annotations))
        restore(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((baseImage, annotations))
        restore(next)
    }

    private func pruneCarriedRuns() {
        let live = Set([ObjectIdentifier(baseImage)] + (undoStack + redoStack).map { ObjectIdentifier($0.image) })
        carriedRuns = carriedRuns.filter { live.contains($0.key) }
    }

    private func restore(_ state: (image: CGImage, annotations: [ScreenshotSupport.Annotation])) {
        cancelCanvasExpansion()
        if state.image !== baseImage {
            baseImage = state.image
            pixelated = [:]
            softBlurred = [:]
            textRuns = nil
            clearTextSelection()
            recognizeText()
            recognizeQRCodes()
        }
        annotations = state.annotations
        ensureBlurSamplesForAnnotations()
        selectedID = nil
        editingTextID = nil
        newTextID = nil
        cropDraft = nil
        refreshUndoFlags()
        refreshDirtyState()
    }

    private func refreshUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func markExported() {
        recordCleanState()
    }

    private func recordCleanState() {
        cleanImage = baseImage
        cleanAnnotations = annotations
        cleanBackdropStyle = backdropStyle.sanitized()
        cleanWatermarkStyle = watermarkStyle.sanitized()
        cleanAnnotationShadowsEnabled = annotationShadowsEnabled
        cleanSpotlightDimStrength = spotlightDimStrength
        isDirty = false
    }

    private func refreshDirtyState() {
        guard let cleanImage else { return }
        isDirty = baseImage !== cleanImage
            || annotations != cleanAnnotations
            || backdropStyle.sanitized() != cleanBackdropStyle
            || watermarkStyle.sanitized() != cleanWatermarkStyle
            || annotationShadowsEnabled != cleanAnnotationShadowsEnabled
            || (spotlightDimStrength != cleanSpotlightDimStrength
                && annotations.contains { $0.tool == .spotlight })
    }

    // MARK: - Selection styling

    private func applyStyleToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        guard annotations[index].tool != .image else { return }
        let arrowStyleChanged = annotations[index].tool == .arrow
            && annotations[index].arrowStyle != arrowStyle
        let textSizeChanged = annotations[index].tool == .text
            && annotations[index].textSize != textSize
        let usesStroke = ScreenshotSupport.selectionStyle(for: annotations[index]).stroke != nil
        let strokeChanged = usesStroke && annotations[index].stroke != stroke
        guard annotations[index].color != color
                || strokeChanged
                || arrowStyleChanged
                || textSizeChanged
        else { return }
        registerUndo()
        annotations[index].color = color
        if usesStroke { annotations[index].stroke = stroke }
        if annotations[index].tool == .arrow {
            if arrowStyleChanged, arrowStyle == .scribbly {
                annotations[index].scribbleSeed = ScreenshotSupport.randomScribbleSeed()
            }
            annotations[index].arrowStyle = arrowStyle
        }
        if annotations[index].tool == .text {
            annotations[index].textSize = textSize
            annotations[index].rect = ScreenshotRenderer.textBounds(
                annotations[index].text,
                at: annotations[index].rect.origin,
                textSize: textSize,
                scale: scale)
        }
    }

    private func applyBlurToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .pixelate
        else { return }
        let mark = annotations[index]
        guard mark.blurLevel != blurLevel
                || mark.blurStyle != blurStyle
                || mark.blurTextOnly != blurTextOnly
        else { return }
        guard ensureBlurSample(blurStyle, level: blurLevel) else {
            self.selectedID = nil
            syncControls(to: mark)
            self.selectedID = selectedID
            return
        }
        registerUndo()
        annotations[index].blurLevel = blurLevel
        annotations[index].blurStyle = blurStyle
        annotations[index].blurTextOnly = blurTextOnly
        ensureBlurSamplesForAnnotations()
    }

    private func applyStickerToSelection() {
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID }),
              annotations[index].tool == .sticker,
              annotations[index].text != sticker.rawValue
        else { return }
        registerUndo()
        annotations[index].text = sticker.rawValue
    }

    private func syncControls(to annotation: ScreenshotSupport.Annotation) {
        let style = ScreenshotSupport.selectionStyle(for: annotation)
        if let color = style.color { self.color = color }
        if let stroke = style.stroke { self.stroke = stroke }
        if let textSize = style.textSize { self.textSize = textSize }
        if let blurLevel = style.blurLevel { self.blurLevel = blurLevel }
        if let blurStyle = style.blurStyle { self.blurStyle = blurStyle }
        if let blurTextOnly = style.blurTextOnly { self.blurTextOnly = blurTextOnly }
        if let arrowStyle = style.arrowStyle { self.arrowStyle = arrowStyle }
        if annotation.tool == .sticker {
            sticker = ScreenshotSupport.StickerID.sanitized(annotation.text)
        }
    }

    // MARK: - Gestures (image-pixel coordinates)

    func beginDrag(at point: CGPoint) {
        dragStart = point
        dragRegistered = false
        editingSelectedAnnotation = false
        if tool != .select, tool != .crop, tool != .expandCanvas,
           selectedAnnotationOwns(point, includingInterior: tool != .spotlight) {
            editingSelectedAnnotation = true
            beginSelectDrag(at: point)
            return
        }
        if tool != .select, tool != .crop, tool != .expandCanvas {
            selectedID = nil
        }
        switch tool {
        case .select:
            beginSelectDrag(at: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let draft = cropDraft,
               let handle = ScreenshotSupport.handle(at: point, rect: draft,
                                                     tolerance: 14 * scale) {
                activeHandle = handle
                cropResizeOrigin = draft
                cropLoupePoint = handle.position(in: draft)
            } else if let draft = cropDraft,
                      ScreenshotSupport.startsNewCropSelection(
                        at: point, draft: draft, within: bounds) {
                cropSelectionOrigin = draft
            } else if let draft = cropDraft, draft.contains(point) {
                cropMoveOrigin = draft
            }
        case .arrow, .line:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point, point], color: color, stroke: stroke,
                arrowStyle: arrowStyle)
            annotations.append(annotation)
            draftID = annotation.id
        case .freehand:
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, points: [point], color: color, stroke: stroke)
            annotations.append(annotation)
            draftID = annotation.id
        case .rect, .ellipse, .highlight, .pixelate, .redact, .spotlight:
            if tool == .pixelate { ensureBlurSample(blurStyle, level: blurLevel) }
            registerUndo()
            dragRegistered = true
            let annotation = ScreenshotSupport.Annotation(
                tool: tool, rect: CGRect(origin: point, size: .zero),
                color: color, stroke: stroke, blurLevel: blurLevel,
                blurStyle: blurStyle, blurTextOnly: blurTextOnly)
            annotations.append(annotation)
            draftID = annotation.id
        case .expandCanvas:
            expansionRejected = false
            expansionDraft = CGRect(origin: .zero, size: imageSize)
            expansionHandle = ScreenshotCanvasSupport.expansionHandle(at: point,
                rect: CGRect(origin: .zero, size: imageSize),
                tolerance: ScreenshotCanvasSupport.expansionGripReach / max(currentDisplayZoom, 0.001))
            expansionStartPoint = expansionHandle == nil ? nil : point
        case .text, .sticker, .counter, .image:
            break
        }
    }

    private func beginSelectDrag(at point: CGPoint) {
        if let selectedID,
           let selected = annotations.first(where: { $0.id == selectedID }) {
            let tolerance = 12 * scale
            if selected.tool.resizesWithHandles,
               let handle = selected.tool == .image
                    ? ScreenshotCanvasSupport.imageHandle(at: point, rect: selected.rect, tolerance: tolerance)
                    : ScreenshotSupport.handle(at: point, rect: selected.rect, tolerance: tolerance) {
                activeHandle = handle
                moveOrigin = selected.rect
                return
            }
            if selected.points.count >= 2 {
                if hypot(point.x - selected.points[0].x, point.y - selected.points[0].y) < tolerance {
                    activeHandle = .topLeft
                    movePoints = selected.points
                    return
                }
                if hypot(point.x - selected.points[1].x, point.y - selected.points[1].y) < tolerance {
                    activeHandle = .bottomRight
                    movePoints = selected.points
                    return
                }
            }
        }
        let hitID = hitTest(point)
        self.selectedID = nil
        if let hitID, let hit = annotations.first(where: { $0.id == hitID }) {
            syncControls(to: hit)
            self.selectedID = hitID
            moveOrigin = hit.rect
            movePoints = hit.points
            clearTextSelection()
        } else if let word = wordIndex(at: point) {
            textSelectionAnchor = point
            selectedWordIndexes = [word]
        }
    }

    func continueDrag(to point: CGPoint) {
        if editingSelectedAnnotation {
            continueSelectDrag(to: point)
            return
        }
        switch tool {
        case .select:
            continueSelectDrag(to: point)
        case .crop:
            let bounds = CGRect(origin: .zero, size: imageSize)
            if let handle = activeHandle, let origin = cropResizeOrigin {
                let rect = ScreenshotSupport.resizedRect(origin, dragging: handle, to: point)
                let snapped = ScreenshotSupport.pixelSnappedCropRect(rect, within: bounds)
                cropDraft = snapped
                cropLoupePoint = handle.position(in: snapped)
            } else if cropSelectionOrigin != nil {
                cropDraft = ScreenshotSupport.pixelSnappedCropRect(
                    ScreenshotSupport.selectionRect(from: dragStart, to: point),
                    within: bounds)
            } else if let origin = cropMoveOrigin {
                let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
                cropDraft = ScreenshotSupport.pixelSnappedCropRect(
                    ScreenshotSupport.movedRect(origin, by: delta, within: bounds),
                    within: bounds)
            }
        case .arrow, .line:
            updateDraft { $0.points = [dragStart, point] }
        case .freehand:
            updateDraft { $0.points.append(point) }
        case .rect, .ellipse, .highlight, .pixelate, .redact, .spotlight:
            updateDraft { $0.rect = ScreenshotSupport.selectionRect(from: dragStart, to: point) }
        case .expandCanvas:
            if let handle = expansionHandle, let start = expansionStartPoint {
                let anchor = handle.position(in: CGRect(origin: .zero, size: imageSize))
                let target = CGPoint(x: anchor.x + point.x - start.x, y: anchor.y + point.y - start.y)
                expansionDraft = ScreenshotCanvasSupport.expandedRect(size: imageSize, handle: handle, point: target)
                expansionRejected = expansionDraft == nil
            }
        case .text, .sticker, .counter, .image:
            break
        }
    }

    private func continueSelectDrag(to point: CGPoint) {
        if let anchor = textSelectionAnchor {
            selectedWordIndexes = ScreenshotSupport.wordSelection(
                anchor: anchor, current: point, boxes: textWords.map(\.rect))
            return
        }
        guard let selectedID,
              let index = annotations.firstIndex(where: { $0.id == selectedID })
        else { return }
        if !dragRegistered {
            registerUndo()
            dragRegistered = true
        }
        if let handle = activeHandle {
            if annotations[index].points.count >= 2 {
                var points = movePoints
                if handle == .topLeft { points[0] = point } else { points[1] = point }
                annotations[index].points = points
            } else {
                annotations[index].rect = annotations[index].tool == .image
                    ? ScreenshotCanvasSupport.resizedImageRect(moveOrigin, handle: handle, point: point)
                    : ScreenshotSupport.resizedRect(moveOrigin, dragging: handle, to: point)
            }
            return
        }
        let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
        if annotations[index].tool == .image {
            annotations[index].rect = CGRect(origin: CGPoint(x: (moveOrigin.minX + delta.x).rounded(),
                                                             y: (moveOrigin.minY + delta.y).rounded()),
                                             size: moveOrigin.size)
        } else if annotations[index].points.isEmpty {
            annotations[index].rect = moveOrigin.offsetBy(dx: delta.x, dy: delta.y)
        } else {
            annotations[index].points = movePoints.map {
                CGPoint(x: $0.x + delta.x, y: $0.y + delta.y)
            }
        }
    }

    func endDrag(at point: CGPoint, isTap: Bool) {
        defer {
            draftID = nil
            activeHandle = nil
            cropResizeOrigin = nil
            cropMoveOrigin = nil
            cropSelectionOrigin = nil
            cropLoupePoint = nil
            dragRegistered = false
            editingSelectedAnnotation = false
        }
        if editingSelectedAnnotation {
            finishSelectDrag(at: point, isTap: isTap)
            return
        }
        switch tool {
        case .text:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            var annotation = ScreenshotSupport.Annotation(
                tool: .text, color: color, stroke: stroke, textSize: textSize)
            annotation.rect = ScreenshotRenderer.textBounds("", at: point, textSize: textSize,
                                                            scale: scale)
            annotations.append(annotation)
            newTextID = annotation.id
            selectedID = annotation.id
            editingTextID = annotation.id
        case .sticker:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let bounds = CGRect(origin: .zero, size: imageSize)
            let side = ScreenshotSupport.stickerSide(for: imageSize, scale: scale)
            let annotation = ScreenshotSupport.Annotation(
                tool: .sticker,
                rect: ScreenshotSupport.stickerRect(centeredAt: point,
                                                     side: side,
                                                     within: bounds),
                text: sticker.rawValue,
                color: color,
                stroke: stroke)
            annotations.append(annotation)
            selectedID = annotation.id
        case .counter:
            guard isTap else { return }
            if selectExistingAnnotation(at: point) { return }
            registerUndo()
            let annotation = ScreenshotSupport.Annotation(
                tool: .counter,
                rect: CGRect(x: point.x, y: point.y, width: 0, height: 0),
                color: color, stroke: stroke, number: 1)
            annotations.append(annotation)
            annotations = ScreenshotSupport.renumberingCounters(annotations)
            selectedID = annotation.id
        case .arrow, .line, .rect, .ellipse, .highlight, .pixelate, .redact, .spotlight, .freehand:
            if isTap {
                annotations.removeAll { $0.id == draftID }
                if !undoStack.isEmpty { undoStack.removeLast() }
                refreshUndoFlags()
                refreshDirtyState()
                _ = selectExistingAnnotation(at: point)
            } else if let draftID {
                selectedID = draftID
            }
        case .expandCanvas:
            if expansionRejected {
                NSSound.beep()
            } else if let draft = expansionDraft, draft.size != imageSize {
                if !commitCanvasExpansion(to: draft) { NSSound.beep() }
            }
            cancelCanvasExpansion()
        case .image:
            break
        case .select:
            finishSelectDrag(at: point, isTap: isTap)
        case .crop:
            if isTap, let origin = cropSelectionOrigin {
                cropDraft = origin
            }
        }
    }

    func selectedAnnotationOwns(_ point: CGPoint, includingInterior: Bool = true) -> Bool {
        guard let selectedID,
              let selected = annotations.first(where: { $0.id == selectedID })
        else { return false }
        let tolerance = 12 * scale
        if selected.tool.resizesWithHandles,
           (selected.tool == .image
                ? ScreenshotCanvasSupport.imageHandle(at: point, rect: selected.rect, tolerance: tolerance)
                : ScreenshotSupport.handle(at: point, rect: selected.rect, tolerance: tolerance)) != nil {
            return true
        }
        if selected.points.prefix(2).contains(where: {
            hypot(point.x - $0.x, point.y - $0.y) < tolerance
        }) {
            return true
        }
        return hitTest(point, includeShapeInteriors: includingInterior) == selectedID
    }

    private func finishSelectDrag(at point: CGPoint, isTap: Bool) {
        textSelectionAnchor = nil
        guard isTap, !dragRegistered else { return }
        let hitID = hitTest(point)
        self.selectedID = nil
        if let hitID, let hit = annotations.first(where: { $0.id == hitID }) {
            syncControls(to: hit)
            self.selectedID = hitID
            editingTextID = hit.tool == .text ? hitID : nil
            clearTextSelection()
        } else if let word = wordIndex(at: point) {
            selectedWordIndexes = [word]
        } else {
            clearTextSelection()
        }
    }

    @discardableResult
    private func selectExistingAnnotation(at point: CGPoint) -> Bool {
        guard let hitID = hitTest(point, includeShapeInteriors: false),
              let hit = annotations.first(where: { $0.id == hitID })
        else {
            selectedID = nil
            return false
        }
        self.selectedID = nil
        syncControls(to: hit)
        selectedID = hitID
        editingTextID = hit.tool == .text ? hitID : nil
        clearTextSelection()
        tool = .select
        return true
    }

    private func updateDraft(_ mutate: (inout ScreenshotSupport.Annotation) -> Void) {
        guard let draftID,
              let index = annotations.firstIndex(where: { $0.id == draftID })
        else { return }
        mutate(&annotations[index])
    }

    func hitTest(_ point: CGPoint, includeShapeInteriors: Bool = true) -> UUID? {
        let tolerance = 10 * scale
        for annotation in annotations.reversed() {
            switch annotation.tool {
            case .arrow, .line:
                guard annotation.points.count >= 2 else { continue }
                if ScreenshotSupport.distance(from: point,
                                              toSegment: annotation.points[0],
                                              annotation.points[1])
                    <= tolerance + annotation.stroke.width * scale / 2 {
                    return annotation.id
                }
            case .freehand:
                for pathPoint in annotation.points
                where hypot(point.x - pathPoint.x, point.y - pathPoint.y) <= tolerance {
                    return annotation.id
                }
            case .counter:
                let radius = ScreenshotSupport.counterDiameter(for: annotation.renderReferenceSize ?? imageSize, scale: 1) / 2
                if hypot(point.x - annotation.rect.midX, point.y - annotation.rect.midY)
                    <= radius + 4 * scale {
                    return annotation.id
                }
        case .rect, .ellipse, .highlight, .pixelate, .redact, .spotlight:
                let outer = annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                guard outer.contains(point) else { continue }
                if includeShapeInteriors {
                    return annotation.id
                }
                let inner = annotation.rect.insetBy(dx: tolerance, dy: tolerance)
                if inner.isEmpty || inner.width <= 0 || inner.height <= 0
                    || !inner.contains(point) {
                    return annotation.id
                }
            case .image:
                if includeShapeInteriors,
                   annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point) {
                    return annotation.id
                }
            case .text, .sticker:
                if annotation.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                    .contains(point) {
                    return annotation.id
                }
            case .select, .crop, .expandCanvas:
                continue
            }
        }
        return nil
    }

    func cancelCanvasExpansion() {
        expansionDraft = nil
        expansionHandle = nil
        expansionStartPoint = nil
        expansionRejected = false
    }

    func leaveCanvasExpansion() {
        if expansionDraft != nil || expansionRejected {
            cancelCanvasExpansion()
        } else {
            tool = .select
        }
    }

    // MARK: - Edits

    func deleteSelected() {
        guard let selectedID else { return }
        guard annotations.contains(where: { $0.id == selectedID }) else { return }
        registerUndo()
        annotations.removeAll { $0.id == selectedID }
        annotations = ScreenshotSupport.renumberingCounters(annotations)
        self.selectedID = nil
        editingTextID = nil
        if newTextID == selectedID { newTextID = nil }
    }

    func moveSelected(_ move: ScreenshotSupport.LayerMove) {
        guard let selectedID else { return }
        let reordered = ScreenshotSupport.reordering(annotations, moving: selectedID, move)
        guard reordered.map(\.id) != annotations.map(\.id) else { return }
        registerUndo()
        annotations = ScreenshotSupport.renumberingCounters(reordered)
    }

    func commitText(_ id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        editingTextID = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = newTextID == id
        if isNew, trimmed.isEmpty {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
            while let last = undoStack.last,
                  last.annotations.contains(where: { $0.id == id }) {
                undoStack.removeLast()
            }
            if !undoStack.isEmpty { undoStack.removeLast() }
            newTextID = nil
            refreshUndoFlags()
            refreshDirtyState()
            return
        }
        guard annotations[index].text != trimmed else {
            newTextID = nil
            return
        }
        if !isNew { registerUndo() }
        guard !trimmed.isEmpty else {
            annotations.remove(at: index)
            if selectedID == id { selectedID = nil }
            return
        }
        annotations[index].text = trimmed
        annotations[index].rect = ScreenshotRenderer.textBounds(
            trimmed,
            at: annotations[index].rect.origin,
            textSize: annotations[index].textSize,
            scale: scale)
        newTextID = nil
    }

    func applyCrop() {
        guard let draft = cropDraft else {
            tool = .select
            return
        }
        let cropRect = ScreenshotSupport.pixelSnappedCropRect(
            draft,
            within: CGRect(origin: .zero, size: imageSize))
        guard cropRect.width >= 8, cropRect.height >= 8,
              let cropped = baseImage.cropping(to: cropRect)
        else {
            tool = .select
            return
        }
        registerUndo()
        let previousImage = baseImage
        baseImage = cropped
        pixelated = [:]
        softBlurred = [:]
        clearTextSelection()
        let croppedBounds = CGRect(origin: .zero, size: CGSize(width: cropped.width,
                                                               height: cropped.height))
        textWords = textWords.compactMap { word in
            let moved = word.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            guard moved.intersects(croppedBounds) else { return nil }
            return ScreenshotSupport.RecognizedWord(text: word.text, rect: moved, line: word.line)
        }
        let previousCarried = carriedRuns[ObjectIdentifier(previousImage)]
        textRuns = ScreenshotSupport.croppedRuns(textRuns, by: cropRect)
        if let carried = textRuns ?? ScreenshotSupport.croppedRuns(previousCarried, by: cropRect), !carried.isEmpty {
            carriedRuns[ObjectIdentifier(cropped)] = carried
        }
        pruneCarriedRuns()
        annotations = annotations.map { annotation in
            var moved = annotation
            moved.rect = annotation.rect.offsetBy(dx: -cropRect.minX, dy: -cropRect.minY)
            moved.points = annotation.points.map {
                CGPoint(x: $0.x - cropRect.minX, y: $0.y - cropRect.minY)
            }
            return moved
        }
        ensureBlurSamplesForAnnotations()
        cropDraft = nil
        selectedID = nil
        tool = .select
        recognizeText()
        recognizeQRCodes()
    }

    // MARK: - Output

    func exportImage(withBackdrop: Bool = true) -> ScreenshotRenderer.Export? {
        ensureBlurSamplesForAnnotations()
        let downscale = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotDownscale)
        return ScreenshotRenderer.renderExport(
            baseImage: baseImage,
            annotations: annotations,
            blurSources: blurSources,
            scale: scale,
            annotationShadowsEnabled: annotationShadowsEnabled,
            watermark: watermarkStyle,
            watermarkImage: watermarkImage,
            style: backdropStyle.sanitized(),
            fill: withBackdrop ? backdropFill : .none,
            downscaleTo1x: downscale,
            spotlightDimStrength: spotlightDimStrength)
    }

    @discardableResult
    private func ensureBlurSample(_ style: ScreenshotSupport.BlurStyleID, level: Int) -> Bool {
        switch style {
        case .pixelate:
            if pixelated[level] == nil {
                pixelated[level] = ScreenshotRenderer.pixelatedImage(from: baseImage, level: level)
            }
            return pixelated[level] != nil
        case .blur:
            if softBlurred[level] == nil {
                softBlurred[level] = ScreenshotRenderer.softBlurredImage(from: baseImage, level: level)
            }
            return softBlurred[level] != nil
        case .erase:
            return true
        }
    }

    private func ensureBlurSamplesForAnnotations() {
        let mosaicLevels = ScreenshotSupport.mosaicLevels(for: annotations)
        let softBlurLevels = ScreenshotSupport.softBlurLevels(for: annotations)
        pixelated = pixelated.filter { mosaicLevels.contains($0.key) }
        softBlurred = softBlurred.filter { softBlurLevels.contains($0.key) }
        for level in mosaicLevels { ensureBlurSample(.pixelate, level: level) }
        for level in softBlurLevels { ensureBlurSample(.blur, level: level) }
    }
}

// MARK: - Window controller

final class ScreenshotEditorController: NSObject, NSWindowDelegate {
    let model: ScreenshotEditorModel
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var pointerMonitor: Any?

    var protectedWindowIDs: Set<CGWindowID> {
        guard let window, window.isVisible, window.windowNumber > 0 else { return [] }
        return [CGWindowID(window.windowNumber)]
    }
    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    init(capture: ScreenshotSelectionController.Capture) {
        model = ScreenshotEditorModel(image: capture.image, scale: capture.scale)
        super.init()
    }

    func show() {
        let screen = NSScreen.pointerVisibleFrame
        let minimumSize = ScreenshotSupport.editorMinimumContentSize(visibleSize: screen.size)
        let content = ScreenshotEditorView(model: model, controller: self)
            .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        window.title = strings.editorTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let contentSize = ScreenshotSupport.editorContentSize(
            imagePointSize: model.pointSize,
            visibleSize: screen.size)
        window.setContentSize(contentSize)
        window.center()

        self.window = window
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible == true else { return }
            self.model.recognizeText()
            self.model.recognizeQRCodes()
        }
    }

    func close() {
        window?.close()
    }

    func discardAndClose() {
        window?.close()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow)
            else { return event }
            if ShortcutCapture.isCapturing { return event }
            if window.firstResponder is NSText || self.model.editingTextID != nil {
                return event
            }
            return self.handleKey(event) ? nil : event
        }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            if let self, let window = self.window, event.windowNumber == window.windowNumber {
                self.model.notePointerActivity()
            }
            return event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow),
                  event.modifierFlags.contains(.control)
            else { return event }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return nil }
            let clamped = max(-24, min(24, delta))
            self.model.adjustZoom(by: 1 + clamped * 0.014)
            return nil
        }
    }

    private func pasteImageFromClipboard() {
        GeneralPasteboardAccess.shared.async({
            autoreleasepool {
                ScreenshotService.clipboardImage(from: .general)
                    .flatMap { ScreenshotService.imageCapture(from: $0) }
            }
        }) { [weak self] capture in
            guard let self, self.window != nil else { return }
            guard let capture, self.model.pasteImage(capture.image) else {
                NSSound.beep()
                return
            }
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = Int(event.keyCode)
        if ScreenshotSupport.editorIgnoresRepeatedOutputKey(
            keyCode: key, command: flags.contains(.command), isRepeat: event.isARepeat) {
            return true
        }

        let orderRaw = UserDefaults.standard.string(forKey: DefaultsKey.screenshotToolOrder)
        let bindingsRaw = UserDefaults.standard.string(forKey: DefaultsKey.screenshotToolShortcuts)
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.screenshotToolShortcutsEnabled)
        let number = event.characters?.first.flatMap { Int(String($0)) }
        if let tool = ScreenshotSupport.Tool.shortcutTool(
            keyCode: Int64(key), modifiers: GlobalShortcutModifiers(eventFlags: flags),
            number: number, orderRaw: orderRaw, bindingsRaw: bindingsRaw, enabled: enabled,
            capsLockOn: flags.contains(.capsLock)) {
            model.tool = tool
            return true
        }

        if flags.contains(.command) {
            switch key {
            case kVK_ANSI_C:
                if !model.selectedWordIndexes.isEmpty {
                    copySelectedText()
                } else if !ScreenshotSupport.editorIgnoresPostedCopy(
                    sourceProcessID: event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0,
                    ownProcessID: Int64(getpid()),
                    now: ProcessInfo.processInfo.systemUptime,
                    lastPointerActivity: model.lastPointerActivityUptime) {
                    copyToClipboard()
                }
                return true
            case kVK_ANSI_V: pasteImageFromClipboard(); return true
            case kVK_ANSI_S:
                if flags.contains(.shift) { saveAs() } else { save() }
                return true
            case kVK_ANSI_Z:
                if flags.contains(.shift) { model.redo() } else { model.undo() }
                return true
            case kVK_ANSI_P: pin(); return true
            case kVK_Delete, kVK_ForwardDelete:
                discardAndClose()
                return true
            case kVK_ANSI_0: model.zoomOverride = nil; return true
            case kVK_ANSI_1: model.zoomOverride = 1 / model.scale; return true
            case kVK_ANSI_Equal: model.adjustZoom(by: 1.25); return true
            case kVK_ANSI_Minus: model.adjustZoom(by: 0.8); return true
            default:
                return false
            }
        }
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return false }

        switch key {
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelected()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.tool == .crop, model.cropDraft != nil {
                model.applyCrop()
            } else {
                copyToClipboard()
            }
            return true
        case kVK_Escape:
            if model.tool == .expandCanvas {
                model.leaveCanvasExpansion()
            } else if model.tool == .crop, model.cropDraft != nil {
                model.tool = .select
            } else if !model.selectedWordIndexes.isEmpty {
                model.clearTextSelection()
            } else if model.selectedID != nil {
                model.selectedID = nil
            } else {
                window?.performClose(nil)
            }
            return true
        default:
            return false
        }
    }

    // MARK: Export actions

    func share(duration: ScreenshotShareDuration,
               completion: @escaping (ScreenshotShareRecord?) -> Void) {
        guard let export = model.exportImage() else {
            QuickToolHUD.show(icon: "link", message: strings.shareFailedHUD)
            completion(nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            }.value
            guard let data else {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                completion(nil)
                return
            }
            guard self.window != nil,
                  AppFeature.screenshot.isAvailable,
                  UserDefaults.standard.bool(forKey: DefaultsKey.screenshotSharingEnabled) else {
                completion(nil)
                return
            }
            do {
                let record = try await ScreenshotShareService.shared.createLink(
                    pngData: data, duration: duration)
                guard self.window != nil,
                      AppFeature.screenshot.isAvailable,
                      UserDefaults.standard.bool(forKey: DefaultsKey.screenshotSharingEnabled) else {
                    try? await ScreenshotShareService.shared.delete(record)
                    completion(nil)
                    return
                }
                self.model.markExported()
                completion(record)
            } catch {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                NSSound.beep()
                completion(nil)
            }
        }
    }

    func shareFile() -> URL? {
        guard let export = model.exportImage() else { return nil }
        return ScreenshotService.temporaryExportFile(image: export.image, scale: export.scale,
                                                     strings: strings)
    }

    func copyToClipboard() {
        guard let export = model.exportImage() else { return }
        guard Self.copyImage(export, fileNamePrefix: strings.fileNamePrefix) else {
            NSSound.beep()
            return
        }
        model.markExported()
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        window?.close()
    }

    @discardableResult
    static func copyImage(_ export: ScreenshotRenderer.Export, fileNamePrefix: String) -> Bool {
        guard let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return false }
        let payload = clipboardPayload(from: export, png: data)
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotCopyImageOnly) {
            return copyClipboardPayload(payload)
        }
        guard let folder = ScreenshotSupport.copiedFilesDirectory() else { return false }
        let name = ScreenshotSupport.fileName(prefix: fileNamePrefix, date: Date())
        guard let url = try? ScreenshotSupport.copiedFile(data: data, name: name,
                                                         directory: folder) else {
            return false
        }
        guard copyFile(url, payload: payload, imageOnly: false) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        ScreenshotSupport.pruneCopiedFiles(in: folder, preserving: url)
        return true
    }

    @discardableResult
    static func copyFile(_ url: URL?, payload: ClipboardPayload,
                         imageOnly: Bool = UserDefaults.standard.bool(
                            forKey: DefaultsKey.screenshotCopyImageOnly)) -> Bool {
        if imageOnly { return copyClipboardPayload(payload) }
        guard let url else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL) else { return false }
        if let png = payload.png {
            item.setData(png, forType: .png)
        }
        if let tiff = payload.tiff {
            item.setData(tiff, forType: .tiff)
        }
        guard pasteboard.writeObjects([item]) else { return false }
        pasteboard.declareVorssaintSource()
        return true
    }

    struct ClipboardPayload: Sendable {
        let png: Data?
        let tiff: Data?
    }

    static func clipboardPayload(from export: ScreenshotRenderer.Export) -> ClipboardPayload {
        clipboardPayload(from: export,
                         png: ScreenshotRenderer.pngData(from: export.image, scale: export.scale))
    }

    static func clipboardPayload(from export: ScreenshotRenderer.Export,
                                 png: Data?) -> ClipboardPayload {
        ClipboardPayload(png: png,
                         tiff: ScreenshotRenderer.tiffData(from: export.image, scale: export.scale))
    }

    @discardableResult
    static func copyClipboardPayload(_ payload: ClipboardPayload) -> Bool {
        guard payload.png != nil || payload.tiff != nil else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = payload.png {
            item.setData(png, forType: .png)
        }
        if let tiff = payload.tiff {
            item.setData(tiff, forType: .tiff)
        }
        guard pasteboard.writeObjects([item]) else { return false }
        pasteboard.declareVorssaintSource()
        return true
    }

    func save() {
        guard let export = model.exportImage(),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return }
        let (url, consumedNumber) = ScreenshotService.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            ScreenshotSupport.markAsScreenCapture(url)
            model.markExported()
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            window?.close()
        } catch {
            if let consumedNumber {
                ScreenshotService.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
        }
    }

    func saveAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotSupport.fileName(
            prefix: strings.fileNamePrefix, date: Date())
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let export = self.model.exportImage(),
                  let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.model.markExported()
                self.window?.close()
            } catch {
                NSSound.beep()
            }
        }
    }

    func addToShelf() {
        guard let export = model.exportImage(),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return }
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        guard ShelfService.shared.shelveGeneratedFile(data, named: name) != nil else {
            NSSound.beep()
            return
        }
        model.markExported()
        QuickToolHUD.show(icon: "tray.full", message: L10n.shared.s.shelfName)
        window?.close()
    }

    func pin() {
        guard let export = model.exportImage(withBackdrop: false) else { return }
        ScreenshotPinController.shared.pin(image: export.image, scale: export.scale)
        model.markExported()
    }

    func copySelectedText() {
        let text = model.selectedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(text, forType: .string)
        QuickToolHUD.show(icon: "text.viewfinder", message: L10n.shared.s.ocrCopied)
    }

    func showQRResult() {
        guard let reading = model.qrReading else { return }
        QRResultController.shared.show(reading: reading)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = strings.discardTitle
        alert.informativeText = strings.discardMessage
        alert.addButton(withTitle: strings.discardConfirm)
        alert.addButton(withTitle: strings.cancel)
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.delegate = nil
        window = nil
        ScreenshotService.shared.editorDidClose(self)
    }
}
