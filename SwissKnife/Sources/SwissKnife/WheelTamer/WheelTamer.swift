import AppKit
import ApplicationServices
import Foundation

protocol WheelTamerDelegate: AnyObject {
    func wheelTamerDidUpdate(_ tamer: WheelTamer)
}

final class WheelTamer {
    weak var delegate: WheelTamerDelegate?

    private let settingsStore = WheelStore.shared
    private let logger = WheelLogger.shared
    private let buildVersion = "ATASWheelTamer v2026_0902_0002"

    private enum TargetApp {
        static let atasBundleID = "com.atas.platform"
        // Parallels 在虚拟机窗口聚焦时报告为 com.parallels.desktop.console，
        // 其他场景可能是 com.parallels.desktop，统一用前缀匹配
        static let parallelsBundleIDPrefix = "com.parallels.desktop"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentFrontmostBundleID = ""
    private var accessibilityTrusted = false
    private var eventTapEnabled = false
    private var observedEventCount = 0
    private var scaledEventCount = 0
    private var lastEventSample: WheelEventSample?
    private var remainders = FieldRemainders()
    private struct FieldRemainders {
        var deltaAxis1 = 0.0
        var deltaAxis2 = 0.0
        var fixedAxis1 = 0.0
        var fixedAxis2 = 0.0
        var pointAxis1 = 0.0
        var pointAxis2 = 0.0
    }

    func start() {
        updateFrontmostApp()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        installEventTap(promptForTrust: true)
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        teardownEventTap()
    }

    func restart() {
        logger.log("restart_requested")
        installEventTap(promptForTrust: true, forceRestart: true)
    }

    func refreshSettings() {
        resetRemainders()
        logger.log("settings_updated", details: [
            "atasEnabled": String(settingsStore.current.atas.enabled),
            "atasScalePercent": String(settingsStore.current.atas.scalePercent),
            "parallelsEnabled": String(settingsStore.current.parallels.enabled),
            "parallelsScalePercent": String(settingsStore.current.parallels.scalePercent)
        ])
        delegate?.wheelTamerDidUpdate(self)
    }

    func currentSnapshot() -> WheelTamerSnapshot {
        WheelTamerSnapshot(
            generatedAt: Date(),
            build: buildVersion,
            accessibilityTrusted: accessibilityTrusted,
            eventTapInstalled: eventTap != nil,
            eventTapEnabled: eventTapEnabled,
            atasEnabled: settingsStore.current.atas.enabled,
            atasScalePercent: settingsStore.current.atas.scalePercent,
            parallelsEnabled: settingsStore.current.parallels.enabled,
            parallelsScalePercent: settingsStore.current.parallels.scalePercent,
            currentFrontmostBundleID: currentFrontmostBundleID,
            atasFrontmost: currentFrontmostBundleID == TargetApp.atasBundleID,
            parallelsFrontmost: isParallelsBundleID(currentFrontmostBundleID),
            scaledEventCount: scaledEventCount,
            observedEventCount: observedEventCount,
            lastEventSample: lastEventSample,
            logDirectory: logger.logDirectoryPath()
        )
    }

    @objc private func frontmostAppDidChange(_ notification: Notification) {
        updateFrontmostApp()
        delegate?.wheelTamerDidUpdate(self)
    }

    private func updateFrontmostApp() {
        let nextBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if nextBundleID != currentFrontmostBundleID {
            currentFrontmostBundleID = nextBundleID
            resetRemainders()
        }
    }

    private func installEventTap(promptForTrust: Bool, forceRestart: Bool = false) {
        if forceRestart {
            teardownEventTap()
        }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: promptForTrust] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)

        guard accessibilityTrusted else {
            logger.log("accessibility_not_trusted")
            eventTapEnabled = false
            delegate?.wheelTamerDidUpdate(self)
            return
        }

