import Foundation

enum TrimSettingsError: Error {
    case invalidArgument(message: String)
}

/// Trim boundaries of an edit operation, expressed in milliseconds.
public class TrimSettings: NSObject {
    private var startsAt: CLong = 0
    private var endsAt: CLong = 0

    /// - Parameters:
    ///   - startsAt: start of the output, in milliseconds from the start of the source
    ///   - endsAt: end of the output in milliseconds, or 0 for "until the end of the source"
    init(startsAt: CLong, endsAt: CLong) throws {
        super.init()

        try self.setStartsAt(startsAt)
        try self.setEndsAt(endsAt)
    }

    /// Get startsAt in milliseconds
    func getStartsAt() -> CLong {
        return self.startsAt
    }

    /// Set startsAt in milliseconds
    func setStartsAt(_ startsAt: CLong) throws {
        if startsAt < 0 {
            throw TrimSettingsError.invalidArgument(message: "Parameter startsAt cannot be negative")
        }
        self.startsAt = startsAt
    }

    /// Get endsAt in milliseconds. A value of 0 means "until the end of the source".
    func getEndsAt() -> CLong {
        return self.endsAt
    }

    /// Set endsAt in milliseconds
    func setEndsAt(_ endsAt: CLong) throws {
        if endsAt < 0 {
            throw TrimSettingsError.invalidArgument(message: "Parameter endsAt cannot be negative")
        }
        self.endsAt = endsAt
    }
}
