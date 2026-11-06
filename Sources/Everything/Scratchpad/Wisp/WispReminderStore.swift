import Foundation
import UserNotifications

struct Reminder: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case scheduled
        case waiting
        case cancelled
    }

    var id: String
    var line: String
    var phrase: String
    var fireDate: Date
    var state: State
    var handedOver = false
    var archived = false
    var cancelledAt: Date?

    init(id: String, line: String, phrase: String, fireDate: Date, state: State) {
        self.id = id
        self.line = line
        self.phrase = phrase
        self.fireDate = fireDate
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        line = try c.decode(String.self, forKey: .line)
        phrase = try c.decode(String.self, forKey: .phrase)
        fireDate = try c.decode(Date.self, forKey: .fireDate)
        state = try c.decode(State.self, forKey: .state)
        handedOver = try c.decodeIfPresent(Bool.self, forKey: .handedOver) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        cancelledAt = try c.decodeIfPresent(Date.self, forKey: .cancelledAt)
    }
}

enum ReminderPermission: Sendable, Equatable {
    case allowed, denied, notDetermined
}

@MainActor
protocol ReminderScheduling: AnyObject {
    var canDeliver: Bool { get }
    func schedule(_ reminder: Reminder, done: @escaping @Sendable @MainActor (Bool) -> Void)
    func cancel(_ ids: [String])
    func pending(_ done: @escaping @Sendable @MainActor ([String]) -> Void)
    func currentPermission(_ done: @escaping @Sendable @MainActor (ReminderPermission) -> Void)
    func requestPermission(_ done: @escaping @Sendable @MainActor (Bool) -> Void)
    func flush(timeout: TimeInterval)
}

@MainActor
final class ReminderStore {
    static let didChange = Notification.Name("WispRemindersDidChange")

    static let shared = ReminderStore(
        fileURL: StorageLocation.defaultFolder.appendingPathComponent("Reminders.json"),
        scheduler: SystemReminderScheduler()
    )

    private static let reviveWindow: TimeInterval = 10 * 60
    private static let historyKept: TimeInterval = 86_400
    static let pendingLimit = 64

    let fileURL: URL
    let scheduler: ReminderScheduling
    private let clock: () -> Date
    private(set) var reminders: [Reminder] = []
    private(set) var permission: ReminderPermission = .notDetermined
    var editing: [String: String] = [:]
    private var externalLines: Set<String> = []
    private var loadedCleanly = true
    private var asking = false
    private var permissionChecked = false
    private var changePosted = false
    private var readings: [String: (reading: Reminders.Reading, phrase: String)?] = [:]
    private var readingsMinute = 0
    private var tick: Timer?

    init(fileURL: URL, scheduler: ReminderScheduling, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.scheduler = scheduler
        self.clock = clock
        load()
        scheduleTick()
    }

    func timeChanged() {
        sync()
        scheduleTick()
        changed()
    }

    // MARK: What a line shows

    func label(forLine line: String, now: Date = Date()) -> Reminders.Label? {
        guard Reminders.isReminder(line) else { return nil }
        if let reminder = active(line) { return label(for: reminder, now: now) }
        guard let read = reading(line, now: now) else { return nil }
        if let origin = editing[line], let reminder = active(origin),
           reminder.phrase.lowercased() == read.phrase.lowercased() {
            return label(for: reminder, now: now)
        }
        switch read.reading {
        case .past: return .past
        case .noTime: return .noTime
        case .at(let date):
            if externalLines.contains(line) { return .notOnThisMac }
            if !scheduler.canDeliver { return .outsideApplications }
            if permission == .denied { return .notificationsOff }
            return .due(date)
        }
    }

    private func label(for reminder: Reminder, now: Date) -> Reminders.Label {
        if reminder.fireDate <= now {
            return reminder.handedOver ? .sent(reminder.fireDate) : .notSent
        }
        if reminder.state == .scheduled {
            return permission == .denied ? .notificationsOff : .set(reminder.fireDate)
        }
        if !scheduler.canDeliver { return .outsideApplications }
        switch permission {
        case .denied: return .notificationsOff
        case .notDetermined: return .needsPermission
        case .allowed: return .set(reminder.fireDate)
        }
    }

    private func reading(_ line: String, now: Date) -> (reading: Reminders.Reading, phrase: String)? {
        let minute = Int((now.timeIntervalSinceReferenceDate / 60).rounded(.down))
        if minute != readingsMinute {
            readings = [:]
            readingsMinute = minute
        }
        if let known = readings[line] { return known }
        let read = Reminders.read(line, now: now)
        readings.updateValue(read, forKey: line)
        return read
    }

