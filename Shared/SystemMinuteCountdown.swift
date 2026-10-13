import Foundation
import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
enum SystemMinuteCountdown {
    static func style(updatedAt: Date, arrival: Date) -> SystemFormatStyle.Timer {
        // The native minute-precision timer truncates. Shift only its formatting
        // endpoint to the representable instant before arrival + 60 seconds so
        // displayed minutes round up. Prediction and stale dates stay unchanged.
        let end = Date(timeIntervalSince1970: arrival.addingTimeInterval(60).timeIntervalSince1970.nextDown)
        return .init(countingDownIn: updatedAt..<end, showsHours: false,
                     maxFieldCount: 1, maxPrecision: .seconds(60))
    }
}