        guard eventTap == nil else {
            eventTapEnabled = true
            delegate?.wheelTamerDidUpdate(self)
            return
        }

        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let tamer = Unmanaged<WheelTamer>.fromOpaque(userInfo).takeUnretainedValue()
                return tamer.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.log("event_tap_create_failed")
            eventTapEnabled = false
            delegate?.wheelTamerDidUpdate(self)
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        eventTapEnabled = true
        logger.log("event_tap_started", details: [
            "atasEnabled": String(settingsStore.current.atas.enabled),
            "atasScalePercent": String(settingsStore.current.atas.scalePercent),
            "parallelsEnabled": String(settingsStore.current.parallels.enabled),
            "parallelsScalePercent": String(settingsStore.current.parallels.scalePercent)
        ])
        delegate?.wheelTamerDidUpdate(self)
    }

    private func teardownEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        eventTapEnabled = false
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            eventTapEnabled = true
            logger.log("event_tap_reenabled", details: ["reason": "\(type.rawValue)"])
            delegate?.wheelTamerDidUpdate(self)
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        observedEventCount += 1

        guard let activeTarget = activeTarget() else {
            return Unmanaged.passUnretained(event)
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let factor = settingsStore.current[activeTarget].scalePercent / 100.0
        let sample = rewriteMouseEvent(event: event, isContinuous: isContinuous, factor: factor)
        lastEventSample = sample

        guard sample.emittedLineAxis1 != 0 || sample.emittedLineAxis2 != 0 else {
            return nil
        }

        guard let replacement = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
            units: .line,
            wheelCount: 2,
            wheel1: sample.emittedLineAxis1,
            wheel2: sample.emittedLineAxis2,
            wheel3: 0
        ) else {
            return nil
        }

        replacement.flags = event.flags
        replacement.location = event.location
        replacement.tapPostEvent(proxy)
        scaledEventCount += 1
        return nil
    }

    private func activeTarget() -> TargetKind? {
        if currentFrontmostBundleID == TargetApp.atasBundleID, settingsStore.current.atas.enabled {
            return .atas
        }
        if isParallelsBundleID(currentFrontmostBundleID), settingsStore.current.parallels.enabled {
            return .parallels
        }
        return nil
    }

    private func isParallelsBundleID(_ bundleID: String) -> Bool {
        bundleID == TargetApp.parallelsBundleIDPrefix || bundleID.hasPrefix(TargetApp.parallelsBundleIDPrefix + ".")
    }

    private func rewriteMouseEvent(event: CGEvent, isContinuous: Bool, factor: Double) -> WheelEventSample {
        let clampedFactor = max(0.0, min(1.0, factor))

        let rawDeltaAxis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let rawDeltaAxis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let rawFixedAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let rawFixedAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let rawPointAxis1 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let rawPointAxis2 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)

        let inputAxis1 = preferredInputValue(delta: rawDeltaAxis1, fixed: rawFixedAxis1, point: rawPointAxis1)
        let inputAxis2 = preferredInputValue(delta: rawDeltaAxis2, fixed: rawFixedAxis2, point: rawPointAxis2)
        let emittedAxis1 = accumulatedLineStep(inputAxis1 * clampedFactor, remainder: &remainders.pointAxis1)
        let emittedAxis2 = accumulatedLineStep(inputAxis2 * clampedFactor, remainder: &remainders.pointAxis2)

        return WheelEventSample(
            at: Date(),
            isContinuous: isContinuous,
            rawDeltaAxis1: rawDeltaAxis1,
            rawDeltaAxis2: rawDeltaAxis2,
            rawFixedAxis1: rawFixedAxis1,
            rawFixedAxis2: rawFixedAxis2,
            rawPointAxis1: rawPointAxis1,
            rawPointAxis2: rawPointAxis2,
            scaledDeltaAxis1: Int64(emittedAxis1),
            scaledDeltaAxis2: Int64(emittedAxis2),
            scaledFixedAxis1: Double(emittedAxis1),
            scaledFixedAxis2: Double(emittedAxis2),
            scaledPointAxis1: Double(emittedAxis1),
            scaledPointAxis2: Double(emittedAxis2),
            emittedLineAxis1: Int32(clamping: emittedAxis1),
            emittedLineAxis2: Int32(clamping: emittedAxis2),
            swallowedOriginalEvent: true
        )
    }

    private func preferredInputValue(delta: Int64, fixed: Double, point: Double) -> Double {
        if abs(point) > 0.000_001 {
            return point
        }
        if abs(fixed) > 0.000_001 {
            return fixed
        }
        return Double(delta)
    }

    private func accumulatedLineStep(_ value: Double, remainder: inout Double) -> Int {
        let total = value + remainder
        let emitted = Int(total.rounded(.towardZero))
        remainder = total - Double(emitted)
        return emitted
    }

    private func resetRemainders() {
        remainders = FieldRemainders()
    }

}
