import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import os.lock

// One-shot diagnostic probe. It intentionally records no key characters, process
// identities, window data, or unfiltered SkyLight dictionaries.

private struct Options {
    var duration: TimeInterval = 300
    var outputPath = "/private/tmp/tungsten-space-input-probe.jsonl"

    static func parse() -> Options {
        var result = Options()
        var index = 1
        while index < CommandLine.arguments.count {
            switch CommandLine.arguments[index] {
            case "--duration" where index + 1 < CommandLine.arguments.count:
                result.duration = Double(CommandLine.arguments[index + 1]) ?? result.duration
                index += 2
            case "--output" where index + 1 < CommandLine.arguments.count:
                result.outputPath = CommandLine.arguments[index + 1]
                index += 2
            case "--help", "-h":
                print("usage: TungstenSpaceInputProbe [--duration SECONDS] [--output PATH]")
                exit(0)
            default:
                fputs("unknown argument: \(CommandLine.arguments[index])\n", stderr)
                exit(64)
            }
        }
        return result
    }
}

private enum Monotonic {
    private static var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func nowNanoseconds() -> UInt64 {
        let ticks = mach_continuous_time()
        let numerator = UInt64(timebase.numer)
        let denominator = UInt64(timebase.denom)
        return ticks * numerator / denominator
    }

    static func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }
}

private enum InputSource: String {
    case cgTap
    case appKitGlobal
}

private enum InputKind: String {
    case keyDown
    case scrollWheel
    case gesture
    case swipe
    case beginGesture
    case endGesture
    case tapDisabledTimeout
    case tapDisabledUserInput
}

private struct InputSample {
    var sequence: UInt64
    let monotonicNS: UInt64
    let source: InputSource
    let kind: InputKind
    var flags: UInt64 = 0
    var keyCode: Int64 = -1
    var isRepeat: Bool = false
    var deltaX: Double = 0
    var deltaY: Double = 0
    var scrollingDeltaX: Double = 0
    var scrollingDeltaY: Double = 0
    var phase: UInt64 = 0
    var momentumPhase: UInt64 = 0
    var isContinuous: Bool = false
    var hasPreciseDeltas: Bool = false
    var isDirectionInverted: Bool = false
    var subtype: Int = 0
}

private func arrowDirection(keyCode: Int64, isRepeat: Bool) -> String? {
    guard !isRepeat else { return nil }
    if keyCode == 123 { return "left" }
    if keyCode == 124 { return "right" }
    return nil
}

private func exactSpaceShortcutDirection(keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> String? {
    guard let direction = arrowDirection(keyCode: keyCode, isRepeat: isRepeat) else { return nil }
    let relevant: CGEventFlags = [
        .maskControl,
        .maskCommand,
        .maskAlternate,
        .maskShift,
        .maskHelp,
    ]
    guard flags.intersection(relevant) == [.maskControl] else { return nil }
    return direction
}

private func modifierNames(_ flags: CGEventFlags) -> [String] {
    let known: [(CGEventFlags, String)] = [
        (.maskControl, "control"),
        (.maskCommand, "command"),
        (.maskAlternate, "option"),
        (.maskShift, "shift"),
        (.maskSecondaryFn, "fn"),
        (.maskHelp, "help"),
        (.maskNumericPad, "numericPad"),
        (.maskAlphaShift, "capsLock"),
        (.maskNonCoalesced, "nonCoalesced"),
    ]
    return known.compactMap { flags.contains($0.0) ? $0.1 : nil }
}

private final class InputBuffer {
    private var lock = os_unfair_lock_s()
    private var nextSequence: UInt64 = 1
    private var samples: [InputSample] = []

    func append(_ sample: InputSample) {
        os_unfair_lock_lock(&lock)
        var stamped = sample
        stamped.sequence = nextSequence
        nextSequence &+= 1
        samples.append(stamped)
        os_unfair_lock_unlock(&lock)
    }

    func drain() -> [InputSample] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let result = samples
        samples.removeAll(keepingCapacity: true)
        return result
    }
}

private final class JSONLWriter {
    private let handle: FileHandle

