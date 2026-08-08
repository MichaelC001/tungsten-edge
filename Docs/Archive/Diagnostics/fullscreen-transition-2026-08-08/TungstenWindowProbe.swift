import CoreGraphics
import Darwin
import Foundation

let duration = Double(CommandLine.arguments.dropFirst().first ?? "5") ?? 5
let targetPID = pid_t(CommandLine.arguments.dropFirst(2).first ?? "0") ?? 0
let intervalMicros = useconds_t(CommandLine.arguments.dropFirst(3).first ?? "500") ?? 500
let fullscreenAppPID = pid_t(CommandLine.arguments.dropFirst(4).first ?? "0") ?? 0
let end = Date().addingTimeInterval(duration)
var previous = ""

while Date() < end {
    var dockWindows: [String] = []
    var tungstenIDs: [Int] = []
    var tungstenLayers: [Int] = []
    var fullscreenAppWindows: [String] = []
    if let raw = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] {
        for info in raw {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let owner = info[kCGWindowOwnerName as String] as? String else {
                continue
            }
            if owner == "Dock",
               let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
               let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) {
                dockWindows.append(
                    "\(number)@L\(layer)@\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width))x\(Int(bounds.height))"
                )
            }
            if let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue {
                if ownerPID == Int(targetPID) {
                    tungstenIDs.append(number)
                    tungstenLayers.append(layer)
                }
                if ownerPID == Int(fullscreenAppPID),
                   let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                   let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) {
                    fullscreenAppWindows.append(
                        "\(number)@\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width))x\(Int(bounds.height))"
                    )
                }
            }
        }
    }

    let signature = "dock=\(dockWindows.sorted()) tungsten=\(tungstenIDs.sorted()) layers=\(tungstenLayers.sorted()) fullscreenApp=\(fullscreenAppWindows.sorted())"
    if signature != previous {
        let now = String(format: "%.6f", CFAbsoluteTimeGetCurrent())
        let line = "t=\(now) \(signature)\n"
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
        previous = signature
    }
    usleep(intervalMicros)
}