    func isExternal(_ line: String) -> Bool { externalLines.contains(line) }

    // MARK: Setting and cancelling

    @discardableResult
    func commit(line: String, origin: String? = nil, restored: Bool = false, now: Date = Date()) -> Reminder? {
        guard let read = Reminders.read(line, now: now), case .at(let date) = read.reading else { return nil }
        if let existing = active(line) { return existing }
        externalLines.remove(line)

        if let origin, origin != line, let i = reminders.lastIndex(where: {
            $0.line == origin && !$0.archived && ($0.state != .cancelled || recent($0, now))
        }) {
            if reminders[i].phrase.lowercased() == read.phrase.lowercased() {
                reminders[i].line = line
                restore(i, now: now)
                return finishChange(at: i, now: now)
            }
            withdraw(i, now: now)
        }
        if let i = reminders.lastIndex(where: {
            $0.line == line && $0.state == .cancelled && !$0.archived && recent($0, now) && ($0.fireDate > now || restored)
        }) {
            restore(i, now: now)
            return finishChange(at: i, now: now)
        }

        let whole = Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
        reminders.append(Reminder(id: UUID().uuidString, line: line, phrase: read.phrase, fireDate: whole, state: .waiting))
        return finishChange(at: reminders.count - 1, now: now)
    }

    private func restore(_ i: Int, now: Date) {
        reminders[i].cancelledAt = nil
        if reminders[i].state == .cancelled { reminders[i].state = .waiting }
        if reminders[i].state == .scheduled, reminders[i].fireDate > now {
            hand(i)
        }
    }

    private func withdraw(_ i: Int, now: Date) {
        if reminders[i].fireDate > now {
            scheduler.cancel([reminders[i].id])
            reminders[i].handedOver = false
        }
        reminders[i].state = .cancelled
        reminders[i].cancelledAt = now
    }

    private func finishChange(at i: Int, now: Date) -> Reminder {
        sync(now: now)
        save()
        refreshPermission(askIfUndecided: true, now: now)
        changed()
        return reminders[i]
    }

    func reconcile(noteText: String, now: Date = Date()) {
        let editedFrom = Set(editing.values)
        let live = reminders.indices.filter {
            reminders[$0].state != .cancelled && !reminders[$0].archived && !editedFrom.contains(reminders[$0].line)
        }
        let present = Self.present(Set(live.map { reminders[$0].line }), in: noteText)
        var touched = false
        for i in live where !present.contains(reminders[i].line) {
            withdraw(i, now: now)
            touched = true
        }
        let before = reminders.count
        let oldest = now.addingTimeInterval(-Self.historyKept)
        reminders.removeAll {
            ($0.state == .cancelled && ($0.cancelledAt ?? .distantPast) < oldest) || ($0.archived && $0.fireDate < oldest)
        }
        if touched || reminders.count != before {
            sync(now: now)
            save()
            changed()
        }
    }

    func archive(noteText: String, keeping kept: String = "") {
        let live = reminders.indices.filter { reminders[$0].state != .cancelled && !reminders[$0].archived }
        let lines = Set(live.map { reminders[$0].line })
        let leaving = Self.present(lines, in: noteText).subtracting(Self.present(lines, in: kept))
        var touched = false
        for i in live where leaving.contains(reminders[i].line) {
            reminders[i].archived = true
            touched = true
        }
        if touched { save() }
    }

