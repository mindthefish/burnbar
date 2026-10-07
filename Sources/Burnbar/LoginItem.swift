import Foundation
import ServiceManagement

/// Registers the app as a macOS login item so it starts with the system.
/// Registration only works from an installed `.app` bundle; a bare SwiftPM
/// binary reports `.unsupported` instead of failing the launch.
struct LoginItem {
    enum Status: Equatable, Sendable {
        case enabled
        case disabled
        case unsupported
    }

    typealias StatusReader = @Sendable () -> SMAppService.Status
    typealias Registrar = @Sendable () throws -> Void

    private let statusReader: StatusReader
    private let registrar: Registrar
    private let isBundled: Bool

    init(
        statusReader: @escaping StatusReader = { SMAppService.mainApp.status },
        registrar: @escaping Registrar = { try SMAppService.mainApp.register() },
        isBundled: Bool = Bundle.main.bundleIdentifier != nil
    ) {
        self.statusReader = statusReader
        self.registrar = registrar
        self.isBundled = isBundled
    }

    @discardableResult
    func enable() -> Status {
        guard isBundled else {
            return .unsupported
        }

        if statusReader() == .enabled {
            return .enabled
        }

        do {
            try registrar()
            return .enabled
        } catch {
            return .disabled
        }
    }
}