    init(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.handle = handle
        try handle.truncate(atOffset: 0)
    }

    func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let newline = "\n".data(using: .utf8) else {
            return
        }
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: newline)
    }

    func close() {
        try? handle.synchronize()
        try? handle.close()
    }
}

private struct SpaceValue: Equatable {
    let id64: UInt64?
    let type: Int?

    var json: [String: Any] {
        var result: [String: Any] = [:]
        result["id64"] = id64.map { String($0) } ?? NSNull()
        result["type"] = type ?? NSNull()
        return result
    }
}

private struct DisplaySpaces: Equatable {
    let displayUUID: String?
    let spaces: [SpaceValue]
    let current: SpaceValue

    var json: [String: Any] {
        [
            "displayUUID": displayUUID ?? NSNull(),
            "spaces": spaces.map(\.json),
            "current": current.json,
        ]
    }
}

private final class ManagedSpacesReader {
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias CopyManagedSpaces = @convention(c) (UInt32) -> Unmanaged<CFArray>?

    private let handle: UnsafeMutableRawPointer
    private let mainConnection: MainConnection
    private let copyManagedSpaces: CopyManagedSpaces

    init?() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let copySymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces") else {
            return nil
        }
        self.handle = handle
        self.mainConnection = unsafeBitCast(mainSymbol, to: MainConnection.self)
        self.copyManagedSpaces = unsafeBitCast(copySymbol, to: CopyManagedSpaces.self)
    }

    deinit {
        dlclose(handle)
    }

    func read() -> [DisplaySpaces]? {
        guard let unmanaged = copyManagedSpaces(mainConnection()),
              let rawDisplays = unmanaged.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        return rawDisplays.map { display in
            let rawSpaces = display["Spaces"] as? [[String: Any]] ?? []
            let rawCurrent = display["Current Space"] as? [String: Any] ?? [:]
            return DisplaySpaces(
                displayUUID: display["Display Identifier"] as? String,
                spaces: rawSpaces.map(Self.projectSpace),
                current: Self.projectSpace(rawCurrent)
            )
        }
    }

    private static func projectSpace(_ raw: [String: Any]) -> SpaceValue {
        let id64 = (raw["id64"] as? NSNumber)?.uint64Value
        let type = (raw["type"] as? NSNumber)?.intValue
        return SpaceValue(id64: id64, type: type)
    }
}

private final class SessionEventTapThread {
    private let buffer: InputBuffer
    private var lock = os_unfair_lock_s()
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var thread: Thread?
    private let started = DispatchSemaphore(value: 0)
    private(set) var startupError: String?

    init(buffer: InputBuffer) {
        self.buffer = buffer
    }

