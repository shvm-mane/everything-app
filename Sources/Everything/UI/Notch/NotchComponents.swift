// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var lifts = true
    var highlights = true
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let active = enabled && hovered
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(active && highlights ? 0.09 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(reduceMotion || !lifts ? 1
                         : configuration.isPressed ? 0.965 : (active ? 1.022 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension NotchArtworkTint {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

struct NotchLiveEqualizerBars: View {
    var isPlaying = true
    var bars = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14
    var tint: Color = .white
    @ObservedObject private var audio = NotchAudioLevelService.shared

    var body: some View {
        NotchEqualizerBars(isPlaying: isPlaying, bars: bars, barWidth: barWidth, height: height, tint: tint,
                           live: audio.levels)
    }
}

struct NotchMeter: View {
    let value: Double
    var height: CGFloat = 5
    var tint: Color = .white

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.9))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct NotchRollingDigits: ViewModifier {
    let value: String
    let countsDown: Bool
    var everySecond = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText(countsDown: countsDown))
            .animation(reduceMotion ? nil : .smooth(duration: 0.3),
                       value: NotchTimerSupport.rollingValue(value, everySecond: everySecond))
    }
}

struct NotchStripHold<Value: Equatable, Content: View>: View {
    private let value: Value
    private let shows: Bool
    private let content: (Value) -> Content
    @State private var held: Value

    init(_ value: Value, shows: Bool, @ViewBuilder content: @escaping (Value) -> Content) {
        self.value = value
        self.shows = shows
        self.content = content
        _held = State(initialValue: value)
    }

    var body: some View {
        content(shows ? value : held)
            .onChange(of: value) { _, value in
                if shows { held = value }
            }
    }
}

struct NotchFadeThrough: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(max(0, progress * 2 - 1))
    }
}

extension AnyTransition {
    static var notchFadeThrough: AnyTransition {
        .modifier(active: NotchFadeThrough(progress: 0), identity: NotchFadeThrough(progress: 1))
    }
}

