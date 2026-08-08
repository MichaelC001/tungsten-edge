import CoreGraphics
import Darwin
import Foundation

let duration = Double(CommandLine.arguments.dropFirst().first ?? "4") ?? 4
let targetPID = Int(CommandLine.arguments.dropFirst(2).first ?? "0") ?? 0
let tungstenPID = Int(CommandLine.arguments.dropFirst(3).first ?? "0") ?? 0
let end = Date().addingTimeInterval(duration)
var previous = ""

while Date() < end {
    var targetWindows: [String] = []
    var tungstenOnscreen: [Int] = []
    if let windows = CGWindowListCopyWindowInfo(
        [.optionAll, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] {
        for window in windows {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let onscreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue,
                  let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                continue
            }
            if ownerPID == targetPID {
                targetWindows.append(
                    "\(number)@L\(layer)@on\(onscreen ? 1 : 0)@\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width))x\(Int(bounds.height))"
                )
            }
            if ownerPID == tungstenPID && onscreen && layer == Int(CGWindowLevelForKey(.floatingWindow)) {
                tungstenOnscreen.append(number)
            }
        }
    }
    let signature = "tungsten=\(tungstenOnscreen.sorted()) target=\(targetWindows.sorted())"
    if signature != previous {
        let line = String(format: "t=%.6f %@\n", CFAbsoluteTimeGetCurrent(), signature)
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
        previous = signature
    }
    usleep(1_000)
}
