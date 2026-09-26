import AppKit
import ScreenCaptureKit

/// An explicit user capture asks ScreenCaptureKit itself. Passive resource discovery never calls this service.
@MainActor final class ScreenCaptureAccess: ObservableObject {
    enum State: Equatable { case idle, requesting, allowed, needsSettings, failed }
    static let shared = ScreenCaptureAccess()
    @Published private(set) var state: State = .idle
    private(set) var lastPreflight: Bool?
    private let preflight: () -> Bool
    private var generation = 0
    init(preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }) { self.preflight = preflight }

    func perform<T>(_ operation: () async throws -> T) async throws -> T {
        generation += 1; let token = generation
        lastPreflight = preflight(); state = .requesting
        // Preflight is advisory: it can retain a negative value after consent changes.
        // ScreenCaptureKit handles consent for this explicit user request and returns the authoritative result.
        do {
            let result = try await operation()
            if token == generation { state = .allowed }
            return result
        } catch {
            if token == generation { recordFailure(error) }
            throw error
        }
    }
    func recordFailure(_ error: Error) {
        if error is CancellationError { state = .idle }
        else { state = Self.isPermissionDenied(error) ? .needsSettings : .failed }
    }
    static func isPermissionDenied(_ error: Error) -> Bool {
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == SCStreamErrorDomain && current.code == SCStreamError.Code.userDeclined.rawValue { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }
    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
