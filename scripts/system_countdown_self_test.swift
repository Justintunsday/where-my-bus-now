import Foundation
import SwiftUI

@main enum SystemCountdownSelfTest {
    static func main() {
        if #available(macOS 15.0, *) {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            for (seconds, expected) in [(1.0, 1), (59, 1), (60, 1), (61, 2), (360, 6), (3660, 61), (86460, 1441)] {
                let style = SystemFormatStyle.Timer(countingDownIn: now..<now.addingTimeInterval(seconds),
                    showsHours: false, maxFieldCount: 1, maxPrecision: .seconds(60))
                let value = String(style.format(now).characters)
                print("Native minute timer \(seconds)s = [\(value)]")
                precondition(value == String(expected), "Native whole minutes must match ceil without seconds or clock separators")
                precondition(String(style.format(now.addingTimeInterval(seconds + 60)).characters) == "0",
                             "The bounded system timer must never become negative")
            }
            print("PASS: built-in system timer rounds whole minutes and clamps at zero")
        } else { fatalError("Xcode 26 runner requires macOS 15 or later") }
    }
}
