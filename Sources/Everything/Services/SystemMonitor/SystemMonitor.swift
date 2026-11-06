// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import IOKit
import IOKit.ps

enum MemoryPressure {
    case normal, warning, critical, unknown

    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

struct SystemSnapshot {
    var cpuTemperature: Double?
    var cpuTemperatureReadAt: TimeInterval?
    var gpuTemperature: Double?
    var batteryTemperature: Double?
    var batteryTemperatureReadAt: TimeInterval?
    var cpuUsage: Double?
    var cpuUsageReadAt: TimeInterval?
    var cpuCoreUsage: [Double?] = []
    var gpuUsage: Double?
    var memoryUsed: UInt64?
    var memoryAppUsed: UInt64?
    var memoryTotal: UInt64?
    var memoryCompressed: UInt64?
    var memoryCached: UInt64?
    var memorySwapUsed: UInt64?
    var memoryPressure: MemoryPressure = .unknown
    var fanSpeeds: [Double] = []

    var netDownBytesPerSec: Double?
    var netUpBytesPerSec: Double?
    var netTotalDown: UInt64?
    var netTotalUp: UInt64?

    var power: PowerReading?
    var peripheralBatteries: [PeripheralBatteryDevice] = []
    var peripheralBatterySample = PeripheralBatterySample()

    var disk: DiskReading?

    var connectedDevices: [ConnectedUSBDevice] = []

    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var memoryAppHistory: [Double] = []
    var netDownHistory: [Double] = []
    var netUpHistory: [Double] = []
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []
    var systemPowerHistory: [Double] = []
    var batteryHistory: [Double] = []
}

struct SystemMonitorPanelNeeds: Equatable {
    var system = false
    var network = false
    var disk = false
    var power = false
    var powerCard = false
    var cpu = false
    var gpu = false
    var memory = false
    var battery = false
    var peripheralBattery = false
    var cpuTemperature = false
    var gpuTemperature = false
    var batteryTemperature = false
    var fanSpeed = false
    var connectedDevices = false

    func merging(_ other: Self) -> Self {
        Self(system: system || other.system,
             network: network || other.network,
             disk: disk || other.disk,
             power: power || other.power,
             powerCard: powerCard || other.powerCard,
             cpu: cpu || other.cpu,
             gpu: gpu || other.gpu,
             memory: memory || other.memory,
             battery: battery || other.battery,
             peripheralBattery: peripheralBattery || other.peripheralBattery,
             cpuTemperature: cpuTemperature || other.cpuTemperature,
             gpuTemperature: gpuTemperature || other.gpuTemperature,
             batteryTemperature: batteryTemperature || other.batteryTemperature,
             fanSpeed: fanSpeed || other.fanSpeed,
             connectedDevices: connectedDevices || other.connectedDevices)
    }

    static let none = SystemMonitorPanelNeeds()

    var any: Bool {
        system || network || disk || power || powerCard || cpu || gpu || memory || battery ||
            peripheralBattery || cpuTemperature || gpuTemperature || batteryTemperature || fanSpeed ||
            connectedDevices
    }
}

final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = SystemSnapshot()

    private let queue = DispatchQueue(label: "com.vorssaint.utils.system-monitor", qos: .utility)
    private var timer: Timer?
    private var intervalSeconds = 2
    private var panelClients = 0
    private var menuPanelNeeds: SystemMonitorPanelNeeds = .none
    private var notchVisible = false
    private var notchDetailNeeds: SystemMonitorPanelNeeds = .none
    private var notchAccessoryMonitoring = false
    private var menuBarActive = false
    private var alertsActive = false
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var pendingRefreshSuppressesGPU = false
    private var pendingRefreshForcing: Set<MonitorSamplingKind> = []
    private var suppressGPUReadsUntil: TimeInterval = 0

    private var smc: SMCClient?
    private var smcTried = false
    private var cpuKeys: [SMCClient.Key] = []
    private var preferredCPUKeys: [SMCClient.Key] = []
    private var fallbackCPUKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var fanKeys: [SMCClient.Key] = []
    private var tempKeysPrepared = false
    private var fanKeysPrepared = false
    private var cpuTemperaturePlatform: CPUTemperaturePlatform = .generic

    private let networkSampler = NetworkSampler()
    private let diskSampler = DiskSampler()
    private let peripheralBatterySampler = PeripheralBatterySampler()
    private let cpuCoreSampler = CPUCoreSampler()
    private var powerSampler: PowerSampler?
    private let usbSampler = USBDeviceSampler()

