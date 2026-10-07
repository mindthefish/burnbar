import Foundation
import ServiceManagement
import Testing
@testable import Burnbar

struct LoginItemTests {
    @Test
    func reportsUnsupportedWithoutAnAppBundle() {
        let item = LoginItem(
            statusReader: { .notRegistered },
            registrar: { Issue.record("must not register outside a bundle") },
            isBundled: false
        )

        #expect(item.enable() == .unsupported)
    }

    @Test
    func skipsRegistrationWhenTheLoginItemIsAlreadyEnabled() {
        let item = LoginItem(
            statusReader: { .enabled },
            registrar: { Issue.record("must not register twice") },
            isBundled: true
        )

        #expect(item.enable() == .enabled)
    }

    @Test
    func registersWhenTheLoginItemIsNotRegisteredYet() {
        let item = LoginItem(
            statusReader: { .notRegistered },
            registrar: {},
            isBundled: true
        )

        #expect(item.enable() == .enabled)
    }

    @Test
    func reportsDisabledWhenRegistrationFails() {
        struct RegistrationError: Error {}
        let item = LoginItem(
            statusReader: { .notRegistered },
            registrar: { throw RegistrationError() },
            isBundled: true
        )

        #expect(item.enable() == .disabled)
    }
}