    func start() -> Bool {
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "TungstenSpaceInputProbe.EventTap"
        self.thread = thread
        thread.start()
        _ = started.wait(timeout: .now() + 3)
        return startupError == nil && eventTap != nil
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        let loop = runLoop
        os_unfair_lock_unlock(&lock)
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            if let tap = self?.eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            CFRunLoopStop(loop)
        }
        CFRunLoopWakeUp(loop)
        let deadline = Date().addingTimeInterval(1)
        while thread?.isExecuting == true && Date() < deadline {
            usleep(1_000)
        }
    }

    private func run() {
        autoreleasepool {
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            let info = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.callback,
                userInfo: info
            ) else {
                startupError = "CGEvent.tapCreate returned nil (Accessibility permission may be missing)"
                started.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let loop = CFRunLoopGetCurrent()
            os_unfair_lock_lock(&lock)
            eventTap = tap
            runLoop = loop
            os_unfair_lock_unlock(&lock)
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            started.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
            os_unfair_lock_lock(&lock)
            eventTap = nil
            runLoop = nil
            os_unfair_lock_unlock(&lock)
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<SessionEventTapThread>.fromOpaque(userInfo).takeUnretainedValue()
        owner.capture(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private func capture(type: CGEventType, event: CGEvent) {
        let now = Monotonic.nowNanoseconds()
        var sample: InputSample
        switch type {
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            guard arrowDirection(keyCode: keyCode, isRepeat: isRepeat) != nil else {
                return
            }
            sample = InputSample(
                sequence: 0,
                monotonicNS: now,
                source: .cgTap,
                kind: .keyDown,
                flags: event.flags.rawValue,
                keyCode: keyCode,
                isRepeat: isRepeat
            )
        case .scrollWheel:
            sample = InputSample(
                sequence: 0,
                monotonicNS: now,
                source: .cgTap,
                kind: .scrollWheel,
                flags: event.flags.rawValue,
                deltaX: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                deltaY: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                scrollingDeltaX: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                scrollingDeltaY: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
                phase: UInt64(max(0, event.getIntegerValueField(.scrollWheelEventScrollPhase))),
                momentumPhase: UInt64(max(0, event.getIntegerValueField(.scrollWheelEventMomentumPhase))),
                isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            )
        case .tapDisabledByTimeout:
            sample = InputSample(sequence: 0, monotonicNS: now, source: .cgTap, kind: .tapDisabledTimeout)
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .tapDisabledByUserInput:
            sample = InputSample(sequence: 0, monotonicNS: now, source: .cgTap, kind: .tapDisabledUserInput)
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            return
        }
        buffer.append(sample)
    }
}

private struct Candidate {
    enum Kind: String { case keyboard, horizontalGesture }
    let id: UInt64
    let kind: Kind
    let startNS: UInt64
    var lastNS: UInt64
    var direction: String
    var matched = false
    var eventCount = 0
    var totalX: Double = 0
    var peakAbsX: Double = 0
    var positiveSamples = 0
    var negativeSamples = 0
    var directionReversals = 0
    var lastNonzeroSign = 0
    var sourceKinds: [String: Int] = [:]
    var phaseMask: UInt64 = 0
    var momentumPhaseMask: UInt64 = 0
    var sawBegin = false
    var sawEnd = false

    mutating func record(_ sample: InputSample) {
        lastNS = sample.monotonicNS
        eventCount += 1
        sourceKinds["\(sample.source.rawValue):\(sample.kind.rawValue)", default: 0] += 1
        phaseMask |= sample.phase
        momentumPhaseMask |= sample.momentumPhase
        sawBegin = sawBegin || sample.kind == .beginGesture
        sawEnd = sawEnd || sample.kind == .endGesture

        let x = sample.scrollingDeltaX != 0 ? sample.scrollingDeltaX : sample.deltaX
        totalX += x
        peakAbsX = max(peakAbsX, abs(x))
        let sign = x > 0 ? 1 : (x < 0 ? -1 : 0)
        if sign > 0 { positiveSamples += 1 }
        if sign < 0 { negativeSamples += 1 }
        if sign != 0 {
            if lastNonzeroSign != 0, lastNonzeroSign != sign {
                directionReversals += 1
            }
            lastNonzeroSign = sign
            direction = sign > 0 ? "x-positive" : "x-negative"
        }
    }
}

private final class Correlator {
    private let writer: JSONLWriter
    private var nextCandidateID: UInt64 = 1
    private var candidates: [Candidate] = []
    private var previousSpaces: [DisplaySpaces]
    private var pendingGestureStartNS: UInt64?

    init(writer: JSONLWriter, initialSpaces: [DisplaySpaces]) {
        self.writer = writer
        self.previousSpaces = initialSpaces
    }

    func consume(_ sample: InputSample, currentSpaces: [DisplaySpaces]) {
        writer.write(rawJSON(sample))

        if let direction = keyboardDirection(sample) {
            addKeyboardCandidate(at: sample.monotonicNS, direction: direction, spaces: currentSpaces)
        } else {
            consumeGestureSample(sample, spaces: currentSpaces)
        }
    }

    func recordSpaceNotification(at timeNS: UInt64) {
        writer.write([
            "record": "spaceNotification",
            "t_ms": Monotonic.milliseconds(timeNS),
            "monotonic_ns": String(timeNS),
        ])
    }

    func observeSpaces(
        at timeNS: UInt64,
        spaces: [DisplaySpaces],
        source: String,
        logUnchanged: Bool
    ) {
        let changes = Self.changes(from: previousSpaces, to: spaces)
        previousSpaces = spaces
        guard !changes.isEmpty else {
            if logUnchanged {
                writer.write([
                    "record": "spaceNotification",
                    "t_ms": Monotonic.milliseconds(timeNS),
                    "monotonic_ns": String(timeNS),
                    "changed": false,
                    "spaces": spaces.map(\.json),
                ])
            }
            return
        }

        let eligible = candidates.indices.filter {
            !candidates[$0].matched && candidates[$0].lastNS <= timeNS && timeNS - candidates[$0].lastNS <= 2_000_000_000
        }
        let matchedIndex = eligible.max { candidates[$0].lastNS < candidates[$1].lastNS }
        var correlation: Any = NSNull()
        if let index = matchedIndex {
            candidates[index].matched = true
            let candidate = candidates[index]
            correlation = [
                "candidate_id": candidate.id,
                "kind": candidate.kind.rawValue,
                "candidate_direction": candidate.direction,
                "first_lead_ms": Monotonic.milliseconds(timeNS - candidate.startNS),
                "last_lead_ms": Monotonic.milliseconds(timeNS - candidate.lastNS),
                "event_count": candidate.eventCount,
                "gesture_summary": gestureSummary(candidate),
            ] as [String: Any]
        }

        writer.write([
            "record": "spaceTransition",
            "t_ms": Monotonic.milliseconds(timeNS),
            "monotonic_ns": String(timeNS),
            "detected_by": source,
            "changes": changes,
            "correlation": correlation,
            "spaces": spaces.map(\.json),
        ])
    }

    func expire(at timeNS: UInt64) {
        var retained: [Candidate] = []
        for candidate in candidates {
            if timeNS >= candidate.lastNS && timeNS - candidate.lastNS >= 2_000_000_000 {
                if !candidate.matched {
                    writer.write([
                        "record": "candidateOutcome",
                        "t_ms": Monotonic.milliseconds(timeNS),
                        "candidate_id": candidate.id,
                        "kind": candidate.kind.rawValue,
                        "direction": candidate.direction,
                        "event_count": candidate.eventCount,
                        "outcome": "cancelled/no-transition",
                        "gesture_summary": gestureSummary(candidate),
                    ])
                }
            } else {
                retained.append(candidate)
            }
        }
        candidates = retained
    }

    func finishUnmatched(at timeNS: UInt64) {
        for candidate in candidates where !candidate.matched {
            writer.write([
                "record": "candidateOutcome",
                "t_ms": Monotonic.milliseconds(timeNS),
                "candidate_id": candidate.id,
                "kind": candidate.kind.rawValue,
                "direction": candidate.direction,
                "event_count": candidate.eventCount,
                "outcome": "probe-stopped-before-2s",
                "gesture_summary": gestureSummary(candidate),
            ])
        }
        candidates.removeAll()
    }

    private func addKeyboardCandidate(at timeNS: UInt64, direction: String, spaces: [DisplaySpaces]) {
        var candidate = Candidate(
            id: nextCandidateID,
            kind: .keyboard,
            startNS: timeNS,
            lastNS: timeNS,
            direction: direction
        )
        nextCandidateID &+= 1
        candidate.eventCount = 1
        candidates.append(candidate)
        writer.write([
            "record": "candidate",
            "t_ms": Monotonic.milliseconds(timeNS),
            "monotonic_ns": String(timeNS),
            "candidate_id": candidate.id,
            "kind": Candidate.Kind.keyboard.rawValue,
            "direction": direction,
            "possible_targets": possibleTargets(direction: direction, spaces: spaces),
        ])
    }

    private func consumeGestureSample(_ sample: InputSample, spaces: [DisplaySpaces]) {
        switch sample.kind {
        case .beginGesture:
            pendingGestureStartNS = sample.monotonicNS
            if let index = recentGestureCandidateIndex(for: sample.monotonicNS) {
                candidates[index].record(sample)
            }
            return
        case .endGesture:
            if let index = recentGestureCandidateIndex(for: sample.monotonicNS) {
                candidates[index].record(sample)
            }
            pendingGestureStartNS = nil
            return
        case .gesture, .swipe, .scrollWheel:
            guard isHorizontalMotion(sample) else { return }
        default:
            return
        }

        if let index = recentGestureCandidateIndex(for: sample.monotonicNS) {
            candidates[index].record(sample)
            return
        }
        let startNS = pendingGestureStartNS.flatMap {
            sample.monotonicNS >= $0 && sample.monotonicNS - $0 <= 300_000_000 ? $0 : nil
        } ?? sample.monotonicNS
        var candidate = Candidate(
            id: nextCandidateID,
            kind: .horizontalGesture,
            startNS: startNS,
            lastNS: sample.monotonicNS,
            direction: horizontalDirection(sample)
        )
        nextCandidateID &+= 1
        candidate.record(sample)
        candidates.append(candidate)
        writer.write([
            "record": "candidate",
            "t_ms": Monotonic.milliseconds(startNS),
            "monotonic_ns": String(startNS),
            "candidate_id": candidate.id,
            "kind": Candidate.Kind.horizontalGesture.rawValue,
            "direction": candidate.direction,
            "possible_targets": possibleTargets(direction: candidate.direction, spaces: spaces),
        ])
    }

    private func recentGestureCandidateIndex(for timeNS: UInt64) -> Int? {
        candidates.indices.last(where: {
            candidates[$0].kind == .horizontalGesture
                && !candidates[$0].matched
                && timeNS >= candidates[$0].lastNS
                && timeNS - candidates[$0].lastNS <= 300_000_000
        })
    }

    private func gestureSummary(_ candidate: Candidate) -> [String: Any] {
        guard candidate.kind == .horizontalGesture else { return [:] }
        return [
            "duration_ms": Monotonic.milliseconds(candidate.lastNS - candidate.startNS),
            "total_x": candidate.totalX,
            "peak_abs_x": candidate.peakAbsX,
            "positive_samples": candidate.positiveSamples,
            "negative_samples": candidate.negativeSamples,
            "direction_reversals": candidate.directionReversals,
            "source_kinds": candidate.sourceKinds,
            "phase_mask": candidate.phaseMask,
            "momentum_phase_mask": candidate.momentumPhaseMask,
            "saw_begin": candidate.sawBegin,
            "saw_end": candidate.sawEnd,
        ]
    }

    private func rawJSON(_ sample: InputSample) -> [String: Any] {
        var result: [String: Any] = [
            "record": "input",
            "sequence": sample.sequence,
            "t_ms": Monotonic.milliseconds(sample.monotonicNS),
            "monotonic_ns": String(sample.monotonicNS),
            "source": sample.source.rawValue,
            "kind": sample.kind.rawValue,
        ]
        if sample.kind == .keyDown {
            result["direction"] = arrowDirection(keyCode: sample.keyCode, isRepeat: sample.isRepeat) ?? "unknown"
            result["modifiers"] = modifierNames(CGEventFlags(rawValue: sample.flags))
        }
        if sample.kind == .scrollWheel || sample.kind == .gesture || sample.kind == .swipe
            || sample.kind == .beginGesture || sample.kind == .endGesture {
            result["delta_x"] = sample.deltaX
            result["delta_y"] = sample.deltaY
            result["scrolling_delta_x"] = sample.scrollingDeltaX
            result["scrolling_delta_y"] = sample.scrollingDeltaY
            result["phase"] = sample.phase
            result["momentum_phase"] = sample.momentumPhase
            result["is_continuous"] = sample.isContinuous
            result["has_precise_deltas"] = sample.hasPreciseDeltas
            result["direction_inverted"] = sample.isDirectionInverted
            result["subtype"] = sample.subtype
        }
        return result
    }

    private func keyboardDirection(_ sample: InputSample) -> String? {
        guard sample.source == .cgTap, sample.kind == .keyDown, !sample.isRepeat else { return nil }
        return exactSpaceShortcutDirection(
            keyCode: sample.keyCode,
            flags: CGEventFlags(rawValue: sample.flags),
            isRepeat: sample.isRepeat
        )
    }

    private func isHorizontalMotion(_ sample: InputSample) -> Bool {
        let x = abs(sample.scrollingDeltaX) + abs(sample.deltaX)
        let y = abs(sample.scrollingDeltaY) + abs(sample.deltaY)
        return x > 0 && x >= y
    }

    private func horizontalDirection(_ sample: InputSample) -> String {
        let x = sample.scrollingDeltaX != 0 ? sample.scrollingDeltaX : sample.deltaX
        if x > 0 { return "x-positive" }
        if x < 0 { return "x-negative" }
        return "none"
    }

    private func possibleTargets(direction: String, spaces: [DisplaySpaces]) -> [[String: Any]] {
        spaces.map { display in
            guard let currentID = display.current.id64,
                  let currentIndex = display.spaces.firstIndex(where: { $0.id64 == currentID }) else {
                return [
                    "displayUUID": display.displayUUID ?? NSNull(),
                    "current_id64": display.current.id64.map(String.init) ?? NSNull(),
                    "target_id64": NSNull(),
                    "exists": false,
                ]
            }
            let targetIndex: Int?
            if direction == "left" {
                targetIndex = currentIndex > 0 ? currentIndex - 1 : nil
            } else if direction == "right" {
                targetIndex = currentIndex + 1 < display.spaces.count ? currentIndex + 1 : nil
            } else {
                targetIndex = nil
            }
            let target = targetIndex.map { display.spaces[$0] }
            return [
                "displayUUID": display.displayUUID ?? NSNull(),
                "current_id64": String(currentID),
                "current_type": display.current.type ?? NSNull(),
                "target_id64": target?.id64.map(String.init) ?? NSNull(),
                "target_type": target?.type ?? NSNull(),
                "exists": target != nil,
            ]
        }
    }

    private static func changes(from old: [DisplaySpaces], to new: [DisplaySpaces]) -> [[String: Any]] {
        let oldByDisplay = Dictionary(uniqueKeysWithValues: old.compactMap { display in
            display.displayUUID.map { ($0, display) }
        })
        return new.compactMap { display in
            guard let uuid = display.displayUUID,
                  let previous = oldByDisplay[uuid],
                  previous.current.id64 != display.current.id64 else { return nil }
            let oldIndex = previous.spaces.firstIndex(where: { $0.id64 == previous.current.id64 })
            let newIndex = display.spaces.firstIndex(where: { $0.id64 == display.current.id64 })
            let direction: String
            if let oldIndex, let newIndex {
                direction = newIndex < oldIndex ? "left" : (newIndex > oldIndex ? "right" : "unknown")
            } else {
                direction = "unknown"
            }
            return [
                "displayUUID": uuid,
                "from": previous.current.json,
                "to": display.current.json,
                "direction": direction,
            ]
        }
    }
}

private func appKitSample(from event: NSEvent, buffer: InputBuffer) -> InputSample? {
    let kind: InputKind
    switch event.type {
    case .scrollWheel: kind = .scrollWheel
    case .gesture: kind = .gesture
    case .swipe: kind = .swipe
    case .beginGesture: kind = .beginGesture
    case .endGesture: kind = .endGesture
    default: return nil
    }
    return InputSample(
        sequence: 0,
        monotonicNS: Monotonic.nowNanoseconds(),
        source: .appKitGlobal,
        kind: kind,
        flags: UInt64(event.modifierFlags.rawValue),
        deltaX: Double(event.deltaX),
        deltaY: Double(event.deltaY),
        scrollingDeltaX: Double(event.scrollingDeltaX),
        scrollingDeltaY: Double(event.scrollingDeltaY),
        phase: UInt64(event.phase.rawValue),
        momentumPhase: UInt64(event.momentumPhase.rawValue),
        isContinuous: false,
        hasPreciseDeltas: event.hasPreciseScrollingDeltas,
        isDirectionInverted: event.isDirectionInvertedFromDevice,
        subtype: Int(event.subtype.rawValue)
    )
}

private let options = Options.parse()
private let buffer = InputBuffer()

guard let writer = try? JSONLWriter(path: options.outputPath) else {
    fputs("cannot open output: \(options.outputPath)\n", stderr)
    exit(74)
}
guard let spacesReader = ManagedSpacesReader(), let initialSpaces = spacesReader.read() else {
    writer.write(["record": "fatal", "error": "SkyLight managed spaces unavailable"])
    writer.close()
    fputs("SkyLight managed spaces unavailable\n", stderr)
    exit(69)
}

private let tapThread = SessionEventTapThread(buffer: buffer)
guard tapThread.start() else {
    let error = tapThread.startupError ?? "event tap startup failed"
    writer.write(["record": "fatal", "error": error])
    writer.close()
    fputs("\(error)\n", stderr)
    exit(77)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let eventMask: NSEvent.EventTypeMask = [.scrollWheel, .gesture, .swipe, .beginGesture, .endGesture]
let appKitMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { event in
    if let sample = appKitSample(from: event, buffer: buffer) {
        buffer.append(sample)
    }
}

private let correlator = Correlator(writer: writer, initialSpaces: initialSpaces)
private var currentSpaces = initialSpaces
private let drainBufferedInputs = {
    let samples = buffer.drain().sorted { $0.sequence < $1.sequence }
    for sample in samples {
        correlator.consume(sample, currentSpaces: currentSpaces)
    }
}
writer.write([
    "record": "probeStart",
    "t_ms": Monotonic.milliseconds(Monotonic.nowNanoseconds()),
    "duration_seconds": options.duration,
    "output": options.outputPath,
    "spaces": initialSpaces.map(\.json),
    "privacy": "Only exact Control-Left/Right key events are retained; no other keys, characters, process identities, windows, titles, or raw SkyLight dictionaries are recorded.",
])

let workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.activeSpaceDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    let notificationNS = Monotonic.nowNanoseconds()
    drainBufferedInputs()
    correlator.recordSpaceNotification(at: notificationNS)
    if let spaces = spacesReader.read() {
        let observedNS = Monotonic.nowNanoseconds()
        currentSpaces = spaces
        correlator.observeSpaces(at: observedNS, spaces: spaces, source: "notification", logUnchanged: false)
    } else {
        writer.write([
            "record": "spaceNotification",
            "t_ms": Monotonic.milliseconds(notificationNS),
            "monotonic_ns": String(notificationNS),
            "error": "managed spaces read failed",
        ])
    }
}

let drainTimer = Timer(timeInterval: 0.02, repeats: true) { _ in
    drainBufferedInputs()
    if let spaces = spacesReader.read() {
        let observedNS = Monotonic.nowNanoseconds()
        currentSpaces = spaces
        correlator.observeSpaces(at: observedNS, spaces: spaces, source: "poll", logUnchanged: false)
    }
    correlator.expire(at: Monotonic.nowNanoseconds())
}
RunLoop.main.add(drainTimer, forMode: .common)

var didShutdown = false
func shutdown(reason: String) {
    guard !didShutdown else { return }
    didShutdown = true
    drainTimer.invalidate()
    if let appKitMonitor { NSEvent.removeMonitor(appKitMonitor) }
    NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
    tapThread.stop()
    drainBufferedInputs()
    let stoppedNS = Monotonic.nowNanoseconds()
    correlator.expire(at: stoppedNS)
    correlator.finishUnmatched(at: stoppedNS)
    writer.write([
        "record": "probeStop",
        "t_ms": Monotonic.milliseconds(Monotonic.nowNanoseconds()),
        "reason": reason,
    ])
    writer.close()
    Darwin.exit(0)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler { shutdown(reason: "SIGINT") }
interruptSource.resume()
let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminateSource.setEventHandler { shutdown(reason: "SIGTERM") }
terminateSource.resume()

let durationTimer = Timer(timeInterval: options.duration, repeats: false) { _ in shutdown(reason: "duration") }
RunLoop.main.add(durationTimer, forMode: .common)

print("Space input probe running for \(Int(options.duration))s")
print("JSONL: \(options.outputPath)")
print("Press Control-C to stop early. No permission prompt will be shown.")
fflush(stdout)
RunLoop.main.run()