struct NotchIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: symbol)
                .frame(width: 28, height: 28)
                .background(.white.opacity(selected ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct NotchEmptyView<Actions: View>: View {
    let symbol: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                glyph
                label.multilineTextAlignment(.center).frame(maxWidth: 250)
                actions()
            }
            HStack(spacing: 14) {
                glyph
                VStack(alignment: .leading, spacing: 10) {
                    label.frame(maxWidth: 260, alignment: .leading)
                    actions()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 56, height: 56)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var label: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension NotchEmptyView where Actions == EmptyView {
    init(symbol: String, message: String) {
        self.init(symbol: symbol, message: message) { EmptyView() }
    }
}

struct NotchPillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .semibold : .medium))
                .foregroundStyle(.white.opacity(prominent ? 1 : 0.7))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(.white.opacity(prominent ? 0.14 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
    }
}

struct NotchArtwork: View {
    let image: NSImage?
    let size: CGFloat
    var source: RadialNowPlayingSnapshot? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let icon = source.flatMap(RadialNowPlayingApplication.icon(for:)) {
                Color.black.overlay {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().padding(size * 0.14)
                }
            } else {
                Color.black.overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

struct NotchRail<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let rows: Int
    let itemWidth: CGFloat
    let width: CGFloat
    var spacing: CGFloat = 8
    var leastSpacing: CGFloat? = nil
    var rowSpacing: CGFloat = 8
    var scrollTarget: Item.ID? = nil
    @ViewBuilder let content: (Item) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: Int { NotchLayout.railColumns(count: items.count, rows: rows) }
    private var starts: [Int] { Array(stride(from: 0, to: items.count, by: max(1, rows))) }
    private var rowStarts: [Int] { Array(stride(from: 0, to: items.count, by: max(1, columns))) }
    private var gap: CGFloat? {
        NotchLayout.railGap(columns: columns, itemWidth: itemWidth, spacing: spacing,
                            least: leastSpacing ?? spacing, width: width)
    }

    private var targetColumn: Int? {
        guard let scrollTarget, let index = items.firstIndex(where: { $0.id == scrollTarget }) else { return nil }
        return index / max(1, rows) * max(1, rows)
    }

    var body: some View {
        if let gap {
            let cell = (width - CGFloat(max(0, columns - 1)) * gap) / CGFloat(max(1, columns))
            VStack(spacing: rowSpacing) {
                ForEach(rowStarts, id: \.self) { start in row(start, cell: cell, gap: gap) }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(starts, id: \.self) { start in column(start).frame(width: itemWidth).id(start) }
                    }
                    .contentShape(Rectangle())
                }
                .scrollIndicators(.never)
                .notchScrollEdgeFade(.horizontal)
                .onAppear {
                    if let targetColumn { proxy.scrollTo(targetColumn, anchor: .center) }
                }
                .onChange(of: targetColumn) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ start: Int, cell: CGFloat, gap: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(items[start..<min(items.count, start + max(1, columns))]) { item in
                content(item).frame(width: cell)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func column(_ start: Int) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(items[start..<min(items.count, start + max(1, rows))]) { item in
                content(item)
            }
        }
    }
}

private struct NotchGlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchGlassSurface: Bool {
        get { self[NotchGlassSurfaceKey.self] }
        set { self[NotchGlassSurfaceKey.self] = newValue }
    }

    var notchSettingsPreview: Bool {
        get { self[NotchSettingsPreviewKey.self] }
        set { self[NotchSettingsPreviewKey.self] = newValue }
    }
}

private struct NotchSettingsPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NotchBandEnvironmentKey: EnvironmentKey {
    static let defaultValue = NotchBand()
}

extension EnvironmentValues {
    var notchBand: NotchBand {
        get { self[NotchBandEnvironmentKey.self] }
        set { self[NotchBandEnvironmentKey.self] = newValue }
    }
}

struct NotchBandItems {
    var leading: AnyView?
    var trailing: AnyView?
}

struct NotchBandKey: PreferenceKey {
    static var defaultValue = NotchBandItems()

    static func reduce(value: inout NotchBandItems, nextValue: () -> NotchBandItems) {
        let next = nextValue()
        if let leading = next.leading { value.leading = leading }
        if let trailing = next.trailing { value.trailing = trailing }
    }
}

extension View {
    func notchBand<Leading: View, Trailing: View>(@ViewBuilder leading: () -> Leading,
                                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        let leading = AnyView(leading()), trailing = AnyView(trailing())
        return transformPreference(NotchBandKey.self) { $0.leading = leading; $0.trailing = trailing }
    }

    func notchBand<Leading: View>(@ViewBuilder leading: () -> Leading) -> some View {
        let leading = AnyView(leading())
        return transformPreference(NotchBandKey.self) { $0.leading = leading }
    }

    func notchBand<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        let trailing = AnyView(trailing())
        return transformPreference(NotchBandKey.self) { $0.trailing = trailing }
    }
}

