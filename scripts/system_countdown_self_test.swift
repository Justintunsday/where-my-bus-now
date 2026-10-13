import Foundation
import SwiftUI

@main enum SystemCountdownSelfTest {
    static func main() {
        if #available(macOS 15.0, *) {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            var failures = 0
            for (seconds, expected) in [(1.0, 1), (59, 1), (60, 1), (61, 2), (360, 6), (3660, 61), (86460, 1441)] {
                let style = SystemFormatStyle.Timer(countingDownIn: now..<now.addingTimeInterval(seconds),
                    showsHours: false, maxFieldCount: 1, maxPrecision: .seconds(60))
                let value = String(style.format(now).characters)
                let expired = String(style.format(now.addingTimeInterval(seconds + 60)).characters)
                FileHandle.standardError.write(Data("Native minute timer \(seconds)s = [\(value)], expected \(expected), expired [\(expired)]\n".utf8))
                if value != String(expected) || expired != "0" { failures += 1 }
            }
            guard failures == 0 else { exit(1) }
            print("PASS: built-in system timer rounds whole minutes and clamps at zero")
        } else { fatalError("Xcode 26 runner requires macOS 15 or later") }
    }
}
