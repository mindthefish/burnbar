import AppKit
import Testing
@testable import Burnbar

struct StatusItemControllerTests {
    @Test
    @MainActor
    func installationAndReopeningDoNotCreateSettings() {
        _ = NSApplication.shared
        let controller = StatusItemController(snapshotStore: QuotaSnapshotStore(configuration: .defaults))
        controller.install()
        defer { controller.remove() }
        #expect(controller.settingsWindow == nil)
        let delegate: any NSApplicationDelegate = controller
        #expect(delegate.applicationShouldHandleReopen?(NSApplication.shared, hasVisibleWindows: false) == false)
        #expect(controller.settingsWindow == nil)
    }

    @Test
    @MainActor
    func settingsKeyboardCommandOpensOnlyTheExplicitSettingsWindow() throws {
        _ = NSApplication.shared
        let controller = StatusItemController(snapshotStore: QuotaSnapshotStore(configuration: .defaults))
        defer { controller.remove() }
        let menu = controller.makeApplicationMenu()
        let command = try #require(menu.items.first?.submenu?.items.first)
        #expect(command.keyEquivalent == ",")
        let editMenu = try #require(menu.items.last?.submenu)
        let paste = try #require(editMenu.items.first(where: { $0.keyEquivalent == "v" }))
        #expect(paste.action == Selector("paste:"))
        #expect(paste.target == nil)
        #expect(controller.settingsWindow == nil)
        let action = try #require(command.action)
        #expect(NSApplication.shared.sendAction(action, to: command.target, from: command))
        let window = try #require(controller.settingsWindow)
        #expect(window.title == "Burnbar Settings")
        #expect(!window.isRestorable)
    }

    @Test
    @MainActor
    func emptyProfilesKeepAnAccessibleStatusItem() {
        // SwiftPM runners do not start an NSApplication before AppKit tests.
        _ = NSApplication.shared
        let store = QuotaSnapshotStore(configuration: BurnbarConfiguration(profiles: []))
        let controller = StatusItemController(snapshotStore: store)
        controller.install()
        defer { controller.remove() }
        #expect(controller.statusItem.length == 28)
        #expect(controller.popover.contentViewController != nil)
    }

    @Test
    @MainActor
    func extraProfilesUseAnotherColumn() {
        // SwiftPM runners do not start an NSApplication before AppKit tests.
        _ = NSApplication.shared
        var configuration = BurnbarConfiguration.sample
        configuration.profiles[0].enabled = true
        configuration.profiles.append(.init(id: "extra", provider: .codex, name: "Extra", indicator: "E", home: "~/.codex-extra", enabled: true))
        let controller = StatusItemController(snapshotStore: QuotaSnapshotStore(configuration: configuration))
        controller.install()
        defer { controller.remove() }
        #expect(controller.statusItem.length == 180)
    }

    @Test
    @MainActor
    func installsAHostedMenuBarLabelAndPopover() {
        // SwiftPM runners do not start an NSApplication before AppKit tests.
        _ = NSApplication.shared
        let controller = StatusItemController(snapshotStore: QuotaSnapshotStore(configuration: .sample))

        controller.install()
        defer { controller.remove() }

        #expect(controller.statusItem.button?.subviews.count == 1)
        #expect(controller.statusItem.length == 90)
        #expect(controller.popover.contentViewController != nil)
    }

    @Test
    @MainActor
    func settingsReuseTheirWindowAndCloseWithTheController() {
        // SwiftPM runners do not start an NSApplication before AppKit tests.
        _ = NSApplication.shared
        let controller = StatusItemController(snapshotStore: QuotaSnapshotStore(configuration: .defaults))
        controller.install()
        controller.showSettings()
        let window = controller.settingsWindow
        #expect(window?.title == "Burnbar Settings")
        #expect(window?.contentViewController != nil)
        controller.showSettings()
        #expect(controller.settingsWindow === window)
        controller.remove()
        #expect(controller.settingsWindow == nil)
    }

    @Test
    @MainActor
    func quitTerminatesTheApp() {
        // SwiftPM runners do not start an NSApplication before AppKit tests.
        _ = NSApplication.shared
        let controller = StatusItemController()
        var terminated = false
        controller.terminate = { terminated = true }

        controller.quit()

        #expect(terminated)
    }

    @Test
    @MainActor
    func showingThePopoverWatchesForClicksOutsideTheApp() {
        // SwiftPM runners do not start an NSApplication before AppKit tests.
        _ = NSApplication.shared
        let controller = StatusItemController()
        controller.install()
        defer { controller.remove() }

        controller.showPopover()
        #expect(controller.outsideClickMonitor != nil)

        controller.closePopover()
        #expect(controller.outsideClickMonitor == nil)
    }
}
