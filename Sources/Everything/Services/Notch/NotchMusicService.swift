// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class NotchMusicService: ObservableObject {
    static let shared = NotchMusicService()
    @Published private(set) var playback: NotchPlayback?
    @Published private(set) var sources: [NotchPlaybackSource] = []
    @Published private(set) var sourceIsAutomatic = true
    @Published private(set) var selectedSourcePID: Int32?
    @Published private(set) var awaitingPlayback = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkTint: NotchArtworkTint?
    @Published private(set) var commandFailed = false
    @Published private(set) var commandPending = false
    @Published private(set) var automationAvailability: NotchMusicAutomation.Availability?
    @Published private(set) var requestingAutomation = false
    @Published private(set) var upcoming: NotchQueueSnapshot? {
        didSet {
            guard upcoming != oldValue else { return }
            queueCovers.update(upcoming, decode: NSImage.init(data:))
            upcomingArtwork = queueCovers.images
        }
    }
    @Published private(set) var upcomingArtwork: [String: NSImage] = [:]
    private var queueCovers = NotchQueueCovers<NSImage>()
    @Published private(set) var queueLoading = false
    @Published private(set) var queueActionPending = false
    @Published private(set) var queueActionFailed = false
    let trackChanges = PassthroughSubject<Void, Never>()
    let trackEnds = PassthroughSubject<Void, Never>()
    let gestureSkips = PassthroughSubject<Bool, Never>()
    private var trackChange = NotchTrackChange()
    static let appleMusic = "com.apple.Music"
    private struct Reading {
        let playback: NotchPlayback?
        let artwork: NSImage?
        let tint: NotchArtworkTint?
        let sources: [NotchPlaybackSource]
        let automatic: Bool?
        let selectedPID: Int32?
    }
    private var gapReading: Reading?
    private var gapWork: DispatchWorkItem?
    private var queueVisible = false
    private var queueRequest: UUID?
    private var queueReply: [String: Any]?
    private var process: Process?
    private var output: Pipe?
    private var input: Pipe?
    private var generation = UUID()
    private var wantsPlayback = false
    private var includeOtherPlayers = false
    private var restartCount = 0
    private var restartWork: DispatchWorkItem?
    private var launchedAt: TimeInterval?
    private var chosenSource: NotchPlaybackSource.Selection?
    private var restoringSource = false
    private var artworkCache = NotchArtworkCache<(image: NSImage, tint: NotchArtworkTint?)>()
    private var artworkWork: DispatchWorkItem?
    private var automationTarget: NotchMusicAutomation.Target?
    private var automationDiscovery = DispatchWorkItem {}
    private var automationCancellation = DispatchWorkItem {}
    private var automationConsentCancellation = DispatchWorkItem {}
    private var automationTimeout: DispatchWorkItem?
    private struct AutomationAction {
        let id = UUID()
        let command: Command
        let playback: NotchPlayback
        let availability: NotchMusicAutomation.Availability
    }
    private var automationAction: AutomationAction?
    private var awaitingAutomationValidation = false
    private let queue = DispatchQueue(label: "com.vorssaint.notch-music", qos: .utility)
    private lazy var commandWriter = NotchMusicCommandWriter { [queue = self.queue] action in queue.async(execute: action) }

    private init() {}

    private static var adapter: [String]? {
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libEverythingNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path) else { return nil }
        return [script.path, library.path]
    }

    func start() {
        let includeOtherPlayers = UserDefaults.standard.bool(forKey: DefaultsKey.notchIncludeOtherPlayers)
        if wantsPlayback {
            guard self.includeOtherPlayers != includeOtherPlayers else { return }
            stop()
        }
        self.includeOtherPlayers = includeOtherPlayers
        wantsPlayback = true
        awaitingPlayback = true
        restartCount = 0
        launch()
    }

    private func launch() {
        guard wantsPlayback, process == nil else { return }
        guard let arguments = Self.adapter else { connectionEnded(); return }
        let process = Process()
        let output = Pipe()
        let input = Pipe()
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { connectionEnded(); return }
        let requested = UUID()
        generation = requested
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = arguments + [includeOtherPlayers ? "watch_all" : "watch"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        var playerArtwork: Data?
        var cachedArtwork: Data?
        var cachedImage: NSImage?
        var cachedTint: NotchArtworkTint?
        let reader = NotchMusicPipeReader { [weak self] data in
            let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let reply, reply["validationRequest"] != nil {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.receiveValidation(reply)
                }
                return
            }
            if let reply,
               reply["queueRequest"] != nil || reply["queueAction"] != nil {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.receiveQueue(reply)
                }
                return
            }
            if let sent = reply?["sent"] as? Bool {
                DispatchQueue.main.async {
                    guard let self, self.generation == requested else { return }
                    self.commandFailed = !sent
                }
                return
            }
            var next = NotchPlayback.decode(data, previousArtwork: playerArtwork,
                                           commandContext: reply.flatMap(NotchPlaybackContext.init(reply:)),
                                           canSendCommandsDirectly: reply?["canSendCommandsDirectly"] as? Bool == true)
            playerArtwork = next?.track.artworkData
            if let playback = next, let cover = NotchBrowserArtwork.shared.artwork(for: playback) {
                next = playback.withArtwork(cover)
            }
            if cachedArtwork != next?.track.artworkData {
                cachedArtwork = next?.track.artworkData
                cachedImage = cachedArtwork.flatMap { ImageThumbnailer.thumbnail(data: $0, pointSize: 160, scale: 2) }
                cachedTint = cachedImage.flatMap(NotchMusicService.artworkTint(of:))
            }
            let image = cachedImage
            let tint = cachedTint
            let automatic = reply?["sourceIsAutomatic"] as? Bool
            let selectedPID = automatic == false ? NotchPlaybackSource.decodePID(reply?["selectedPID"]) : nil
            let sources = NotchPlaybackSource.decode(reply?["sources"], selectedPID: selectedPID)
            DispatchQueue.main.async {
                guard let self, self.generation == requested,
                      self.acceptsSourceReply(automatic: automatic, sources: sources) else { return }
                let music = sources.first { $0.bundleIdentifier == Self.appleMusic }
                let shown = next?.track.appBundleIdentifier == Self.appleMusic ? next : nil
                if shown == nil, let music, !(automatic == false && selectedPID == music.pid) {
                    self.sources = sources
                    self.selectSource(music.selection)
                }
                self.receive(Reading(playback: shown, artwork: shown == nil ? nil : image,
                                     tint: shown == nil ? nil : tint, sources: music.map { [$0] } ?? [],
                                     automatic: automatic, selectedPID: selectedPID))
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { reader.append(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.connectionEnded()
            }
        }
        do {
            try process.run()
            commandWriter.start()
            self.process = process
            self.output = output
            self.input = input
            launchedAt = ProcessInfo.processInfo.systemUptime
            restoreSource()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            connectionEnded()
        }
    }

    private func restoreSource() {
        guard let chosenSource else { restoringSource = false; return }
        restoringSource = send(.source(chosenSource))
    }

    private func acceptsSourceReply(automatic: Bool?, sources: [NotchPlaybackSource]) -> Bool {
        let restoring = restoringSource
        restoringSource = false
        guard automatic == true, let chosenSource else { return true }
        guard sources.contains(where: { $0.selection == chosenSource }) else {
            self.chosenSource = nil
            return true
        }
        return !restoring
    }

    private func receive(_ reading: Reading) {
        let listing = gapWork == nil ? reading.sources : []
        if let current = playback, !awaitingPlayback,
           NotchTrackChange.isBetweenSongs(reading.playback, after: current, sources: listing) {
            gapReading = reading
            guard gapWork == nil else { return }
            let requested = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == requested, let reading = self.gapReading else { return }
                self.endPlaybackGap()
                self.apply(reading)
            }
            gapWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchPlayback.gapGracePeriod, execute: work)
            return
        }
        endPlaybackGap()
        apply(reading)
    }

    private func endPlaybackGap() {
        gapWork?.cancel()
        gapWork = nil
        gapReading = nil
    }

    private func apply(_ reading: Reading) {
        let first = awaitingPlayback
        if trackChange.isNewSong(reading.playback, first: first) { trackChanges.send() }
        else if !first, let current = playback, NotchTrackChange.isBetweenSongs(reading.playback, after: current) {
            trackEnds.send()
        }
        updateArtwork(reading.artwork, tint: reading.tint, playback: reading.playback)
        playback = reading.playback
        sources = reading.sources
        NotchPreferredPlayer.remember(reading.playback, in: reading.sources)
        sourceIsAutomatic = reading.automatic ?? true
        selectedSourcePID = reading.selectedPID
        awaitingPlayback = false
        updateAutomation(for: reading.playback)
        NotchLyricsService.shared.playbackChanged(reading.playback)
        updateQueue()
    }

    private func connectionEnded() {
        if let launchedAt, ProcessInfo.processInfo.systemUptime - launchedAt > 60 { restartCount = 0 }
        launchedAt = nil
        disconnect()
        guard wantsPlayback, restartCount < 2 else { awaitingPlayback = false; return }
        restartCount += 1
        let requested = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsPlayback, self.generation == requested else { return }
            self.restartWork = nil
            self.launch()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restartCount), execute: work)
    }

    private func requestBrowserArtwork(for playback: NotchPlayback?) {
        NotchBrowserArtwork.shared.request(for: playback) { [weak self] in
            DispatchQueue.main.async { self?.applyBrowserArtwork() }
        }
    }

    func syncBrowserCovers() {
        requestBrowserArtwork(for: gapWork == nil ? playback : gapReading?.playback)
    }

    private func applyBrowserArtwork() {
        guard let playback, let cover = NotchBrowserArtwork.shared.artwork(for: playback),
              let image = ImageThumbnailer.thumbnail(data: cover, pointSize: 160, scale: 2) else { return }
        updateArtwork(image, tint: Self.artworkTint(of: image), playback: playback.withArtwork(cover))
    }

    private func updateArtwork(_ image: NSImage?, tint: NotchArtworkTint?, playback: NotchPlayback?) {
        artworkWork?.cancel()
        artworkWork = nil
        artworkCache.update(image.map { (image: $0, tint: tint) }, for: playback)
        artwork = artworkCache.artwork?.image
        artworkTint = artworkCache.artwork?.tint
        guard let deadline = artworkCache.expiresAt else { return }
        let requested = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == requested, self.artworkCache.expiresAt == deadline else { return }
            self.artworkCache.expire(at: deadline)
            self.artwork = self.artworkCache.artwork?.image
            self.artworkTint = self.artworkCache.artwork?.tint
            self.artworkWork = nil
        }
        artworkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
    }

    private static func artworkTint(of image: NSImage) -> NotchArtworkTint? {
        return nil
    }

    func stop() {
        wantsPlayback = false
        awaitingPlayback = false
        restartWork?.cancel()
        restartWork = nil
        restartCount = 0
        trackChange.reset()
        disconnect()
    }

    private func disconnect() {
        endPlaybackGap()
        artworkWork?.cancel()
        artworkWork = nil
        artworkCache = .init()
        automationDiscovery.cancel()
        automationConsentCancellation.cancel()
        automationTarget = nil
        automationAvailability = nil
        cancelAutomationAction()
        commandWriter.stop()
        queueVisible = false
        NotchLyricsService.shared.hide()
        NotchBrowserArtwork.shared.cancel()
        queueRequest = nil
        queueReply = nil
        upcoming = nil
        queueCovers = .init()
        queueLoading = false
        queueActionPending = false
        queueActionFailed = false
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
        input = nil
        output = nil
        playback = nil
        sources = []
        sourceIsAutomatic = true
        selectedSourcePID = nil
        artwork = nil
        artworkTint = nil
        commandFailed = false
    }

    typealias Command = NotchPlaybackCommand

    func selectSource(_ selection: NotchPlaybackSource.Selection?) {
        if selection == nil ? sourceIsAutomatic
            : !sourceIsAutomatic && selectedSourcePID == selection?.pid { return }
        guard selection == nil || sources.contains(where: { $0.selection == selection }),
              send(.source(selection)) else { return }
        chosenSource = selection
        cancelAutomationAction()
        setQueueVisible(false)
        endPlaybackGap()
        playback = nil
        artwork = nil
        artworkTint = nil
        awaitingPlayback = true
        updateAutomation(for: nil)
        NotchLyricsService.shared.playbackChanged(nil)
    }

    func setQueueVisible(_ visible: Bool) {
        queueVisible = visible && NotchQueueSupport.isEnabled() && playback != nil
        guard queueVisible else {
            commandWriter.setQueueRequest(nil)
            if queueRequest != nil { send(.queueStop) }
            queueRequest = nil
            queueReply = nil
            upcoming = nil
            queueLoading = false
            queueActionPending = false
            queueActionFailed = false
            return
        }
        guard queueRequest == nil else { return }
        refreshQueue()
    }

    func syncQueuePreference() {
        guard !NotchQueueSupport.isEnabled() else { return }
        setQueueVisible(false)
        queueCovers = .init()
    }

    func refreshQueue() {
        guard queueVisible, NotchQueueSupport.isEnabled(), playback != nil else { return }
        let request = UUID()
        queueRequest = request
        commandWriter.setQueueRequest(request)
        queueReply = nil
        upcoming = nil
        queueLoading = true
        queueActionFailed = false
        queueActionPending = false
        if !send(.queue(request)) { queueLoading = false; queueActionFailed = true }
    }

    var upcomingIsHeld: Bool {
        guard let upcoming else { return false }
        return upcoming.currentIdentifier != playback?.itemIdentifier || upcoming.pid != playback?.track.appPID
    }

    var upcomingRows: [NotchQueueItem] {
        upcoming?.items.filter { $0.id != playback?.itemIdentifier } ?? []
    }

    func playQueued(_ item: NotchQueueItem) {
        guard queueVisible, NotchQueueSupport.isEnabled(), let request = queueRequest, let upcoming,
              let playback, upcoming.currentIdentifier == playback.itemIdentifier,
              upcoming.pid == playback.track.appPID, upcoming.canPlay,
              upcoming.items.contains(where: { $0.id == item.id && $0.offset == item.offset }),
              !queueActionPending else { return }
        queueActionFailed = false
        queueActionPending = true
        let selected = NotchQueueSelection(requestID: request, pid: upcoming.pid,
            currentIdentifier: upcoming.currentIdentifier, itemIdentifier: item.id, offset: item.offset)
        if !send(.queuePlay(selected)) { queueActionPending = false; queueActionFailed = true }
    }

    private func receiveQueue(_ reply: [String: Any]) {
        guard let request = queueRequest, NotchQueueSupport.isEnabled() else { return }
        if reply["queueAction"] as? String == request.uuidString {
            queueActionPending = false
            queueActionFailed = reply["queueActionOK"] as? Bool != true
        } else if reply["queueRequest"] as? String == request.uuidString {
            queueLoading = false
            queueReply = reply
            updateQueue()
        }
    }

    private func updateQueue() {
        guard let request = queueRequest, let playback, let queueReply, NotchQueueSupport.isEnabled() else {
            upcoming = nil
            return
        }
        let next = NotchQueueSupport.decode(queueReply, requestID: request, playback: playback)
        if next == nil, upcoming != nil,
           NotchQueueSupport.awaitsSongQueue(queueReply, requestID: request, playback: playback) { return }
        upcoming = next
    }

    func seek(to position: Double, in track: RadialNowPlayingSnapshot, context: NotchPlaybackContext?) {
        guard let playback, playback.track == track,
              let context, context == playback.commandContext,
              let position = playback.seekPosition(position, allowed: canSeek) else { return }
        send(.seek(position), context: context)
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        send(command, context: playback?.commandContext)
    }

    func skipFromGesture(forward: Bool) {
        let command: Command = forward ? .next : .previous
        guard canPerform(command), send(command) else { return }
        gestureSkips.send(forward)
    }

    @discardableResult
    func send(_ command: Command, context: NotchPlaybackContext?) -> Bool {
        switch command {
        case .queue, .queuePlay: guard queueVisible, NotchQueueSupport.isEnabled() else { return false }
        default: break
        }
        switch command {
        case .source, .queueStop: break
        default: guard playback != nil else { return false }
        }
        guard process?.isRunning == true, let input else { return false }
        if command.requiresPlaybackContext {
            guard gapWork == nil, let context, context == playback?.commandContext else { return false }
            guard !commandPending, let playback else { return false }
            if !playback.canSendCommandsDirectly { return beginAutomation(command, playback: playback) }
        }
        let requested = generation
        let requestedQueue = command.queueRequest
        commandFailed = false
        return commandWriter.submit(command, context: context, write: { data in
            try input.fileHandleForWriting.write(contentsOf: data)
        }, failed: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == requested,
                      requestedQueue == nil || self.queueRequest == requestedQueue else { return }
                self.commandFailed = true
                self.cancelAutomationAction()
                self.queueLoading = false
                self.queueActionPending = false
                self.queueActionFailed = self.queueRequest != nil
            }
        })
    }

    var canSeek: Bool {
        guard let playback, playback.hasPosition, playback.duration > 0 else { return false }
        return playback.canSendCommandsDirectly ? playback.canSeek
            : automationAvailability?.access == .granted && automationAvailability?.capabilities.position != nil
    }

    func canPerform(_ command: Command) -> Bool {
        guard let playback, playback.commandContext != nil, !commandPending else { return false }
        if case .seek = command { return canSeek }
        if playback.canSendCommandsDirectly { return !lacksTrackSkipping(command) }
        guard let available = automationAvailability, available.access == .granted else { return false }
        if command == .toggle { return available.capabilities.canToggle }
        return available.capabilities.event(for: command, isPlaying: playback.isPlaying) != nil
    }

    func lacksTrackSkipping(_ command: Command) -> Bool {
        guard let playback, playback.canSendCommandsDirectly else { return false }
        switch command {
        case .next: return playback.canSkipNext == false
        case .previous: return playback.canSkipPrevious == false
        default: return false
        }
    }

    func refreshAutomation() {
        automationTarget = nil
        updateAutomation(for: playback)
    }

    private func updateAutomation(for playback: NotchPlayback?) {
        if let action = automationAction, action.playback.commandContext != playback?.commandContext { cancelAutomationAction() }
        guard let playback, !playback.canSendCommandsDirectly, let target = NotchMusicAutomation.Target(playback) else {
            automationDiscovery.cancel()
            automationConsentCancellation.cancel()
            automationTarget = nil
            automationAvailability = nil
            cancelAutomationAction()
            return
        }
        guard target != automationTarget else { return }
        automationConsentCancellation.cancel()
        automationDiscovery.cancel()
        let cancellation = DispatchWorkItem {}
        automationDiscovery = cancellation
        automationTarget = target
        if automationAvailability?.target != target { automationAvailability = nil }
        let requested = generation
        queue.async { [weak self] in
            guard !cancellation.isCancelled else { return }
            let available = NotchMusicAutomation.inspect(target)
            DispatchQueue.main.async {
                guard let self, self.generation == requested, self.automationTarget == target,
                      !cancellation.isCancelled else { return }
                self.automationAvailability = available
            }
        }
    }

    func requestAutomationAccess() {
        guard !requestingAutomation, let available = automationAvailability,
              available.access == .consent, available.target.isCurrent else { return }
        requestingAutomation = true
        let requested = generation
        let context = playback?.commandContext
        let cancellation = DispatchWorkItem {}
        automationConsentCancellation = cancellation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !cancellation.isCancelled, available.target.isCurrent {
                _ = AppleScriptRunner.consentToAutomate(bundleID: available.target.bundleIdentifier)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingAutomation = false
                guard !cancellation.isCancelled, self.generation == requested, self.playback?.commandContext == context,
                      self.automationTarget == available.target else { return }
                self.refreshAutomation()
            }
        }
    }

    private func beginAutomation(_ command: Command, playback: NotchPlayback) -> Bool {
        guard canPerform(command), let context = playback.commandContext,
              let available = automationAvailability, available.target.isCurrent else { return false }
        let action = AutomationAction(command: command, playback: playback, availability: available)
        automationAction = action
        awaitingAutomationValidation = true
        automationCancellation = DispatchWorkItem {}
        commandPending = true
        commandFailed = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.automationAction?.id == action.id else { return }
            self.cancelAutomationAction()
            self.commandFailed = true
        }
        automationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        guard send(.validate(action.id, context)) else {
            cancelAutomationAction(); commandFailed = true; return false
        }
        return true
    }

    private func receiveValidation(_ reply: [String: Any]) {
        guard awaitingAutomationValidation, let action = automationAction,
              reply["validationRequest"] as? String == action.id.uuidString else { return }
        awaitingAutomationValidation = false
        guard reply["validationOK"] as? Bool == true, playback?.commandContext == action.playback.commandContext else {
            cancelAutomationAction(); commandFailed = true; return
        }
        automationTimeout?.cancel(); automationTimeout = nil
        let cancellation = automationCancellation
        let validatedAt = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            let succeeded = NotchMusicAutomation.send(action.command, playback: action.playback,
                availability: action.availability, cancellation: cancellation, validatedAt: validatedAt)
            DispatchQueue.main.async {
                guard let self, !cancellation.isCancelled, self.automationAction?.id == action.id else { return }
                self.cancelAutomationAction()
                self.commandFailed = !succeeded
                if !succeeded { self.refreshAutomation() }
            }
        }
    }

    private func cancelAutomationAction() {
        automationCancellation.cancel()
        automationTimeout?.cancel(); automationTimeout = nil
        automationAction = nil
        awaitingAutomationValidation = false
        commandPending = false
    }

}

private final class NotchMusicPipeReader {
    private let queue = DispatchQueue(label: "com.vorssaint.notch-music-reader", qos: .utility)
    private var buffer = Data()
    private let receive: (Data) -> Void
    init(receive: @escaping (Data) -> Void) { self.receive = receive }

    func append(_ data: Data) {
        queue.sync {
            self.buffer.append(data)
            if self.buffer.count > RadialNowPlayingSupport.maximumAdapterReplyBytes {
                self.buffer.removeAll(keepingCapacity: false)
                return
            }
            while let end = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[..<end])
                self.buffer.removeSubrange(...end)
                self.receive(line)
            }
        }
    }
}
