import AppKit
import Foundation
import os

/// Diagnostics for the Paste Bar: activation, search focus, key routing.
/// Read with `log show --predicate 'subsystem == "com.greycorelabs.saipaste"' --last 10m`.
enum BarLog {
    static let log = Logger(subsystem: "com.greycorelabs.saipaste", category: "bar")
}

extension NSResponder {
    var barLogName: String { String(describing: type(of: self)) }
}
