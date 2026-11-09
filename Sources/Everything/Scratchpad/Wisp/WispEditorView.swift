import SwiftUI

enum FontSize: String, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    static let fixed = FontSize.small

    var pointSize: CGFloat { 14 }

    var next: FontSize {
        let all = FontSize.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = "" {
        didSet {
            let parsed = text.extractHeadings()
            headingOffsets = parsed.map(\.lineStart)
            if !parsed.map({ [$0.name, String($0.level)] }).elementsEqual(headings.map({ [$0.name, String($0.level)] })) {
                headings = parsed
            }
            scheduleWordCount()
            guard didLoad, !isReloading else { return }
            scheduleSave()
        }
    }
    @Published private(set) var headings: [Heading] = []
    private var headingOffsets: [Int] = []
    @Published private(set) var wordCount: Int = 0
    @Published private(set) var notice: String?
    @Published var focusToken: Int = 0
    @Published var scrollToken: Int = 0
    private(set) var scrollTarget: Int = 0
    @Published private(set) var placeholder: String = ""
    @Published var showHelp: Bool = false
    @Published var showHotKeyCapture: Bool = false
    @Published var showFirstRunHint: Bool = false
    @Published private(set) var newTips: [Tip] = []
    @Published private(set) var hasUnseenTips: Bool = false
    @Published var showTour: Bool = false
    @Published var updateDismissed: Bool = false
    @Published private(set) var saveFailed: Bool = false

    // MARK: Find
    @Published var showFind: Bool = false
    @Published var findQuery: String = "" {
        didSet {
            guard didLoad, showFind else { return }
            recomputeMatches(resetIndex: true)
        }
    }
    @Published private(set) var findMatchCount: Int = 0
    @Published private(set) var findCurrentDisplayIndex: Int = 0
    @Published var findHighlightToken: Int = 0
    private(set) var findHighlightRange = NSRange(location: 0, length: 0)
    private var findMatches: [NSRange] = []
    private var findIndex = 0


    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    @Published var fontSize: FontSize = .medium {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(fontSize.rawValue, forKey: "wisp.FontSize")
        }
    }
    @Published var fontFace: FontFace = .sanFrancisco {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(fontFace.rawValue, forKey: "wisp.FontFace")
        }
    }
    @Published var dismissOnOutsideClick: Bool = false {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(dismissOnOutsideClick, forKey: "wisp.DismissOnOutsideClick")
            onDismissPreferenceChange?()
        }
    }
    var onDismissPreferenceChange: (@MainActor () -> Void)?

    @Published var opensOnPointerScreen: Bool = false {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(opensOnPointerScreen, forKey: "wisp.OpensOnPointerScreen")
        }
    }

    @Published private(set) var reduceTransparency =
        PerformanceMode.reduceTransparency {
        didSet { onChromeChange?() }
    }

    var effectiveTransparency: Transparency {
        reduceTransparency ? .off : transparency
    }

    @Published var transparency: Transparency = .subtle {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(transparency.rawValue, forKey: "wisp.Transparency")
            onChromeChange?()
        }
    }
    @Published var themePreference: ThemePreference = .system {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(themePreference.rawValue, forKey: "wisp.Theme")
            theme = .dark
        }
    }

    @Published private(set) var theme: WispTheme = .dark {
        didSet {
            onChromeChange?()
        }
    }

    var onChromeChange: (@MainActor () -> Void)?

    private var appearanceObservation: NSKeyValueObservation?
    private var accessibilityObserver: NSObjectProtocol?

    private var didLoad = false
    private var saveTask: Task<Void, Never>?
    private var wordCountTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var isReloading = false
    private var lastLoadedMTime: Date?
    private var lastSavedText: String = ""

    init() {
        if let saved = UserDefaults.standard.string(forKey: "wisp.Theme"),
           let pref = ThemePreference(rawValue: saved) {
            themePreference = pref
        }
        theme = .dark
        appearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.systemAppearanceMaybeChanged() }
        }
        if let saved = UserDefaults.standard.string(forKey: "wisp.FontSize"),
           let f = FontSize(rawValue: saved) {
            fontSize = f
        }
        if let saved = UserDefaults.standard.string(forKey: "wisp.FontFace"),
           let face = FontFace(rawValue: saved) {
            fontFace = face
        }
        if let saved = UserDefaults.standard.string(forKey: "wisp.Transparency"),
           let level = Transparency(rawValue: saved) {
            transparency = level
        }
        dismissOnOutsideClick = UserDefaults.standard.bool(forKey: "wisp.DismissOnOutsideClick")
        opensOnPointerScreen = UserDefaults.standard.bool(forKey: "wisp.OpensOnPointerScreen")
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceTransparency = PerformanceMode.reduceTransparency
            }
        }
        let hasSeenTour = UserDefaults.standard.bool(forKey: "wisp.HasSeenFirstRunTour")
        showFirstRunHint = !hasSeenTour
        if hasSeenTour {
            newTips = Tips.unseen(
                since: UserDefaults.standard.string(forKey: Tips.seenKey)
            )
            hasUnseenTips = !newTips.isEmpty
        } else {
            UserDefaults.standard.set(Tips.version, forKey: Tips.seenKey)
        }
        let url = StorageLocation.currentURL
        if let loaded = try? String(contentsOf: url, encoding: .utf8) {
            text = loaded
            lastSavedText = loaded
            lastLoadedMTime = Self.fileMTime(at: url)
        } else {
            StorageLocation.startDownloadIfPlaceholder()
        }
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        wordCountTask?.cancel()
        wordCount = Self.countWords(text)
        didLoad = true
        let loadedText = text
        Task.detached(priority: .background) {
            Snapshots.recordCheckpoint(text: loadedText)
        }
    }

    func saveAndCheckpoint() {
        saveNow()
        let snapshot = text
        Task.detached(priority: .background) {
            Snapshots.recordCheckpoint(text: snapshot)
        }
    }

    enum ReloadDecision: Equatable {
        case skipNotNewer
        case skipUnsavedEdits
        case reload
    }

    nonisolated static func decideReload(
        fileMTime: Date,
        lastLoadedMTime: Date?,
        text: String,
        lastSavedText: String
    ) -> ReloadDecision {
        if let last = lastLoadedMTime, fileMTime <= last { return .skipNotNewer }
        guard text == lastSavedText else { return .skipUnsavedEdits }
        return .reload
    }

    func reloadFromDiskIfChanged() {
        let url = StorageLocation.currentURL
        guard let mtime = Self.fileMTime(at: url) else {
            StorageLocation.startDownloadIfPlaceholder()
            return
        }
        switch Self.decideReload(
            fileMTime: mtime,
            lastLoadedMTime: lastLoadedMTime,
            text: text,
            lastSavedText: lastSavedText
        ) {
        case .skipNotNewer:
            return
        case .skipUnsavedEdits:
            lastLoadedMTime = mtime
            return
        case .reload:
            break
        }
        guard let loaded = try? String(contentsOf: url, encoding: .utf8) else { return }
        if loaded != text {
            isReloading = true
            text = loaded
            isReloading = false
        }
        lastSavedText = loaded
        lastLoadedMTime = mtime
    }

    func adoptLoadedText(_ newText: String) {
        isReloading = true
        text = newText
        isReloading = false
        lastSavedText = newText
        lastLoadedMTime = Self.fileMTime(at: StorageLocation.currentURL)
    }

    nonisolated private static func fileMTime(at url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func cycleFontSize() {
        fontSize = fontSize.next
        requestFocus()
    }


    func cycleTheme() {
        themePreference = themePreference.next
        requestFocus()
    }

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private nonisolated static let taskMarker = try! NSRegularExpression(pattern: #"(?m)^[ \t]*[-*+] \[[ xX]\]"#)

    nonisolated static func countWords(_ text: String) -> Int {
        // A task's `[x]` is a checkbox, not a word.
        let text = taskMarker.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private func scheduleWordCount() {
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.wordCount = Self.countWords(self.text)
        }
    }

    private func systemAppearanceMaybeChanged() {
        guard themePreference == .system else { return }
        let resolved = themePreference.resolve()
        _ = resolved
    }

    func jumpTo(_ heading: Heading) {
        guard let index = headings.firstIndex(of: heading), index < headingOffsets.count else { return }
        scrollTarget = headingOffsets[index]
        scrollToken &+= 1
    }

    // MARK: Find

    func openFind() {
        showFind = true
        recomputeMatches(resetIndex: true)
    }

    func closeFind() {
        showFind = false
        clearFindHighlight()
        requestFocus()
    }

    func findNext() {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + 1) % findMatches.count
        navigateToCurrentMatch()
    }

    func findPrevious() {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex - 1 + findMatches.count) % findMatches.count
        navigateToCurrentMatch()
    }

    private func recomputeMatches(resetIndex: Bool) {
        findMatches = TextSearch.matches(in: text, query: findQuery)
        findMatchCount = findMatches.count
        if resetIndex { findIndex = 0 }
        if findIndex >= findMatches.count { findIndex = max(0, findMatches.count - 1) }
        if findMatches.isEmpty {
            findCurrentDisplayIndex = 0
            clearFindHighlight()
        } else {
            navigateToCurrentMatch()
        }
    }

    private func navigateToCurrentMatch() {
        guard findIndex < findMatches.count else { return }
        findCurrentDisplayIndex = findIndex + 1
        findHighlightRange = findMatches[findIndex]
        findHighlightToken &+= 1
    }

    private func clearFindHighlight() {
        findHighlightRange = NSRange(location: 0, length: 0)
        findHighlightToken &+= 1
    }

    func refreshPlaceholder() {
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
    }

    func openHelp() {
        showHelp = true
        guard hasUnseenTips else { return }
        hasUnseenTips = false
        UserDefaults.standard.set(Tips.version, forKey: Tips.seenKey)
    }

    func closeHelp() {
        showHelp = false
    }

    func openTour() {
        showTour = true
    }

    func dismissTour() {
        showTour = false
        showFirstRunHint = false
        UserDefaults.standard.set(true, forKey: "wisp.HasSeenFirstRunTour")
    }

    func flushSave() {
        saveNow()
        Snapshots.recordCheckpoint(text: text)
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard didLoad else { return }
        let newText = text
        guard newText != lastSavedText || saveFailed else { return }
        Snapshots.recordOnSave(old: lastSavedText, new: newText)
        do {
            try Self.write(newText)
            lastSavedText = newText
            lastLoadedMTime = Self.fileMTime(at: StorageLocation.currentURL)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    nonisolated private static func write(_ text: String) throws {
        let url = StorageLocation.currentURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    var hotKeyDisplay: String = ""
    var showsHeader = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if showsHeader {
                    HeaderBar(headings: model.headings) { heading in
                        model.jumpTo(heading)
                    }
                }
                ZStack(alignment: .topLeading) {
                    MinimalTextEditor(
                        text: $model.text,
                        focusToken: model.focusToken,
                        scrollToken: model.scrollToken,
                        scrollTarget: model.scrollTarget,
                        findHighlightToken: model.findHighlightToken,
                        findHighlightRange: model.findHighlightRange,
                        fontSize: model.fontSize,
                        fontFace: model.fontFace,
                        theme: model.theme,
                        transparency: model.effectiveTransparency
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    if model.text.isEmpty {
                        Text(model.placeholder)
                            .font(Font(editorFont as CTFont))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                            .padding(.top, firstLineLead)
                            .frame(maxWidth: model.fontSize.pointSize * 34, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.horizontal, 10)
                            .padding(.top, 2)
                    }
                }
                if !showsHeader {
                    if !model.headings.isEmpty {
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
                    }
                    HeaderBar(headings: model.headings) { heading in
                        model.jumpTo(heading)
                    }
                } else {
                BottomBar(
                    wordCount: model.wordCount,
                    notice: model.notice,
                    saveFailed: model.saveFailed,
                    fontSize: model.fontSize,
                    onCycleFontSize: { model.cycleFontSize() },
                    themePreference: model.themePreference,
                    onCycleTheme: { model.cycleTheme() },
                    hasUnseenTips: model.hasUnseenTips,
                    onHelpClick: {
                        withAnimation(overlayAnimation) {
                            if model.showHelp {
                                model.closeHelp()
                            } else {
                                model.openHelp()
                            }
                        }
                    }
                )
                }
            }
            if model.showHelp {
                HelpOverlay(theme: model.theme, hotKey: hotKeyDisplay, newTips: model.newTips) {
                    withAnimation(overlayAnimation) {
                        model.closeHelp()
                    }
                }
                .transition(overlayTransition)
            }
            if model.showFind {
                FindBar(
                    theme: model.theme,
                    query: $model.findQuery,
                    matchCount: model.findMatchCount,
                    currentIndex: model.findCurrentDisplayIndex,
                    onNext: { model.findNext() },
                    onPrev: { model.findPrevious() },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            model.closeFind()
                        }
                    }
                )
                .padding(.top, 12)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var editorFont: NSFont {
        MinimalTextEditor.makeFont(face: model.fontFace, size: model.fontSize.pointSize)
    }

    private var firstLineLead: CGFloat {
        let natural = NSLayoutManager().defaultLineHeight(for: editorFont)
        return (natural * (MarkdownStyler.lineHeightMultiple - 1)).rounded()
    }

    private var overlayAnimation: Animation {
        .spring(response: 0.3, dampingFraction: 0.9)
    }

    private var overlayTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }
}