    func loaded(_ text: String, now: Date = Date()) {
        reconcile(noteText: text, now: now)
        let ns = text as NSString
        var external: Set<String> = []
        var revived = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard Reminders.mightBeReminder(ns, range) else { return }
            let line = ns.substring(with: range)
            guard Reminders.isReminder(line), self.active(line) == nil else { return }
            if let i = self.reminders.lastIndex(where: {
                $0.line == line && $0.state == .cancelled && !$0.archived && self.recent($0, now)
            }) {
                self.restore(i, now: now)
                revived = true
            } else {
                external.insert(line)
            }
        }
        externalLines = external
        if revived {
            sync(now: now)
            save()
        }
        changed()
    }

    // MARK: macOS

    private func sync(now: Date = Date()) {
        guard permissionChecked else { return }
        let ahead = reminders.indices
            .filter { reminders[$0].state != .cancelled && reminders[$0].fireDate > now }
            .sorted { reminders[$0].fireDate < reminders[$1].fireDate }
        let canHand = scheduler.canDeliver && permission == .allowed
        let held = canHand ? Set(ahead.prefix(Self.pendingLimit)) : []
        var touched = false
        for i in ahead where held.contains(i) != (reminders[i].state == .scheduled) {
            if held.contains(i) {
                reminders[i].state = .scheduled
                hand(i)
            } else {
                if canHand { scheduler.cancel([reminders[i].id]) }
                reminders[i].state = .waiting
                reminders[i].handedOver = false
            }
            touched = true
        }
        if touched { save() }
    }

    private func hand(_ i: Int) {
        reminders[i].handedOver = true
        let id = reminders[i].id
        scheduler.schedule(reminders[i]) { [weak self] taken in
            guard !taken, let self, let i = self.reminders.firstIndex(where: { $0.id == id }),
                  self.reminders[i].state == .scheduled else { return }
            self.reminders[i].state = .waiting
            self.reminders[i].handedOver = false
            self.save()
            self.changed()
        }
    }

    private func repair() {
        scheduler.pending { [weak self] ids in
            guard let self else { return }
            let held = Set(ids)
            let ours = Set(self.reminders.filter { $0.state == .scheduled && $0.fireDate > Date() }.map(\.id))
            for i in self.reminders.indices where self.reminders[i].state == .scheduled
                && self.reminders[i].fireDate > Date() && !held.contains(self.reminders[i].id) {
                self.hand(i)
            }
            let strays = held.subtracting(ours)
            if self.loadedCleanly, !strays.isEmpty { self.scheduler.cancel(Array(strays)) }
        }
    }

    // MARK: Permission

    func refreshPermission(askIfUndecided: Bool = false, now: Date = Date()) {
        if true { return }
        scheduler.currentPermission { [weak self] current in
            guard let self else { return }
            let was = self.permission
            self.permission = current
            self.permissionChecked = true
            if current == .notDetermined, askIfUndecided, !self.asking, self.scheduler.canDeliver, self.hasWaiting() {
                self.asking = true
                self.scheduler.requestPermission { [weak self] granted in
                    guard let self else { return }
                    self.asking = false
                    self.refreshPermission(now: self.clock())
                }
                return
            }
            self.sync(now: now)
            if current == .allowed { self.repair() }
            if current != was { self.changed() }
        }
    }

    private func hasWaiting(now: Date = Date()) -> Bool {
        reminders.contains { $0.state == .waiting && $0.fireDate > now }
    }

    func flush(timeout: TimeInterval = 1) {
        scheduler.flush(timeout: timeout)
    }

    // MARK: Finding

    func reminder(id: String) -> Reminder? {
        reminders.first { $0.id == id }
    }

    func locate(_ reminder: Reminder, in text: String) -> NSRange? {
        guard !reminder.archived else { return nil }
        var found: NSRange?
        (text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (text as NSString).length), options: .byLines
        ) { line, range, _, stop in
            if line == reminder.line {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    private func active(_ line: String) -> Reminder? {
        reminders.last { $0.line == line && $0.state != .cancelled && !$0.archived }
    }

    private func recent(_ reminder: Reminder, _ now: Date) -> Bool {
        guard let at = reminder.cancelledAt else { return true }
        return now.timeIntervalSince(at) <= Self.reviveWindow
    }

    // MARK: Lines

    nonisolated static func present(_ candidates: Set<String>, in text: String) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        if candidates.count <= 16 {
            let ns = text as NSString
            return candidates.filter { containsLine($0, in: ns) }
        }
        guard candidates.count <= 100 else { return candidates.intersection(lines(of: text)) }
        var text = text
        return text.withUTF8 { note in candidates.filter { containsLine($0, in: note) } }
    }

    nonisolated private static func containsLine(_ line: String, in ns: NSString) -> Bool {
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let hit = ns.range(of: line, options: .literal, range: search)
            guard hit.location != NSNotFound else { return false }
            let startsLine = hit.location == 0 || isLineBreak(ns.character(at: hit.location - 1))
            let endsLine = NSMaxRange(hit) == ns.length || isLineBreak(ns.character(at: NSMaxRange(hit)))
            if startsLine && endsLine { return true }
            search = NSRange(location: hit.location + 1, length: ns.length - hit.location - 1)
        }
        return false
    }

    nonisolated private static func isLineBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029
    }

    nonisolated private static func containsLine(_ line: String, in note: UnsafeBufferPointer<UInt8>) -> Bool {
        var line = line
        return line.withUTF8 { needle in
            guard let base = note.baseAddress, let bytes = needle.baseAddress, needle.count > 0 else { return false }
            var from = 0
            while note.count - from >= needle.count {
                guard let hit = memmem(base + from, note.count - from, bytes, needle.count) else { return false }
                let start = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
                if breakBefore(start, in: note), breakAfter(start + needle.count, in: note) { return true }
                from = start + 1
            }
            return false
        }
    }

    nonisolated private static func breakBefore(_ index: Int, in b: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index > 0 else { return true }
        let c = b[index - 1]
        if c == 0x0A || c == 0x0D { return true }
        if c == 0x85 { return index >= 2 && b[index - 2] == 0xC2 }
        if c == 0xA8 || c == 0xA9 { return index >= 3 && b[index - 3] == 0xE2 && b[index - 2] == 0x80 }
        return false
    }

    nonisolated private static func breakAfter(_ index: Int, in b: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index < b.count else { return true }
        let c = b[index]
        if c == 0x0A || c == 0x0D { return true }
        if c == 0xC2 { return index + 1 < b.count && b[index + 1] == 0x85 }
        if c == 0xE2 { return index + 2 < b.count && b[index + 1] == 0x80 && (b[index + 2] == 0xA8 || b[index + 2] == 0xA9) }
        return false
    }

    nonisolated static func lines(of text: String) -> Set<String> {
        var lines = Set<String>()
        (text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (text as NSString).length), options: .byLines
        ) { line, _, _, _ in
            if let line { lines.insert(line) }
        }
        return lines
    }

    // MARK: Disk

    private struct Entry: Decodable {
        let reminder: Reminder?
        init(from decoder: Decoder) throws { reminder = try? Reminder(from: decoder) }
    }

    private func load() {
        let aside = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
        loadedCleanly = !FileManager.default.fileExists(atPath: aside.path)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let entries = try? JSONDecoder().decode([Entry].self, from: data)
        reminders = entries?.compactMap(\.reminder) ?? []
        if entries == nil || reminders.count != entries?.count {
            loadedCleanly = false
            if !FileManager.default.fileExists(atPath: aside.path) { try? data.write(to: aside, options: .atomic) }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(reminders) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
        scheduleTick()
    }

    private func scheduleTick(now: Date = Date()) {
        tick?.invalidate()
        guard let next = reminders
            .filter({ $0.state != .cancelled && $0.fireDate > now })
            .map(\.fireDate).min() else { return }
        let timer = Timer(timeInterval: next.timeIntervalSince(now) + 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sync()
                self.changed()
                self.scheduleTick()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    func changed() {
        guard !changePosted else { return }
        changePosted = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.changePosted = false
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }
}

@MainActor
final class SystemReminderScheduler: ReminderScheduling {
    var canDeliver: Bool { Self.isAppBundle && Self.isInApplicationsFolder(Bundle.main.bundlePath) }

    nonisolated static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    nonisolated static func isInApplicationsFolder(_ bundlePath: String) -> Bool {
        bundlePath.hasSuffix(".app") && bundlePath.contains("/Applications/")
    }

    private let inFlight = DispatchGroup()

    nonisolated static let category = "WispReminder"
    nonisolated static let doneAction = "WispReminderDone"

    nonisolated static func registerActions() {
        guard isAppBundle else { return }
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [done], intentIdentifiers: [], options: []),
        ])
    }

    func schedule(_ reminder: Reminder, done: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard Self.isAppBundle else {
            done(false)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Scratchpad"
        content.body = Reminders.sentence(ofLine: reminder.line)
        content.sound = .default
        content.categoryIdentifier = Self.category
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var when = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        when.calendar = utc
        when.timeZone = utc.timeZone
        let request = UNNotificationRequest(
            identifier: reminder.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )
        let group = inFlight
        group.enter()
        UNUserNotificationCenter.current().add(request) { error in
            group.leave()
            let taken = error == nil
            Task { @MainActor in done(taken) }
        }
    }

    func cancel(_ ids: [String]) {
        guard Self.isAppBundle else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pending(_ done: @escaping @Sendable @MainActor ([String]) -> Void) {
        guard Self.isAppBundle else {
            done([])
            return
        }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
            Task { @MainActor in done(ids) }
        }
    }

    func currentPermission(_ done: @escaping @Sendable @MainActor (ReminderPermission) -> Void) {
        guard Self.isAppBundle else {
            done(.denied)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let permission: ReminderPermission
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permission = .allowed
            case .denied: permission = .denied
            default: permission = .notDetermined
            }
            Task { @MainActor in done(permission) }
        }
    }

    func requestPermission(_ done: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard Self.isAppBundle else {
            done(false)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    func flush(timeout: TimeInterval) {
        _ = inFlight.wait(timeout: .now() + timeout)
    }
}
