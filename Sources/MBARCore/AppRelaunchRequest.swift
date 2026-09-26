import Foundation

public struct AppRelaunchRequest: Equatable {
    public let parentPID: Int32
    public let iconBundle: String?
    public init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--relaunch-parent"), index + 1 < arguments.count,
              let pid = Int32(arguments[index + 1]), pid > 1 else { return nil }
        parentPID = pid
        if let index = arguments.firstIndex(of: "--reopen-icon-settings") {
            guard index + 1 < arguments.count else { return nil }
            let bundle = arguments[index + 1]
            guard !bundle.isEmpty, bundle.utf8.count <= 256, bundle.contains("."),
                  bundle.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
            iconBundle = bundle
        } else { iconBundle = nil }
    }
}