    private var previousCPUTicks: (busy: UInt64, total: UInt64, time: TimeInterval)?
    private var tickCount = 0
    private var scheduledWakeTicks = 1
    private var lastSyncedPlan: SamplingPlan?
    private var lastCPUUsage: Double?
    private var lastCPUUsageReadAt: TimeInterval?
    private var missedCPUUsageSamples = 0
    private var lastGPUUsage: Double?
    private var missedGPUUsageSamples = 0
    private var memoryCache: CachedMemoryReading?
    private var cpuTemperatureCache: CachedSensorReading?
    private var gpuTemperatureCache: CachedSensorReading?
    private var batteryTemperatureCache: CachedSensorReading?
    private var lastFanSpeeds: [Double] = []
    private var missedFanSpeedSamples = 0
    private var lastDiskReading: DiskReading?
    private var lastPowerReading: PowerReading?
    private var lastPeripheralBatterySample = PeripheralBatterySample()
    private var peripheralSamplingEnabled = false
    private var peripheralSampleDue = false
    private var lastConnectedDevices: [ConnectedUSBDevice] = []
    private var lastPublishedPlan: SamplingPlan?
    private var lastPublishedForeground: Bool?

    private let historyCapacity = 120
    private var cpuHistory: MetricHistory
    private var gpuHistory: MetricHistory
    private var memoryHistory: MetricHistory
    private var memoryAppHistory: MetricHistory
    private var netDownHistory: MetricHistory
    private var netUpHistory: MetricHistory
    private var diskReadHistory: MetricHistory
    private var diskWriteHistory: MetricHistory
    private var powerHistory: MetricHistory
    private var batteryHistory: MetricHistory
    private var powerSourceRunLoopSource: CFRunLoopSource?