struct NotchBandRow<Leading: View, Trailing: View>: View {
    let band: NotchBand
    var covered: HorizontalEdge? = nil
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            side(covered == .leading) {
                HStack(spacing: 6) { leading() }
            }
            .frame(width: band.besideCamera ? band.side : nil, alignment: .leading)
            .frame(maxWidth: band.besideCamera ? nil : .infinity, alignment: .leading)
            Spacer(minLength: band.besideCamera ? 0 : 12)
            side(covered == .trailing) {
                HStack(spacing: 6) { trailing() }
            }
            .frame(width: band.besideCamera ? band.side : nil, alignment: .trailing)
            .layoutPriority(band.besideCamera ? 0 : 1)
        }
        .frame(height: band.height)
    }

    private func side<Content: View>(_ hidden: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

final class NotchBackdropPresentation: ObservableObject {
    @Published var contour = Path()
    @Published var usesGlass = false
    @Published var stripHeight: CGFloat = 0
    @Published private(set) var fade = NotchGlassFade.open
    var floatingGap: CGFloat = 0

    var openness: Double { Double(fade.openness(atHeight: contourBottom + floatingGap)) }
    fileprivate var contourBottom: CGFloat { contour.boundingRect.isNull ? 0 : contour.boundingRect.maxY }

    var restingBlack: Double { 1 - openness }

    func planFade(from start: CGFloat, to end: CGFloat, endsInGlass: Bool) {
        setFade(.plan(from: start, to: end, endsInGlass: endsInGlass,
                      current: usesGlass ? fade.openness(atHeight: start) : 0))
    }

    func openFully() { setFade(.open) }

    func shut() { setFade(NotchGlassFade(solidHeight: 100_000, range: 1)) }

    private func setFade(_ next: NotchGlassFade) {
        guard fade != next else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { fade = next }
    }
}

struct NotchBackdropShape: Shape {
    var contour: Path
    func path(in rect: CGRect) -> Path { contour }
}

struct NotchWindowBackground: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @AppStorage(DefaultsKey.notchTranslucentBackground) private var translucent = false

    var body: some View {
        NotchSurfaceBackground(presentation: presentation, glass: glass, translucent: translucent)
    }
}

struct NotchSurfaceBackground: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    let glass: Bool
    var translucent = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var offersGlass: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return glass && !reduceTransparency }
#endif
        return false
    }

    private var showsGlass: Bool { offersGlass && presentation.usesGlass }
    private var showsTranslucent: Bool {
        translucent && !offersGlass && presentation.usesGlass && !reduceTransparency
    }

    var body: some View {
        ZStack {
            Color.black.opacity(showsGlass || showsTranslucent ? presentation.restingBlack : 1)
#if compiler(>=6.2)
            if #available(macOS 26, *), showsGlass, presentation.restingBlack < 1 {
                let shape = NotchBackdropShape(contour: presentation.contour)
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .environment(\.appearsActive, true)
                    .materialActiveAppearance(.active)
                    .overlay {
                        LinearGradient(stops: Self.shade(openness: presentation.openness, contrast: contrast),
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: presentation.contourBottom)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .mask(shape)
                    }
            }
#endif
            if showsTranslucent, presentation.restingBlack < 1 {
                translucentOrBlack
            }
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func shade(openness: Double, contrast: ColorSchemeContrast) -> [Gradient.Stop] {
        (0...64).map { index in
            let t = Double(index) / 64
            return Gradient.Stop(
                color: .black.opacity(1 - openness * (contrast == .increased ? 0.10 : 0.45) * pow(t, 2.5)),
                location: t)
        }
    }
}

extension NotchSurfaceBackground {
    @ViewBuilder var translucentOrBlack: some View {
        if translucent, presentation.usesGlass, !reduceTransparency {
            let shape = NotchBackdropShape(contour: presentation.contour)
            let height = presentation.contourBottom
            let stops = NotchTranslucentTint.stops(height: height, stripHeight: presentation.stripHeight,
                                                   openness: presentation.openness,
                                                   increasedContrast: contrast == .increased)
                .map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) }
            let box = presentation.contour.boundingRect.integral
            ZStack(alignment: .topLeading) {
                if !box.isNull, box.width > 0, box.height > 0 {
                    NotchTranslucentMaterial(contour: presentation.contour.offsetBy(dx: -box.minX, dy: -box.minY).cgPath)
                        .frame(width: box.width, height: box.height)
                        .padding(EdgeInsets(top: box.minY, leading: box.minX, bottom: 0, trailing: 0))
                }
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .mask(shape)
            }
        } else {
            Color.black
        }
    }
}

private struct NotchTranslucentMaterial: NSViewRepresentable {
    let contour: CGPath

    func makeNSView(context: Context) -> NotchTranslucentView {
        let view = NotchTranslucentView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NotchTranslucentView, context: Context) {
        view.contour = contour
    }
}

private final class NotchTranslucentView: NSVisualEffectView {
    var contour: CGPath? {
        didSet { if contour != oldValue { updateMask() } }
    }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { updateMask() }
    }

    private func updateMask() {
        guard let contour, bounds.width > 0, bounds.height > 0 else {
            maskImage = nil
            return
        }
        maskImage = NSImage(size: bounds.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(contour)
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
    }
}

