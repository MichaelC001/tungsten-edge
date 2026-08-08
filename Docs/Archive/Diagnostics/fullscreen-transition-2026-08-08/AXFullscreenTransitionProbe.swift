import ApplicationServices
import Darwin
import Foundation

func attribute(_ name: CFString, of element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func boolAttribute(_ name: CFString, of element: AXUIElement) -> Bool? {
    guard let value = attribute(name, of: element) else { return nil }
    return (value as? NSNumber)?.boolValue
}

func pointAttribute(_ name: CFString, of element: AXUIElement) -> CGPoint? {
    guard let value = attribute(name, of: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func sizeAttribute(_ name: CFString, of element: AXUIElement) -> CGSize? {
    guard let value = attribute(name, of: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

func emit(_ line: String) {
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
}

func describe(_ element: AXUIElement, event: String) {
    let now = String(format: "%.6f", CFAbsoluteTimeGetCurrent())
    let fullscreen = boolAttribute("AXFullScreen" as CFString, of: element).map(String.init) ?? "nil"
    let position = pointAttribute(kAXPositionAttribute as CFString, of: element)
    let size = sizeAttribute(kAXSizeAttribute as CFString, of: element)
    let frame: String
    if let position, let size {
        frame = "\(Int(position.x)),\(Int(position.y)),\(Int(size.width))x\(Int(size.height))"
    } else {
        frame = "nil"
    }
    emit("t=\(now) event=\(event) fullscreen=\(fullscreen) frame=\(frame)")
}

let callback: AXObserverCallback = { _, element, notification, _ in
    describe(element, event: notification as String)
}

guard AXIsProcessTrusted() else {
    emit("trusted=false")
    exit(2)
}

guard CommandLine.arguments.count >= 2, let rawPID = Int32(CommandLine.arguments[1]) else {
    emit("usage: AXFullscreenTransitionProbe <pid> [duration]")
    exit(64)
}
let duration = Double(CommandLine.arguments.dropFirst(2).first ?? "4") ?? 4
let pid = pid_t(rawPID)
let app = AXUIElementCreateApplication(pid)
_ = AXUIElementSetMessagingTimeout(app, 0.2)
var observer: AXObserver?
guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
    emit("observer=false")
    exit(1)
}
let source = AXObserverGetRunLoopSource(observer)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

var windowsValue: CFTypeRef?
if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
   let windows = windowsValue as? [AXUIElement] {
    for window in windows {
        AXObserverAddNotification(observer, window, kAXWindowMovedNotification as CFString, nil)
        AXObserverAddNotification(observer, window, kAXWindowResizedNotification as CFString, nil)
        describe(window, event: "initial")
    }
}
emit("trusted=true pid=\(pid)")
CFRunLoopRunInMode(.defaultMode, duration, false)
