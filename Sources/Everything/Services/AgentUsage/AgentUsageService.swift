// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import Network

final class AgentUsageService: ObservableObject {
    static let shared = AgentUsageService()

    @Published private(set) var snapshot = AgentUsageSnapshot()
    @Published private(set) var claudeAppChecked: Date?
    @Published private(set) var claudeAccountChecking = false
    @Published private(set) var claudeAccountFailure: AgentClaudeServer.Failure?
    @Published private(set) var claudeProfile = ClaudeAccountProfile()
    @Published private(set) var claudeAccountIdentity: ClaudeAccountProfile.Identity?
    @Published private(set) var pricesUpdated: Date?
    let events = PassthroughSubject<AgentUsageEvent, Never>()

    static let horizon: TimeInterval = 8 * 86_400
    private static let tick: TimeInterval = 30
    private static let poll: TimeInterval = 1
    private static let idlePoll: TimeInterval = 5
    private static let pollWindow: TimeInterval = 10 * 60
    private static let publishDelay: TimeInterval = 0.25
    private static let saveInterval: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "com.vorssaint.agent-usage", qos: .utility, autoreleaseFrequency: .workItem)
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private var running = false
    private var paused = false
    private var session = 0
    private var cancellation = Cancellation()
    private var timer: Timer?
    private var providers: [AgentProvider] = []
    private var pricesInFlight = false
    private var pricesAttempted = Date.distantPast
    private var pricesFailed = false
    private var pricesSaved: Date?
    private let claudeAccountQueue = DispatchQueue(label: "com.vorssaint.claude-limits", qos: .utility)
    private var claudeAccountRequest: AgentClaudeServer.Request?
    private var claudeAccountAttempted = Date.distantPast
    private var claudeAccountUnreachable = 0
    private var online = true
    private var pageVisible = false

    private var readerSession = -1
    private var readerCancellation: Cancellation?
    private var enabled: Set<AgentProvider> = []
    private var store = AgentUsageStore()
    private var cursors: [String: AgentLogCursor] = [:]
    private var watcher: AgentLogWatcher?
    private var watchedRoots: [AgentLogRoot] = []
    private var poller: DispatchSourceTimer?
    private var polling = false
    private var pollInterval: TimeInterval = 0
    private var network: NWPathMonitor?
    private var offlineSince: (date: Date, uptime: TimeInterval)?
    private var publishScheduled = false
    private var published = AgentUsageSnapshot()
    private var claudePlan: AgentPlan?
    private var claudeOrganization: String?
    private var claudeIdentity: ClaudeAccountProfile.Identity?
    private var readerClaudeProfile = ClaudeAccountProfile()
    private var claudeProfileModified: Date?
    private var claudeAppModified: Date?
    private var claudeAppSamples: [AgentClaudeAppUsage.Sample] = []
    private var claudeAccountLimits: AgentLimits?
    private var shippedPrices: AgentPriceList?
    private var previousLimits: [AgentProvider: AgentLimits] = [:]
    private var warned: [String: (provider: AgentProvider, window: AgentLimitWindow)] = [:]
    private var budgetDay: Date?
    private var lastRootCheck = Date.distantPast
    private var savedMark: Int?
    private var lastSave = Date.distantPast

    private init() {}

    func syncWithPreferences() {
        CodexProfileLimitsService.shared.synchronize()
        guard NotchAgentSupport.isEnabled() else { stop(); return }
        let wanted = NotchAgentSupport.providers()
        let profile = ClaudeAccountProfile.selected()
        let showingPage = pageVisible
        if running, wanted != providers || profile != claudeProfile {
            stop(keepingProgress: false, pausingAccounts: false)
        }
        if claudeProfile != profile { claudeProfile = profile }
        pageVisible = showingPage
        if !running {
            running = true
            session += 1
            cancellation = Cancellation()
            providers = wanted
            start(session: session, providers: Set(wanted), cancellation: cancellation, claudeProfile: profile)
        } else if paused {
            resume()
        }
        syncPrices()
        refreshClaudeLimits()
    }

    func pause() {
        CodexProfileLimitsService.shared.pause()
        pageVisible = false
        guard running, !paused else { return }
        paused = true
        cancelClaudeLimits()
        timer?.invalidate()
        timer = nil
        queue.async { [self] in
            poller?.cancel()
            poller = nil
            watcher?.stop()
            saveProgress()
        }
    }

    private func resume() {
        paused = false
        startTimer()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            watch(AgentLogRoot.all(home: home, claudeProfile: readerClaudeProfile).filter { enabled.contains($0.provider) })
            filesChanged([], rescan: true)
            startPolling()
            schedulePublish()
        }
    }

    func stop(keepingProgress keeps: Bool = true, pausingAccounts: Bool = true) {
        if pausingAccounts { CodexProfileLimitsService.shared.pause() }
        pageVisible = false
        if running { cancellation.cancel() }
        settleArchive(keeping: keeps && NotchAgentSupport.isEnabled())
        guard running else { return }
        running = false
        cancelClaudeLimits()
        claudeAccountAttempted = .distantPast
        claudeAccountFailure = nil
        claudeAccountUnreachable = 0
        online = true
        paused = false
        session += 1
        timer?.invalidate()
        timer = nil
        providers = []
        pricesInFlight = false
        pricesSaved = nil
        snapshot = AgentUsageSnapshot()
        claudeAppChecked = nil
        claudeAccountIdentity = nil
        queue.async { [self] in
            readerSession = -1
            readerCancellation = nil
            poller?.cancel()
            poller = nil
            watcher?.stop()
            watcher = nil
            watchedRoots = []
            network?.cancel()
            network = nil
            offlineSince = nil
            store = AgentUsageStore()
            cursors.removeAll()
            published = AgentUsageSnapshot()
            previousLimits.removeAll()
            warned.removeAll()
            budgetDay = nil
            claudePlan = nil
            claudeOrganization = nil
            claudeIdentity = nil
            claudeProfileModified = nil
            claudeAppModified = nil
            claudeAppSamples = []
            claudeAccountLimits = nil
            savedMark = nil
            lastSave = .distantPast
        }
    }

    func noteLimits(_ reading: AgentLimits) {
        guard running else { return }
        queue.async { [self] in
            guard readerSession >= 0, enabled.contains(reading.provider) else { return }
            store.updateLimits(reading)
            checkLimits()
            schedulePublish()
        }
    }

    func pageDidAppear(preview: Bool = false) {
        if !preview { pageVisible = true }
        guard running else { return }
        refreshClaudeLimits(pageShows: true)
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            readClaudePlan()
            readClaudeApp(now: Date())
            checkLimits()
            publish()
        }
    }

    func pageDidDisappear() {
        pageVisible = false
    }

    func checkClaudeAccount() {
        guard running, !paused, claudeAccountRequest == nil else { return }
        claudeAccountAttempted = .distantPast
        refreshClaudeLimits(pageShows: true)
    }

    // MARK: Reading

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.tickTimer() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func start(session: Int, providers: Set<AgentProvider>, cancellation: Cancellation,
                       claudeProfile: ClaudeAccountProfile = ClaudeAccountProfile()) {
        startTimer()
        queue.async { [self] in
            readerSession = session
            readerCancellation = cancellation
            enabled = providers
            readerClaudeProfile = claudeProfile
            store = AgentUsageStore()
            cursors.removeAll()
            loadPrices()
            let horizon = Date().addingTimeInterval(-Self.horizon)
            let roots = AgentLogRoot.all(home: home, claudeProfile: claudeProfile).filter { providers.contains($0.provider) }
            let files = AgentLogReader.discover(roots, since: horizon)
            if let saved = AgentUsageArchive.load(), saved.providers == providers {
                let resumed = AgentUsageArchive.resume(saved, logs: Set(files.map(\.path)), since: horizon)
                (store, cursors) = (resumed.store, resumed.cursors)
                if resumed.unchanged { savedMark = progressMark }
            }
            for file in files {
                guard !cancellation.isCancelled else { return }
                read(file.path, provider: file.provider)
            }
            guard !cancellation.isCancelled else { return }
            let now = Date()
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            closeEndedTurns(roots, atLaunch: true)
            readClaudePlan()
            readClaudeApp(now: now)
            store.reportsTransitions = true
            previousLimits = store.limits
            MemoryRelief.soon(after: 2)
            let today = Calendar.autoupdatingCurrent.startOfDay(for: now)
            if let budget = NotchAgentSupport.dailyBudget(),
               store.records.lazy.filter({ $0.date >= today }).reduce(0.0, { $0 + ($1.cost ?? 0) }) >= budget {
                budgetDay = today
            }
            watch(roots)
            startPolling()
            watchNetwork()
            publish()
            saveProgress()
        }
    }

    private func settleArchive(keeping keeps: Bool) {
        queue.sync {
            if keeps { saveProgress() } else { AgentUsageArchive.remove() }
        }
    }

    private func saveProgress() {
        guard readerSession >= 0 else { return }
        let mark = progressMark
        lastSave = Date()
        guard mark != savedMark else { return }
        let kept = cursors.values.filter { !$0.restarted && $0.provider != .opencode }
        let contents = AgentUsageArchive.Contents(providers: enabled, store: store.saved, cursors: kept.map(\.saved))
        if AgentUsageArchive.save(contents) { savedMark = mark }
    }

    private var progressMark: Int {
        let records = store.records.reduce(0) { $1.provider == .opencode ? $0 : $0 + 1 }
        return cursors.values.reduce(records) { mark, cursor in
            guard cursor.provider != .opencode else { return mark }
            var hasher = Hasher()
            hasher.combine(cursor.path)
            hasher.combine(cursor.offset)
            hasher.combine(cursor.identity)
            return mark &+ hasher.finalize()
        }
    }

    private func startPolling() {
        poller?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .distantFuture)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            defer { self.syncPolling() }
            let read = self.pollOpenLogs(within: Self.pollWindow)
            var stopped = self.store.closeSettledTurns(now: Date())
            if let offline = self.offlineSince,
               self.store.closeOfflineTurns(since: offline.date,
                                            lasting: ProcessInfo.processInfo.systemUptime - offline.uptime,
                                            keeping: self.runningCommands) {
                stopped = true
            }
            self.pollTicks &+= 1
            let checksSessions = read || stopped || self.pollTicks % 4 == 0
            guard (checksSessions && self.closeEndedTurns(self.watchedRoots)) || read || stopped else { return }
            self.checkLimits()
            self.schedulePublish()
        }
        poller = timer
        polling = false
        syncPolling()
        timer.resume()
    }

    private var pollTicks = 0

    private func syncPolling(now: Date = Date()) {
        guard let poller else { return }
        let working = !store.turns.isEmpty || !store.waiting.isEmpty
        let wanted = working || cursors.values.contains { now.timeIntervalSince($0.modified) < Self.pollWindow }
        let interval = working ? Self.poll : Self.idlePoll
        guard wanted != polling || (wanted && interval != pollInterval) else { return }
        polling = wanted
        pollInterval = wanted ? interval : 0
        if wanted {
            poller.schedule(deadline: .now() + interval, repeating: interval,
                            leeway: .milliseconds(working ? 400 : 2000))
        } else {
            poller.schedule(deadline: .distantFuture)
        }
    }

    private func pollOpenLogs(within window: TimeInterval) -> Bool {
        guard readerSession >= 0 else { return false }
        let now = Date()
        var working = Set(store.turns.keys).union(store.waiting.keys)
        for key in working {
            if let mark = key.firstIndex(of: "#") { working.insert(String(key[..<mark])) }
        }
        var changed = false
        for (path, cursor) in cursors
        where working.contains(path) || now.timeIntervalSince(cursor.modified) < window {
            if cursor.provider == .opencode {
                if let modified = AgentOpenCodeReader.modified(path), modified <= cursor.modified { continue }
                if read(path, provider: cursor.provider) { changed = true }
                continue
            }
            var info = stat()
            let exists = stat(path, &info) == 0
            guard !exists || UInt64(max(0, info.st_size)) != cursor.offset
                    || UInt64(info.st_ino) != cursor.identity else { continue }
            if read(path, provider: cursor.provider) { changed = true }
        }
        return changed
    }

    private func watchNetwork() {
        guard network == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, self.readerSession >= 0 else { return }
            let online = path.status == .satisfied
            if online {
                self.offlineSince = nil
            } else if self.offlineSince == nil {
                self.offlineSince = (Date(), ProcessInfo.processInfo.systemUptime)
            }
            let session = self.readerSession
            DispatchQueue.main.async {
                guard self.running, self.session == session else { return }
                self.networkChanged(online: online)
            }
        }
        monitor.start(queue: queue)
        network = monitor
    }

    private var runningCommands: Set<String> {
        Set(cursors.filter { !$0.value.state.runningCommands.isEmpty }.keys)
    }

    @discardableResult
    private func closeEndedTurns(_ roots: [AgentLogRoot], atLaunch: Bool = false) -> Bool {
        guard store.showsClaudeTurn else { return false }
        let folders = roots.filter { $0.provider == .claude }
            .map { $0.url.deletingLastPathComponent().appending(path: "sessions", directoryHint: .isDirectory) }
        return store.closeEndedTurns(AgentSessionRegistry.read(folders), atLaunch: atLaunch)
    }

    @discardableResult
    private func read(_ path: String, provider: AgentProvider) -> Bool {
        guard let cancellation = readerCancellation, !cancellation.isCancelled else { return false }
        guard FileManager.default.fileExists(atPath: path) else {
            cursors[path] = nil
            return store.forget(file: path)
        }
        let cursor = cursors[path] ?? AgentLogCursor(path: path, provider: provider)
        cursors[path] = cursor
        var changed = false
        let now = Date()
        let consume: (Data) -> Void = { [self] line in
            let entries = provider.reader.parse(line, state: &cursor.state, now: now)
            guard !entries.isEmpty else { return }
            changed = true
            let isSubagent = provider == .opencode && !cursor.state.parentSession.isEmpty
            let turnFile = provider == .opencode && !cursor.state.session.isEmpty ? "\(path)#\(cursor.state.session)" : path
            let tracksTurns = isSubagent ? false : cursor.tracksTurns
            let parent = isSubagent ? "\(path)#\(cursor.state.parentSession)"
                : cursor.parent ?? cursor.codexParent(among: cursors)
            let finished = store.apply(entries, file: turnFile, provider: provider, tracksTurns: tracksTurns,
                                       parent: parent, modified: cursor.modified, now: now)
            finished.forEach(report)
        }
        if provider.reader.readsFullHistoryFirst && cursor.offset == 0 {
            AgentLogReader.readCopilotHistory(cursor, shouldContinue: { !cancellation.isCancelled }, line: consume)
        } else {
            AgentLogReader.readAppended(cursor, since: now.addingTimeInterval(-Self.horizon),
                                        shouldContinue: { !cancellation.isCancelled }, line: consume)
        }
        return changed
    }

    private func watch(_ roots: [AgentLogRoot]) {
        let existing = roots.filter(\.exists)
        watchedRoots = existing
        lastRootCheck = Date()
        if watcher == nil {
            watcher = AgentLogWatcher(queue: queue) { [weak self] paths, rescan in
                self?.filesChanged(paths, rescan: rescan)
            }
        }
        if existing.isEmpty { watcher?.stop() } else { watcher?.start(existing.map(\.url.path)) }
    }

    private func filesChanged(_ paths: [String], rescan: Bool) {
        guard readerSession >= 0, !watchedRoots.isEmpty else { return }
        defer { syncPolling() }
        var changed = false
        if rescan {
            for file in AgentLogReader.discover(watchedRoots, since: Date().addingTimeInterval(-Self.horizon)) {
                if read(file.path, provider: file.provider) { changed = true }
            }
        } else {
            for path in Set(paths) where AgentLogReader.isLog(path) {
                let actualPath = path.hasSuffix("-wal") ? String(path.dropLast(4)) : path
                guard let root = watchedRoots.first(where: { $0.accepts(actualPath) }) else { continue }
                if read(actualPath, provider: root.provider) { changed = true }
            }
        }
        guard changed else { return }
        checkLimits()
        schedulePublish()
    }

    private func schedulePublish() {
        guard !publishScheduled else { return }
        publishScheduled = true
        queue.asyncAfter(deadline: .now() + Self.publishDelay) { [self] in
            publishScheduled = false
            publish()
        }
    }

    private func tickTimer() {
        guard running else { return }
        syncPrices()
        refreshClaudeLimits()
        queue.async { [self] in
            guard readerSession >= 0 else { return }
            let now = Date()
            defer { syncPolling(now: now) }
            let before = inputs
            store.closeIdleTurns(now: now, after: NotchAgentSupport.idleTurn)
            store.dropRecords(before: now.addingTimeInterval(-Self.horizon))
            var changed = pollOpenLogs(within: 86_400)
            if now.timeIntervalSince(lastRootCheck) > 300 {
                let roots = AgentLogRoot.all(home: home, claudeProfile: readerClaudeProfile).filter { enabled.contains($0.provider) }
                if roots.filter(\.exists) != watchedRoots {
                    for file in AgentLogReader.discover(roots, since: now.addingTimeInterval(-Self.horizon)) {
                        if read(file.path, provider: file.provider) { changed = true }
                    }
                    watch(roots)
                }
                lastRootCheck = now
            }
            readClaudePlan()
            readClaudeApp(now: now)
            checkLimits()
            reportRenewals(now: now)
            if now.timeIntervalSince(lastSave) >= Self.saveInterval { saveProgress() }
            if changed || inputs != before || AgentUsageSummary.movesWithClock(published, now: now) {
                schedulePublish()
            }
        }
    }

    private struct Inputs: Equatable {
        let records: Int
        let turns: [String: AgentLiveSession]
        let limits: [AgentProvider: AgentLimits]
        let codexPlan: String?
        let claudePlan: AgentPlan?
        let claudeOrganization: String?
        let claudeIdentity: ClaudeAccountProfile.Identity?
        let claudeApp: [AgentClaudeAppUsage.Sample]
    }

    private var inputs: Inputs {
        Inputs(records: store.records.count, turns: store.turns, limits: store.limits, codexPlan: store.codexPlan,
               claudePlan: claudePlan, claudeOrganization: claudeOrganization, claudeIdentity: claudeIdentity,
               claudeApp: claudeAppSamples)
    }

    private func publish() {
        let session = readerSession
        guard session >= 0 else { return }
        var plans: [AgentProvider: AgentPlan] = [:]
        if let claudePlan { plans[.claude] = claudePlan }
        if let codex = AgentPlans.codex(planType: store.codexPlan) { plans[.codex] = codex }
        let next = store.snapshot(plans: plans, providers: enabled, now: Date())
        published = next
        checkBudget(next)
        let checked = enabled.contains(.claude) ? claudeAppSamples.last(where: {
            claudeOrganization == nil || $0.organization == nil || $0.organization == claudeOrganization
        })?.date : nil
        let listed = AgentPricing.list.updated
        let prices = listed == AgentPriceList.empty.updated ? nil : listed
        let identity = claudeIdentity
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            if self.claudeAppChecked != checked { self.claudeAppChecked = checked }
            if self.claudeAccountIdentity != identity { self.claudeAccountIdentity = identity }
            if self.pricesUpdated != prices { self.pricesUpdated = prices }
            if self.snapshot != next { self.snapshot = next }
        }
    }

    // MARK: Alerts

    private func report(_ event: AgentUsageEvent) {
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            switch event {
            case .finished(let provider, let duration, _, _, _):
                guard self.providers.contains(provider), let minimum = NotchAgentSupport.finishMinimum(),
                      duration >= minimum else { return }
            case .limitWarning(let provider, _), .limitReset(let provider, _):
                guard self.providers.contains(provider), NotchAgentSupport.limitThreshold() != nil else { return }
            case .budgetReached:
                guard NotchAgentSupport.dailyBudget() != nil else { return }
            }
            self.events.send(event)
        }
    }

    private func checkLimits() {
        guard store.reportsTransitions else { return }
        let threshold = NotchAgentSupport.limitThreshold() ?? NotchAgentSupport.defaultLimitThreshold
        for (provider, limits) in store.limits {
            for window in AgentLimitSupport.crossings(previous: previousLimits[provider], current: limits,
                                                      threshold: threshold) {
                warned[window.id] = (provider, window)
                report(.limitWarning(provider: provider, window: window))
            }
        }
        for (id, entry) in warned {
            guard let reading = store.limits[entry.provider],
                  let window = reading.windows.first(where: { $0.id == id }), window.usedPercent < threshold,
                  AgentLimitSupport.renewed(entry.window, to: window, observedAt: reading.observedAt) else { continue }
            warned[id] = nil
            report(.limitReset(provider: entry.provider, window: window))
        }
        previousLimits = store.limits
    }

    private func reportRenewals(now: Date) {
        for (id, entry) in warned {
            guard let resets = entry.window.resetsAt, resets <= now else { continue }
            warned[id] = nil
            report(.limitReset(provider: entry.provider, window: entry.window))
        }
    }

    private func checkBudget(_ snapshot: AgentUsageSnapshot) {
        guard store.reportsTransitions, let budget = NotchAgentSupport.dailyBudget() else { return }
        let today = Calendar.autoupdatingCurrent.startOfDay(for: snapshot.now)
        let spent = snapshot.usage(.today).total.cost
        guard spent >= budget, budgetDay != today else { return }
        budgetDay = today
        report(.budgetReached(spent: spent, budget: budget))
    }

    // MARK: Plans and limits

    private func readClaudePlan() {
        guard enabled.contains(.claude) else { return }
        let url = readerClaudeProfile.profileURL(home: home)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != claudeProfileModified || !readerClaudeProfile.isAvailable(home: home) else { return }
        claudeProfileModified = modified
        let reading = readerClaudeProfile.read(home: home)
        if reading.identity != claudeIdentity {
            claudeAccountLimits = nil
            store.clearLimits(.claude)
            previousLimits[.claude] = nil
            warned = warned.filter { $0.value.provider != .claude }
        }
        guard let identity = reading.identity else {
            claudePlan = nil
            claudeOrganization = nil
            claudeIdentity = nil
            claudeAccountLimits = nil
            store.clearLimits(.claude)
            return
        }
        claudeIdentity = identity
        claudeOrganization = identity.organization
        claudePlan = reading.plan
    }

    private func readClaudeApp(now: Date) {
        guard enabled.contains(.claude) else {
            store.clearLimits(.claude)
            claudeAccountLimits = nil
            claudeAppModified = nil
            claudeAppSamples = []
            return
        }
        if !readerClaudeProfile.isDefault {
            claudeAppModified = nil
            claudeAppSamples = []
            if let reading = AgentClaudeServer.current(claudeAccountLimits, now: now) {
                store.setLimits(reading)
            } else {
                store.clearLimits(.claude)
            }
            return
        }
        let url = AgentClaudeAppUsage.historyURL(home: home)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if modified != claudeAppModified {
            claudeAppModified = modified
            claudeAppSamples = modified == nil ? []
                : (try? Data(contentsOf: url)).flatMap(AgentClaudeAppUsage.samples) ?? []
        }
        let start = AgentClaudeAppUsage.sessionStart(store.records, samples: claudeAppSamples,
                                                     organization: claudeOrganization)
        let desktop = AgentClaudeAppUsage.limits(from: claudeAppSamples, now: now, sessionStart: start,
                                                 organization: claudeOrganization)
        let account = AgentClaudeServer.current(claudeAccountLimits, now: now)
        let recent = account.flatMap { now.timeIntervalSince($0.observedAt) < AgentClaudeAppUsage.freshness ? $0 : nil }
        if let latest = recent ?? [desktop, account].compactMap({ $0 }).max(by: { $0.observedAt < $1.observedAt }) {
            store.setLimits(latest)
        } else {
            store.clearLimits(.claude)
        }
    }

    func refreshClaudeLimits(now: Date = Date(), pageShows: Bool = false) {
        guard claudeLimitsDue(at: now, pageShows: pageShows) else { return }
        claudeAccountAttempted = now
        claudeAccountChecking = true
        let request = AgentClaudeServer.Request()
        claudeAccountRequest = request
        let session = self.session
        let home = self.home
        let profile = claudeProfile
        claudeAccountQueue.async { [weak self] in
            let result: Result<AgentClaudeServer.Summary, AgentClaudeServer.Failure>
            if let executable = AgentClaudeServer.executable(home: home, searchPath: ProcessInfo.processInfo.environment["PATH"]) {
                var environment = AgentCodexServer.environment(for: executable, searchPath: nil)
                environment["PATH"] = AgentClaudeServer.searchPath(after: environment["PATH"] ?? "", home: home)
                result = request.run(executable, home: home, environment: environment, profile: profile)
            } else { result = .failure(.missing) }
            DispatchQueue.main.async {
                guard let self, self.running, !self.paused, self.session == session,
                      self.claudeAccountRequest === request else { return }
                self.claudeAccountRequest = nil
                self.claudeAccountChecking = false
                switch result {
                case .failure(let failure): self.noteClaudeCheck(failure)
                case .success(let summary):
                    self.noteClaudeCheck(nil)
                    self.queue.async {
                        guard self.readerSession == session, self.enabled.contains(.claude) else { return }
                        self.readClaudePlan()
                        guard self.readerClaudeProfile == profile, self.claudeIdentity == summary.identity else { return }
                        self.claudeAccountLimits = summary.limits
                        self.readClaudeApp(now: Date())
                        self.checkLimits()
                        self.schedulePublish()
                    }
                }
            }
        }
    }

    private func cancelClaudeLimits() {
        guard let request = claudeAccountRequest else { return }
        request.cancel()
        claudeAccountRequest = nil
        claudeAccountChecking = false
        claudeAccountAttempted = .distantPast
    }

    private func claudeLimitsDue(at now: Date, pageShows: Bool) -> Bool {
        guard running, !paused, online, providers.contains(.claude), claudeAccountRequest == nil,
              NotchAgentSupport.limitsInUse(pageShown: pageVisible || pageShows) else { return false }
        return now.timeIntervalSince(claudeAccountAttempted) >= AgentClaudeServer.interval(
            after: claudeAccountFailure, repeated: claudeAccountUnreachable, pageVisible: pageVisible)
    }

    private func noteClaudeCheck(_ failure: AgentClaudeServer.Failure?) {
        claudeAccountFailure = failure
        claudeAccountUnreachable = failure == .unreachable ? claudeAccountUnreachable + 1 : 0
    }

    private func networkChanged(online: Bool) {
        guard online != self.online else { return }
        self.online = online
        if online { claudeAccountUnreachable = 0 }
    }

    // MARK: Prices

    private func loadPrices() {
        if shippedPrices == nil { shippedPrices = AgentPriceSource.bundled() }
        let cached = AgentPriceSource.cached()
        AgentPricing.install(AgentPriceList.newer(shippedPrices, cached?.list) ?? .empty)
        let saved = cached?.saved ?? .distantPast
        let session = readerSession
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.session == session else { return }
            self.pricesSaved = saved
            self.syncPrices()
        }
    }

    private func syncPrices() {
        guard false else { return }
        guard running, NotchAgentSupport.updatesPrices(), !pricesInFlight, let saved = pricesSaved else { return }
        let now = Date()
        let wait = pricesFailed ? AgentPriceSource.retryInterval : AgentPriceSource.refreshInterval
        guard now.timeIntervalSince(saved) >= AgentPriceSource.refreshInterval,
              now.timeIntervalSince(pricesAttempted) >= wait else { return }
        pricesInFlight = true
        pricesAttempted = now
        let session = self.session
        AgentPriceSource.download { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.session == session else { return }
                self.pricesInFlight = false
                guard let result else {
                    self.pricesFailed = true
                    return
                }
                let (data, list) = result
                self.pricesFailed = false
                self.pricesSaved = Date()
                self.queue.async {
                    AgentPriceSource.save(data)
                    guard self.readerSession == session,
                          AgentPricing.install(AgentPriceList.newer(self.shippedPrices, list) ?? list) else { return }
                    self.store.reprice()
                    self.publish()
                }
            }
        }
    }
}