struct NotchControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    var selected = false
    var interactive = true
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.notchGlassSurface) private var glassSurface

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if glassSurface {
                content
                    .background(.white.opacity(selected ? 0.11 : 0.045), in: shape)
                    .overlay {
                        shape.strokeBorder(.white.opacity(selected ? 0.16 : 0.065), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
            } else {
#if compiler(>=6.2)
                if #available(macOS 26, *), glass, !reduceTransparency {
                    content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                        .glassEffect(.regular.interactive(interactive), in: shape)
                } else {
                    content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                }
#else
                content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
#endif
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

struct NotchMenuItem {
    let title: String
    var checked = false
    var symbol: String? = nil
    var enabled = true
    var action: () -> Void = {}

    static let separator = NotchMenuItem(title: "")
    var isSeparator: Bool { title.isEmpty }
}

struct NotchMenuButton<Label: View>: View {
    let title: String
    let items: [NotchMenuItem]
    var cornerRadius: CGFloat = 6
    @ViewBuilder let label: () -> Label
    @State private var anchor = NotchMenuAnchor()

    var body: some View {
        Button { anchor.popUp(items) } label: { label() }
            .buttonStyle(NotchButtonStyle(cornerRadius: cornerRadius, lifts: false))
            .background(NotchMenuAnchorView(anchor: anchor))
            .accessibilityLabel(title)
    }
}

struct NotchBandBackButton: View {
    let title: String
    let action: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(l10n.s.obBack)
        .accessibilityLabel(l10n.s.obBack)
        .accessibilityValue(title)
    }
}

struct NotchBandMenuLabel: View {
    let title: String
    var symbol: String? = nil
    var truncation: Text.TruncationMode = .tail

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.white.opacity(0.55))
            }
            Text(title).lineLimit(1).truncationMode(truncation)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 7)
        .frame(height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

final class NotchMenuAnchor: NSObject {
    fileprivate weak var view: NSView?
    private var actions: [() -> Void] = []

    func popUp(_ items: [NotchMenuItem]) {
        guard let view else { return }
        actions = items.map(\.action)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = NSAppearance(named: .darkAqua)
        for (index, item) in items.enumerated() {
            guard !item.isSeparator else { menu.addItem(.separator()); continue }
            let entry = NSMenuItem(title: item.title, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = item.checked ? .on : .off
            entry.isEnabled = item.enabled
            if let symbol = item.symbol {
                entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(entry)
        }
        var location = NSPoint.zero
        if let window = view.window, let screen = window.screen {
            let bottom = window.convertPoint(toScreen: view.convert(location, to: nil)).y
            let edge = screen.visibleFrame.maxY - 3
            if bottom > edge { location.y -= bottom - edge }
        }
        menu.popUp(positioning: nil, at: location, in: view)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

private struct NotchMenuAnchorView: NSViewRepresentable {
    let anchor: NotchMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

extension NSAlert {
    static func confirmAboveIsland(_ title: String, message: String, action: String,
                                   destructive: Bool, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action).hasDestructiveAction = destructive
        alert.addButton(withTitle: cancel).keyEquivalent = "\u{1b}"
        return alert.runAboveIsland() == .alertFirstButtonReturn
    }

    private func runAboveIsland() -> NSApplication.ModalResponse {
        let island = NotchService.shared.presentationWindow
        var observers: [NSObjectProtocol] = []
        if let island {
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let alertWindow = window
            let raise: (Notification) -> Void = { _ in alertWindow.level = level }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { alertWindow.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}

extension NSSavePanel {
    func runAboveIsland() -> NSApplication.ModalResponse {
        let island = NotchService.shared.presentationWindow
        var observers: [NSObjectProtocol] = []
        if let island {
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let raise: (Notification) -> Void = { [weak self] _ in self?.level = level }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { [weak self] in self?.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}