    private init() {
        cpuHistory = MetricHistory(capacity: historyCapacity)
        gpuHistory = MetricHistory(capacity: historyCapacity)
        memoryHistory = MetricHistory(capacity: historyCapacity)
        memoryAppHistory = MetricHistory(capacity: historyCapacity)
        netDownHistory = MetricHistory(capacity: historyCapacity)
        netUpHistory = MetricHistory(capacity: historyCapacity)
        diskReadHistory = MetricHistory(capacity: historyCapacity)
        diskWriteHistory = MetricHistory(capacity: historyCapacity)
        powerHistory = MetricHistory(capacity: historyCapacity)
        batteryHistory = MetricHistory(capacity: historyCapacity)
        if PowerSampler.hasInternalBattery {
            installPowerSourceObserver()
        }
        peripheralBatterySampler.onBluetoothRefresh = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.peripheralSamplingEnabled else { return }
                self.peripheralSampleDue = true
                self.refresh(suppressImmediateGPU: true)
            }
        }
    }

    deinit {
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
    }

    // MARK: - Lifecycle

    private func installPowerSourceObserver() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                guard monitor.shouldRun,
                      monitor.currentPlan(defaults: .standard).needPower else { return }
                monitor.refresh(forcing: [.power, .powerDraw])
            }
        }, context)?.takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
    }

    func setNotchDetailNeeds(_ needs: SystemMonitorPanelNeeds) {
        runOnMain { [weak self] in
            guard let self, self.notchDetailNeeds != needs else { return }
            self.notchDetailNeeds = needs
            self.stopTimerIfIdle()
            self.ensureTimer()
            if needs.any { self.refresh(suppressImmediateGPU: true); self.scheduleDeferredGPURefreshIfNeeded() }
        }
    }

    func setNotchAccessoryMonitoring(_ enabled: Bool) {
        runOnMain { [weak self] in
            guard let self, self.notchAccessoryMonitoring != enabled else { return }
            self.notchAccessoryMonitoring = enabled
            self.stopTimerIfIdle()
            self.ensureTimer()
            if enabled { self.refresh(suppressImmediateGPU: true) }
        }
    }

    func setNotchVisible(_ visible: Bool) {
        runOnMain { [weak self] in
            guard let self, self.notchVisible != visible else { return }
            self.notchVisible = visible
            if visible {
                self.ensureTimer()
                self.refresh(suppressImmediateGPU: true)
                self.scheduleDeferredGPURefreshIfNeeded()
            } else {
                self.stopTimerIfIdle()
                self.ensureTimer()
            }
        }
    }

    func panelDidAppear() {
        runOnMain { [weak self] in
            guard let self else { return }
            panelClients += 1
            ensureTimer()
            refresh(suppressImmediateGPU: true)
            scheduleDeferredGPURefreshIfNeeded()
        }
    }

    func panelDidDisappear() {
        runOnMain { [weak self] in
            guard let self else { return }
            panelClients = max(0, panelClients - 1)
            stopTimerIfIdle()
        }
    }

    func setMenuPanelNeeds(_ needs: SystemMonitorPanelNeeds) {
        runOnMain { [weak self] in
            guard let self else { return }
            if needs == menuPanelNeeds {
                if shouldRun {
                    ensureTimer()
                } else {
                    stopTimerIfIdle()
                }
                return
            }
            let defaults = UserDefaults.standard
            let previousNeeds = menuPanelNeeds
            let neededGPUBefore = currentPlan(defaults: defaults).needGPUUsage
            menuPanelNeeds = needs
            let needsGPUAfter = currentPlan(defaults: defaults).needGPUUsage
            if shouldRun {
                ensureTimer()
                let panelGPUBecameVisible = needs.system
                    && !previousNeeds.system
                    && defaults.bool(forKey: DefaultsKey.monitorSysGPU)
                let suppressImmediateGPU = needsGPUAfter && (!neededGPUBefore || panelGPUBecameVisible)
                refresh(suppressImmediateGPU: suppressImmediateGPU)
                if suppressImmediateGPU {
                    scheduleDeferredGPURefreshIfNeeded()
                }
            } else {
                stopTimerIfIdle()
            }
        }
    }

    func suppressGPUReadsForTransientUI(duration: TimeInterval = 0.9) {
        runOnMain { [weak self] in
            guard let self else { return }
            let until = ProcessInfo.processInfo.systemUptime + max(0.1, duration)
            suppressGPUReadsUntil = max(suppressGPUReadsUntil, until)
            if shouldSample(), currentPlan(defaults: .standard).needGPUUsage {
                scheduleDeferredGPURefreshIfNeeded()
            }
        }
    }

    func setMenuBarActive(_ active: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard active != menuBarActive else {
                if active { resyncIfPlanChanged() }
                return
            }
            menuBarActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    func setAlertsActive(_ active: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard active != alertsActive else {
                if active { resyncIfPlanChanged() }
                return
            }
            alertsActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    private func resyncIfPlanChanged() {
        syncPeripheralBatterySampling()
        guard shouldSample() else { return }
        let plan = currentPlan(defaults: .standard)
        guard plan != lastSyncedPlan else { return }
        syncTimerCadence(plan: plan)
        refresh()
    }

    func planDidChange() {
        runOnMain { [weak self] in self?.resyncIfPlanChanged() }
    }

    func setInterval(seconds: Int) {
        runOnMain { [weak self] in
            guard let self else { return }
            let clamped = max(1, seconds)
            guard clamped != intervalSeconds else { return }
            intervalSeconds = clamped
            syncTimerCadence(plan: currentPlan(defaults: .standard))
            if timer != nil { restartTimer() }
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async { work() }
        }
    }

    private func scheduleDeferredGPURefreshIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self,
                  self.shouldRun,
                  self.currentPlan(defaults: .standard).needGPUUsage else { return }
            self.refresh()
        }
    }

    private var fullMonitorVisible: Bool { panelClients > 0 }

    private var shouldRun: Bool { fullMonitorVisible || menuPanelNeeds.any || notchDetailNeeds.any || notchVisible || notchAccessoryMonitoring || menuBarActive || alertsActive }

    private func shouldSample(defaults: UserDefaults = .standard) -> Bool {
        shouldRun && currentPlan(defaults: defaults).any
    }

    private struct SamplingPlan: Equatable {
        var needCPU = false
        var needCPUCores = false
        var needMemory = false
        var needNetwork = false
        var needDisk = false
        var needPower = false
        var needPowerDraw = false
        var needPeripheralBattery = false
        var needGPUUsage = false
        var needGPUUsageMenuBar = false
        var needCPUTemperature = false
        var needGPUTemperature = false
        var needBatteryTemperature = false
        var needChipTemperatureMenuBar = false
        var needFanSpeed = false
        var needFanSpeedMenuBar = false
        var needConnectedDevices = false

        var needSMC: Bool { needPower || needTemperature || needFanSpeed }

        var powerKind: MonitorSamplingKind { needPowerDraw ? .powerDraw : .power }

        var gpuUsageKind: MonitorSamplingKind { needGPUUsageMenuBar ? .gpuUsageMenuBar : .gpuUsage }
        var temperatureKind: MonitorSamplingKind {
            needChipTemperatureMenuBar ? .temperatureMenuBar : .temperature
        }
        var fanSpeedKind: MonitorSamplingKind { needFanSpeedMenuBar ? .fanSpeedMenuBar : .fanSpeed }

        var needTemperature: Bool {
            needCPUTemperature || needGPUTemperature || needBatteryTemperature
        }

        var any: Bool {
            needCPU || needMemory || needNetwork || needDisk || needPower ||
                needPeripheralBattery || needGPUUsage || needTemperature || needFanSpeed || needConnectedDevices
        }
    }

    private struct CachedMemoryReading {
        var used: UInt64
        var appUsed: UInt64
        var total: UInt64
        var compressed: UInt64
        var cached: UInt64
        var swapUsed: UInt64?
        var pressure: MemoryPressure
        var updatedAt: TimeInterval
        var missedSamples: Int
    }

    private func currentPlan(defaults: UserDefaults) -> SamplingPlan {
        let menuPanelNeeds = self.menuPanelNeeds.merging(notchDetailNeeds)
        var plan = SamplingPlan()
        let hasInternalBattery = PowerSampler.hasInternalBattery
        let panelNeedsSystem = fullMonitorVisible || menuPanelNeeds.system
        let panelNeedsNetwork = fullMonitorVisible || menuPanelNeeds.network || notchVisible
        let panelNeedsDisk = fullMonitorVisible || menuPanelNeeds.disk
        let panelNeedsPower = fullMonitorVisible || menuPanelNeeds.power || notchVisible

        let panelCPU = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysCPU)) || menuPanelNeeds.cpu || notchVisible
        let panelGPU = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysGPU)) || menuPanelNeeds.gpu || notchVisible
        let panelMemory = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysMemory)) || menuPanelNeeds.memory || notchVisible
        let panelBattery = hasInternalBattery
            && ((panelNeedsPower && defaults.bool(forKey: DefaultsKey.monitorSysBattery)) || menuPanelNeeds.battery)
        let panelTemps = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysTemps)
        let alertCPU = defaults.bool(forKey: DefaultsKey.monitorAlertCPU)
        let alertCPUTemperature = defaults.bool(forKey: DefaultsKey.monitorAlertCPUTemperature)
        let alertBatteryTemperature = hasInternalBattery
            && defaults.bool(forKey: DefaultsKey.monitorAlertBatteryTemperature)
        let alertMemory = defaults.bool(forKey: DefaultsKey.monitorAlertMemory)
        let alertDisk = defaults.bool(forKey: DefaultsKey.monitorAlertDisk)
        let alertBattery = hasInternalBattery && defaults.bool(forKey: DefaultsKey.monitorAlertBattery)

        plan.needCPU = panelCPU || defaults.bool(forKey: DefaultsKey.menuBarCPU) || alertCPU
        plan.needCPUCores = menuPanelNeeds.system
            && defaults.bool(forKey: DefaultsKey.monitorSysCPU)
            && defaults.bool(forKey: DefaultsKey.monitorSysCPUCores)
        plan.needMemory = panelMemory || defaults.bool(forKey: DefaultsKey.menuBarMemory) || alertMemory
        plan.needNetwork = panelNeedsNetwork || defaults.bool(forKey: DefaultsKey.menuBarNetwork)
        plan.needDisk = panelNeedsDisk
            || defaults.bool(forKey: DefaultsKey.menuBarDiskUsage)
            || defaults.bool(forKey: DefaultsKey.menuBarDiskActivity)
            || alertDisk
        plan.needPower = panelNeedsPower || panelBattery
            || defaults.bool(forKey: DefaultsKey.menuBarPower)
            || (hasInternalBattery && defaults.bool(forKey: DefaultsKey.menuBarBattery))
            || (hasInternalBattery && defaults.bool(forKey: DefaultsKey.menuBarBatteryTime))
            || alertBattery
        plan.needPowerDraw = defaults.bool(forKey: DefaultsKey.menuBarPower)
        plan.needPeripheralBattery = menuPanelNeeds.peripheralBattery || notchAccessoryMonitoring
            || (menuPanelNeeds.powerCard && defaults.bool(forKey: DefaultsKey.monitorPwrPeripherals))
            || defaults.bool(forKey: DefaultsKey.menuBarPeripheralBattery)
        plan.needGPUUsage = panelGPU || defaults.bool(forKey: DefaultsKey.menuBarGPU)
        plan.needGPUUsageMenuBar = defaults.bool(forKey: DefaultsKey.menuBarGPU)
        plan.needCPUTemperature = panelTemps || menuPanelNeeds.cpuTemperature ||
            defaults.bool(forKey: DefaultsKey.menuBarCPUTemperature) || alertCPUTemperature
        plan.needGPUTemperature = panelTemps || menuPanelNeeds.gpuTemperature ||
            defaults.bool(forKey: DefaultsKey.menuBarGPUTemperature)
        plan.needBatteryTemperature = hasInternalBattery && (
            (panelNeedsPower && defaults.bool(forKey: DefaultsKey.monitorPwrTemperature))
                || menuPanelNeeds.batteryTemperature
                || defaults.bool(forKey: DefaultsKey.menuBarBatteryTemperature) || alertBatteryTemperature)
        if defaults.bool(forKey: AppFeature.fanControl.availabilityKey),
           Self.fanTelemetryAvailable {
            plan.needFanSpeed = fullMonitorVisible || menuPanelNeeds.fanSpeed
                || defaults.bool(forKey: DefaultsKey.menuBarFanSpeed)
            plan.needFanSpeedMenuBar = defaults.bool(forKey: DefaultsKey.menuBarFanSpeed)
        }
        plan.needConnectedDevices = fullMonitorVisible
            || (menuPanelNeeds.system && defaults.bool(forKey: DefaultsKey.monitorSysConnectedDevices))
            || menuPanelNeeds.connectedDevices
            || defaults.bool(forKey: DefaultsKey.menuBarConnectedDevices)

        func available(_ feature: AppFeature) -> Bool {
            defaults.bool(forKey: feature.availabilityKey)
        }
        if !available(.monitorCPU) {
            plan.needCPU = false
            plan.needCPUCores = false
            plan.needCPUTemperature = false
        }
        if !available(.monitorGPU) {
            plan.needGPUUsage = false
            plan.needGPUUsageMenuBar = false
            plan.needGPUTemperature = false
        }
        plan.needChipTemperatureMenuBar =
            (available(.monitorCPU) && defaults.bool(forKey: DefaultsKey.menuBarCPUTemperature))
            || (available(.monitorGPU) && defaults.bool(forKey: DefaultsKey.menuBarGPUTemperature))
        if !available(.monitorMemory) { plan.needMemory = false }
        if !available(.monitorNetwork) { plan.needNetwork = false }
        if !available(.monitorDisk) { plan.needDisk = false }
        if !available(.monitorPower) {
            plan.needPower = false
            plan.needPowerDraw = false
            plan.needPeripheralBattery = false
            plan.needBatteryTemperature = false
        }
        if !available(.fanControl) {
            plan.needFanSpeed = false
            plan.needFanSpeedMenuBar = false
        }
        if !available(.connectedDevices) { plan.needConnectedDevices = false }
        return plan
    }

    private func syncPeripheralBatterySampling() {
        let enabled = shouldRun && currentPlan(defaults: .standard).needPeripheralBattery
        if enabled != peripheralSamplingEnabled { peripheralSampleDue = enabled }
        peripheralSamplingEnabled = enabled
        peripheralBatterySampler.setEnabled(enabled)
    }

    private func ensureTimer() {
        syncPeripheralBatterySampling()
        guard shouldSample() else { return }
        syncTimerCadence(plan: currentPlan(defaults: .standard))
        guard timer == nil else { return }
        startTimer()
    }

    private func stopTimerIfIdle() {
        syncPeripheralBatterySampling()
        guard !shouldSample() else { return }
        timer?.invalidate()
        timer = nil
    }

    private func syncTimerCadence(plan: SamplingPlan) {
        lastSyncedPlan = plan
        let foreground = fullMonitorVisible || menuPanelNeeds.any || notchDetailNeeds.any || notchVisible
        let desired = MonitorSamplingPolicy.wakeTicks(for: Self.neededKinds(of: plan),
                                                      intervalSeconds: intervalSeconds,
                                                      foreground: foreground)
        guard desired != scheduledWakeTicks else { return }
        scheduledWakeTicks = desired
        tickCount = MonitorSamplingPolicy.alignedTick(tickCount, wakeTicks: desired)
        if timer != nil {
            restartTimer()
        }
    }

    private static func neededKinds(of plan: SamplingPlan) -> [MonitorSamplingKind] {
        var kinds: [MonitorSamplingKind] = []
        if plan.needCPU { kinds.append(.cpu) }
        if plan.needMemory { kinds.append(.memory) }
        if plan.needNetwork { kinds.append(.network) }
        if plan.needDisk { kinds.append(.disk) }
        if plan.needPower { kinds.append(plan.powerKind) }
        if plan.needPeripheralBattery { kinds.append(.peripheralBattery) }
        if plan.needGPUUsage { kinds.append(plan.gpuUsageKind) }
        if plan.needTemperature { kinds.append(plan.temperatureKind) }
        if plan.needFanSpeed { kinds.append(plan.fanSpeedKind) }
        if plan.needConnectedDevices { kinds.append(.connectedDevices) }
        return kinds
    }

    private func startTimer() {
        let cadenceSeconds = TimeInterval(intervalSeconds * scheduledWakeTicks)
        let t = Timer(timeInterval: cadenceSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = cadenceSeconds * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        startTimer()
    }

    // MARK: - Refresh

    private func refresh(suppressImmediateGPU: Bool = false, forcing: Set<MonitorSamplingKind> = []) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refresh(suppressImmediateGPU: suppressImmediateGPU, forcing: forcing) }
            return
        }
        let defaults = UserDefaults.standard
        let plan = currentPlan(defaults: defaults)
        syncPeripheralBatterySampling()
        guard plan.any else {
            stopTimerIfIdle()
            return
        }
        if refreshInFlight {
            pendingRefresh = true
            pendingRefreshSuppressesGPU = pendingRefreshSuppressesGPU || suppressImmediateGPU
            pendingRefreshForcing.formUnion(forcing)
            return
        }
        syncTimerCadence(plan: plan)
        refreshInFlight = true
        let suppressGPUReadsUntil = self.suppressGPUReadsUntil
        let foregroundSampling = fullMonitorVisible || menuPanelNeeds.any || notchDetailNeeds.any || notchVisible
        let intervalSeconds = self.intervalSeconds
        let tick = tickCount
        tickCount &+= scheduledWakeTicks
        let forcePeripheralSample = plan.needPeripheralBattery && peripheralSampleDue
        if forcePeripheralSample { peripheralSampleDue = false }
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareIfNeeded(needSMC: plan.needSMC,
                                 needTemperature: plan.needTemperature,
                                 needFanSpeed: plan.needFanSpeed)
            let now = ProcessInfo.processInfo.systemUptime

            var next = SystemSnapshot()

            var sampledAnything = false
            func take(_ kind: MonitorSamplingKind) -> Bool {
                let sample = MonitorSamplingPolicy.shouldSample(kind,
                                                                tick: tick,
                                                                intervalSeconds: intervalSeconds,
                                                                foreground: foregroundSampling,
                                                                forced: forcing)
                if sample { sampledAnything = true }
                return sample
            }

            if !plan.needCPUCores {
                self.cpuCoreSampler.reset()
            }
            if plan.needCPU {
                let readsCPU = take(.cpu)
                if readsCPU, plan.needCPUCores {
                    next.cpuCoreUsage = self.cpuCoreSampler.sample(now: now)
                }
                if readsCPU,
                   let cpu = self.readCPUUsage(now: now) {
                    self.lastCPUUsage = cpu
                    self.lastCPUUsageReadAt = now
                    self.missedCPUUsageSamples = 0
                    self.cpuHistory.push(cpu)
                } else if self.missedCPUUsageSamples < 3 {
                    self.missedCPUUsageSamples += 1
                } else {
                    self.lastCPUUsage = nil
                    self.lastCPUUsageReadAt = nil
                }
                next.cpuUsage = self.lastCPUUsage
                next.cpuUsageReadAt = self.lastCPUUsageReadAt
            }

            if plan.needMemory {
                if take(.memory),
                   let (memory, isFresh) = self.stabilizedMemoryReading(now: now) {
                    next.memoryUsed = memory.used
                    next.memoryAppUsed = memory.appUsed
                    next.memoryTotal = memory.total
                    next.memoryCompressed = memory.compressed
                    next.memoryCached = memory.cached
                    next.memorySwapUsed = memory.swapUsed
                    next.memoryPressure = memory.pressure
                    if isFresh, memory.total > 0 {
                        self.memoryHistory.push(Double(memory.used) / Double(memory.total))
                        self.memoryAppHistory.push(Double(memory.appUsed) / Double(memory.total))
                    }
                }
            }

            if plan.needNetwork {
                if take(.network) {
                    let network = self.networkSampler.sample(now: now)
                    next.netDownBytesPerSec = network.downBytesPerSec
                    next.netUpBytesPerSec = network.upBytesPerSec
                    next.netTotalDown = network.totalDown
                    next.netTotalUp = network.totalUp
                    if let down = network.downBytesPerSec { self.netDownHistory.push(down) }
                    if let up = network.upBytesPerSec { self.netUpHistory.push(up) }
                }
            }

            if plan.needDisk {
                if take(.disk) {
                    let disk = self.diskSampler.sample(now: now, refreshMetadata: foregroundSampling)
                    self.lastDiskReading = disk
                    next.disk = disk
                    let ioDevices = disk.uniqueIODevices
                    let readValues = ioDevices.compactMap(\.readBytesPerSec)
                    let writeValues = ioDevices.compactMap(\.writeBytesPerSec)
                    if !readValues.isEmpty {
                        self.diskReadHistory.push(readValues.reduce(0, +))
                    }
                    if !writeValues.isEmpty {
                        self.diskWriteHistory.push(writeValues.reduce(0, +))
                    }
                } else {
                    next.disk = self.lastDiskReading
                }
            }

            if plan.needPower, let powerSampler = self.powerSampler {
                if take(plan.powerKind) {
                    let power = powerSampler.sample()
                    self.lastPowerReading = power
                    next.power = power
                    if let watts = power.systemWatts { self.powerHistory.push(watts) }
                    if let charge = power.chargePercent { self.batteryHistory.push(Double(charge) / 100.0) }
                } else {
                    next.power = self.lastPowerReading
                }
            }

            if plan.needPeripheralBattery {
                if take(.peripheralBattery) || forcePeripheralSample {
                    sampledAnything = true
                    self.lastPeripheralBatterySample = self.peripheralBatterySampler.sample(now: now)
                }
                next.peripheralBatterySample = self.lastPeripheralBatterySample
                next.peripheralBatteries = self.lastPeripheralBatterySample.devices
            }

            if plan.needGPUUsage {
                let suppressGPUForUI = suppressImmediateGPU || now < suppressGPUReadsUntil
                let shouldSampleGPU = !suppressGPUForUI && take(plan.gpuUsageKind)
                if shouldSampleGPU {
                    if let rawGPU = Self.readGPUUsage() {
                        self.lastGPUUsage = MetricFormat.stabilizedGPUUsage(previous: self.lastGPUUsage,
                                                                            current: rawGPU)
                        self.missedGPUUsageSamples = 0
                        if let gpu = self.lastGPUUsage { self.gpuHistory.push(gpu) }
                    } else if self.missedGPUUsageSamples < 3 {
                        self.missedGPUUsageSamples += 1
                    } else {
                        self.lastGPUUsage = nil
                    }
                }
                next.gpuUsage = self.lastGPUUsage
            }
            let temperatureGap = TimeInterval(MonitorSamplingPolicy.sampleStride(
                for: plan.temperatureKind,
                intervalSeconds: intervalSeconds,
                foreground: foregroundSampling) * intervalSeconds)
            let temperatureBridge = max(12, temperatureGap * 2.2)
            if plan.needCPUTemperature {
                if take(plan.temperatureKind) {
                    next.cpuTemperature = TemperatureSensorSelector.stabilizedTemperature(
                        self.cpuTemperature(),
                        cache: &self.cpuTemperatureCache,
                        now: now,
                        maxAge: temperatureBridge,
                        minimum: TemperatureSensorSelector.minimumChipTemperature)
                } else {
                    next.cpuTemperature = self.cpuTemperatureCache?.value
                }
                next.cpuTemperatureReadAt = self.cpuTemperatureCache?.updatedAt
            }
            if plan.needGPUTemperature {
                if take(plan.temperatureKind) {
                    next.gpuTemperature = TemperatureSensorSelector.stabilizedTemperature(
                        self.maxTemperature(of: self.gpuKeys),
                        cache: &self.gpuTemperatureCache,
                        now: now,
                        maxAge: temperatureBridge,
                        minimum: TemperatureSensorSelector.minimumChipTemperature)
                } else {
                    next.gpuTemperature = self.gpuTemperatureCache?.value
                }
            }
            if plan.needBatteryTemperature {
                if take(plan.temperatureKind) {
                    next.batteryTemperature = TemperatureSensorSelector.stabilizedTemperature(
                        self.maxTemperature(of: self.batteryKeys),
                        cache: &self.batteryTemperatureCache,
                        now: now,
                        maxAge: temperatureBridge)
                } else {
                    next.batteryTemperature = self.batteryTemperatureCache?.value
                }
                next.batteryTemperatureReadAt = self.batteryTemperatureCache?.updatedAt
            }
            if plan.needFanSpeed {
                if take(plan.fanSpeedKind) {
                    if let speeds = self.readFanSpeeds() {
                        self.lastFanSpeeds = speeds
                        self.missedFanSpeedSamples = 0
                    } else if self.missedFanSpeedSamples < 3 {
                        self.missedFanSpeedSamples += 1
                    } else {
                        self.lastFanSpeeds = []
                    }
                }
                next.fanSpeeds = self.lastFanSpeeds
            }

            if plan.needConnectedDevices {
                if take(.connectedDevices) {
                    self.lastConnectedDevices = self.usbSampler.sample()
                }
                next.connectedDevices = self.lastConnectedDevices
            }

            next.cpuHistory = plan.needCPU
                ? self.cpuHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.gpuHistory = plan.needGPUUsage
                ? self.gpuHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.memoryHistory = plan.needMemory
                ? self.memoryHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.memoryAppHistory = plan.needMemory
                ? self.memoryAppHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.netDownHistory = plan.needNetwork
                ? self.netDownHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.netUpHistory = plan.needNetwork
                ? self.netUpHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.diskReadHistory = plan.needDisk
                ? self.diskReadHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.diskWriteHistory = plan.needDisk
                ? self.diskWriteHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.systemPowerHistory = plan.needPower
                ? self.powerHistory.publishedValues(whileVisible: foregroundSampling) : []
            next.batteryHistory = plan.needPower
                ? self.batteryHistory.publishedValues(whileVisible: foregroundSampling) : []

            DispatchQueue.main.async {
                let planChanged = plan != self.lastPublishedPlan
                    || foregroundSampling != self.lastPublishedForeground
                if sampledAnything || planChanged {
                    self.snapshot = next
                    self.lastPublishedPlan = plan
                    self.lastPublishedForeground = foregroundSampling
                }
                self.refreshInFlight = false
                let shouldRunPendingRefresh = self.pendingRefresh
                let suppressGPU = self.pendingRefreshSuppressesGPU
                let pendingForcing = self.pendingRefreshForcing
                self.pendingRefresh = false
                self.pendingRefreshSuppressesGPU = false
                self.pendingRefreshForcing = []
                if shouldRunPendingRefresh, self.shouldRun {
                    self.refresh(suppressImmediateGPU: suppressGPU, forcing: pendingForcing)
                }
            }
        }
    }

    private func stabilizedMemoryReading(now: TimeInterval) -> (CachedMemoryReading, isFresh: Bool)? {
        let pressure = Self.readMemoryPressure()
        if let memory = SystemInfo.memoryUsage(), memory.total > 0 {
            let swapUsed = memory.swapUsed ?? memoryCache?.swapUsed
            let stablePressure: MemoryPressure
            switch pressure {
            case .unknown:
                stablePressure = memoryCache?.pressure ?? .unknown
            case .normal, .warning, .critical:
                stablePressure = pressure
            }
            let reading = CachedMemoryReading(used: memory.used,
                                              appUsed: memory.appUsed,
                                              total: memory.total,
                                              compressed: memory.compressed,
                                              cached: memory.cached,
                                              swapUsed: swapUsed,
                                              pressure: stablePressure,
                                              updatedAt: now,
                                              missedSamples: 0)
            memoryCache = reading
            return (reading, true)
        }

        guard var held = memoryCache else { return nil }
        held.missedSamples += 1
        guard held.missedSamples <= 4, now - held.updatedAt <= 12 else {
            memoryCache = nil
            return nil
        }

        switch pressure {
        case .normal, .warning, .critical:
            held.pressure = pressure
        case .unknown:
            break
        }
        memoryCache = held
        return (held, false)
    }

    // MARK: - Sensor preparation

    private func prepareIfNeeded(needSMC: Bool,
                                 needTemperature: Bool,
                                 needFanSpeed: Bool) {
        if needSMC, !smcTried {
            smcTried = true
            smc = SMCClient()
            cpuTemperaturePlatform = TemperatureSensorSelector.currentPlatform()
            powerSampler = PowerSampler(smc: smc)
        }
        guard let client = smc else { return }

        if needFanSpeed, !fanKeysPrepared {
            fanKeysPrepared = true
            let count = Self.fanTelemetryCount
            if count > 0 {
                let keys = (0..<count).compactMap { client.key(named: "F\($0)Ac") }
                if keys.count == count { fanKeys = keys }
            }
        }

        guard needTemperature, !tempKeysPrepared else { return }
        tempKeysPrepared = true

        let all = client.keys { name in
            TemperatureSensorSelector.isCPUTemperatureKey(name, platform: cpuTemperaturePlatform)
                || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        cpuKeys = all.filter {
            TemperatureSensorSelector.isCPUTemperatureKey($0.name,
                                                          platform: cpuTemperaturePlatform)
        }
        preferredCPUKeys = cpuKeys.filter {
            TemperatureSensorSelector.isCPUCoreKey($0.name, platform: cpuTemperaturePlatform)
        }
        let preferredNames = Set(preferredCPUKeys.map(\.name))
        fallbackCPUKeys = cpuKeys.filter { !preferredNames.contains($0.name) }
        gpuKeys = all.filter { $0.name.hasPrefix("Tg") }
        batteryKeys = all.filter { $0.name.hasPrefix("TB") }
    }

    static let fanTelemetryCount: Int = {
        guard let client = SMCClient(),
              let countKey = client.key(named: "FNum"),
              let countValue = client.readValue(countKey),
              let count = FanControlPolicy.fanCount(from: countValue) else { return 0 }
        let readings = (0..<count).map { index -> Double? in
            guard let key = client.key(named: "F\(index)Ac") else { return nil }
            return client.readValue(key)
        }
        guard FanControlPolicy.telemetryReadings(expectedCount: count,
                                                 readings: readings) != nil else { return 0 }
        return count
    }()

    static var fanTelemetryAvailable: Bool { fanTelemetryCount > 0 }

    private func readFanSpeeds() -> [Double]? {
        guard let smc, !fanKeys.isEmpty else { return nil }
        return FanControlPolicy.telemetryReadings(expectedCount: fanKeys.count,
                                                  readings: fanKeys.map { smc.readValue($0) })
    }

    private func cpuTemperature() -> Double? {
        guard smc != nil else { return nil }
        var readings = temperatureReadings(of: preferredCPUKeys)
        if let value = TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                         platform: cpuTemperaturePlatform) {
            return value
        }
        readings += temperatureReadings(of: fallbackCPUKeys)
        return TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                 platform: cpuTemperaturePlatform)
    }

    private func temperatureReadings(of keys: [SMCClient.Key]) -> [(key: String, value: Double)] {
        guard let smc else { return [] }
        return keys.compactMap { key -> (key: String, value: Double)? in
            guard let value = smc.readValue(key) else { return nil }
            return (key.name, value)
        }
    }

    private func maxTemperature(of keys: [SMCClient.Key]) -> Double? {
        guard let smc else { return nil }
        let values = keys.compactMap { key -> Double? in
            guard let v = smc.readValue(key), v > 1, v < 125 else { return nil }
            return v
        }
        return values.max()
    }

    // MARK: - CPU usage

    private func readCPUUsage(now: TimeInterval) -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total, now) }
        guard let previous = previousCPUTicks, total > previous.total else { return nil }
        guard now - previous.time <= 12.5 else {
            lastCPUUsage = nil
            lastCPUUsageReadAt = nil
            return nil
        }
        return Double(busy - previous.busy) / Double(total - previous.total)
    }

    // MARK: - GPU usage

    private static func readGPUUsage() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let ref = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString,
                                                            kCFAllocatorDefault, 0),
                  let stats = ref.takeRetainedValue() as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? Int
            else { continue }
            return Double(utilization) / 100.0
        }
        return nil
    }

    // MARK: - Memory pressure

    private static func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(kernelLevel: level)
    }
}
