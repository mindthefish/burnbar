import AppKit
import Combine
import SwiftUI

@main
struct BurnbarApp: App {
    @NSApplicationDelegateAdaptor(StatusItemController.self) private var statusItemController

    var body: some Scene {
        Settings {
            SubscriptionSettingsView(store: statusItemController.snapshotStore)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { statusItemController.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: 90)
    let popover = NSPopover()
    fileprivate let snapshotStore: QuotaSnapshotStore
    private var labelHostingView: NSHostingView<MenuBarLabel>?
    private var configurationObserver: AnyCancellable?
    private(set) var settingsWindow: NSWindow?

    /// Injectable so quitting can be verified without terminating the test run.
    var terminate: @MainActor () -> Void = { NSApp.terminate(nil) }

    /// Watches for clicks outside the app. `.transient` alone does not close the
    /// popover when an accessory app loses focus to another application.
    private(set) var outsideClickMonitor: Any?

    override init() {
        snapshotStore = QuotaSnapshotStore()
        super.init()
    }

    init(snapshotStore: QuotaSnapshotStore) {
        self.snapshotStore = snapshotStore
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        snapshotStore.reloadConfiguration()
        install()
        LoginItem().enable()
        snapshotStore.startRefreshing()
    }

    func install() {
        guard let button = statusItem.button else {
            return
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: PopoverContent(
                store: snapshotStore,
                onQuit: { [weak self] in self?.quit() },
                onSettings: { [weak self] in self?.showSettings() }
            )
                .preferredColorScheme(.dark)
        )

        let hostingView = NSHostingView(
            rootView: MenuBarLabel(store: snapshotStore)
        )
        hostingView.frame = button.bounds.insetBy(dx: 3, dy: 0)
        hostingView.autoresizingMask = [.width, .height]
        button.addSubview(hostingView)
        button.target = self
        button.action = #selector(togglePopover)
        labelHostingView = hostingView
        configurationObserver = snapshotStore.$providers.sink { [weak self] providers in
            self?.statusItem.length = providers.isEmpty ? 28 : CGFloat((providers.count + 2) / 3) * 90
        }
    }

    func remove() {
        snapshotStore.stopRefreshing()
        closePopover()
        settingsWindow?.close()
        settingsWindow = nil
        labelHostingView?.removeFromSuperview()
        labelHostingView = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Burnbar Settings"
            window.minSize = NSSize(width: 540, height: 330)
            window.contentViewController = NSHostingController(rootView: SubscriptionSettingsView(store: snapshotStore))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func quit() {
        terminate()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    func closePopover() {
        popover.performClose(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }
}

private struct PopoverContent: View {
    @ObservedObject private var store: QuotaSnapshotStore
    private let onQuit: () -> Void
    private let onSettings: () -> Void

    init(store: QuotaSnapshotStore, onQuit: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.store = store
        self.onQuit = onQuit
        self.onSettings = onSettings
    }

    var body: some View {
        let presentation = PopoverPresentation(providers: store.providers)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Burnbar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let lastUpdated = store.lastUpdated {
                    Text("Data from \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await store.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel("Refresh quota usage")
                .disabled(store.isRefreshing)
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel("Settings")
                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityLabel("Quit Burnbar")
            }
            .padding(.bottom, 10)

            if let error = store.configurationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
            if presentation.cards.isEmpty {
                Text(store.configuration.profiles.isEmpty
                     ? "Add a subscription to show its remaining budget."
                     : "No active subscriptions. Enable one in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                Button("Open Settings…", action: onSettings)
                    .buttonStyle(.borderless)
            }
            ForEach(Array(presentation.cards.enumerated()), id: \.offset) { index, card in
                if index > 0 {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                }
                VStack(alignment: .leading, spacing: 4) {
                    PopoverQuotaCardView(card: card)
                    if case .keychainDenied = store.providers[index].failure {
                        Button("Allow credential access…") {
                            let id = store.activeProfiles[index].id
                            Task { await store.refresh(authorizing: id) }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(store.isRefreshing)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, Locale(identifier: "en_GB"))
    }
}

private struct PopoverQuotaCardView: View {
    let card: PopoverQuotaCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accent(for: card.accent))
                    .frame(width: 8, height: 8)
                Text(card.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if card.state == .stale {
                    Text(card.statusNote ?? "Stale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if let date = card.lastSuccessfulUpdate {
                Text("Updated \(date, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            switch card.state {
            case .available, .stale:
                ForEach(Array(card.windows.enumerated()), id: \.offset) { _, window in
                    HStack(spacing: 8) {
                        Text(window.label)
                            .frame(width: CGFloat(max(3, card.windows.map { $0.label.count }.max() ?? 3)) * 7, alignment: .leading)
                            .foregroundStyle(Color(white: 0.7))
                        PopoverWindowBar(
                            remainingFraction: window.remainingPercentage / 100,
                            accent: card.accent
                        )
                        .frame(height: 6)
                        .opacity(card.state == .stale ? 0.45 : 1)
                        Text("\(window.remainingPercentage, format: .number.precision(.fractionLength(0)))%")
                            .fontWeight(.bold)
                            .frame(width: 38, alignment: .trailing)
                            .foregroundStyle(.white)
                        Group {
                            if let resetsAt = window.resetsAt {
                                switch ResetTimestampFormat.choose(for: resetsAt, now: .now) {
                                case .timeOnly:
                                    Text(resetsAt, format: .dateTime.hour().minute())
                                case .dateAndTime:
                                    Text(resetsAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                                }
                            } else {
                                Text(verbatim: "\u{2014}")
                            }
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 76, alignment: .trailing)
                        .foregroundStyle(Color(white: 0.55))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(window.label): \(Int(window.remainingPercentage)) percent remaining"
                    )
                }
            case .unavailable:
                HStack(alignment: .top, spacing: 8) {
                    Text(card.statusNote ?? "Unavailable")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    PopoverQuotaBar(barState: card.barState, accent: card.accent)
                        .frame(width: 60, height: 6)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PopoverWindowBar: View {
    let remainingFraction: Double
    let accent: ProviderQuotaSnapshot.Accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accent(for: accent).opacity(0.22))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accent(for: accent))
                    .frame(width: geometry.size.width * remainingFraction)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PopoverQuotaBar: View {
    let barState: PopoverQuotaCard.BarState
    let accent: ProviderQuotaSnapshot.Accent

    var body: some View {
        GeometryReader { geometry in
            switch barState {
            case let .available(fillFraction, _):
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accent(for: accent).opacity(0.22))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accent(for: accent))
                        .frame(width: geometry.size.width * fillFraction)
                }
            case .stale, .unavailable:
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject private var store: QuotaSnapshotStore

    init(store: QuotaSnapshotStore) {
        self.store = store
    }

    var body: some View {
        let presentation = MenuBarPresentation(providers: store.providers)

        GeometryReader { geometry in
            let rows = max(1, min(3, presentation.indicators.count))
            let availableHeight = max(0, geometry.size.height - 4)
            let rowHeight = max(0, (availableHeight - CGFloat(rows - 1) * 2) / CGFloat(rows))

            HStack(spacing: 8) {
                if presentation.indicators.isEmpty {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                } else {
                    ForEach(0..<((presentation.indicators.count + 2) / 3), id: \.self) { column in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(column * 3..<min(column * 3 + 3, presentation.indicators.count), id: \.self) { index in
                                let item = presentation.indicators[index]
                                HStack(spacing: 3) {
                                    Text(item.indicator)
                                        .font(.system(size: min(12, rowHeight + 1), weight: .medium, design: .rounded))
                                        .minimumScaleFactor(0.7)
                                        .lineLimit(1)
                                        .frame(width: rows == 1 ? 16 : 12, alignment: .trailing)
                                    MenuBarQuotaBar(indicator: item)
                                        .frame(height: min(10, rowHeight))
                                }
                                .frame(height: rowHeight)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .padding(.horizontal, 2)
            .frame(width: geometry.size.width, height: availableHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityLabel("Burnbar usage")
    }
}

private struct MenuBarQuotaBar: View {
    let indicator: MenuBarIndicator

    var body: some View {
        GeometryReader { geometry in
            switch indicator.visualState {
            case let .available(fillFraction):
                filledBar(size: geometry.size, fillFraction: fillFraction, opacity: 1)
            case let .stale(fillFraction):
                if let fillFraction {
                    filledBar(size: geometry.size, fillFraction: fillFraction, opacity: 0.45)
                } else {
                    dashedBar
                }
            case .unavailable:
                dashedBar
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func filledBar(size: CGSize, fillFraction: Double, opacity: Double) -> some View {
        let fillWidth = size.width * min(1, max(0, fillFraction))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.accent(for: indicator.accent).opacity(0.22))
            // The longer window is behind the current short-window fill. Drawing it first keeps
            // its leading outline from cutting into a filled bar.
            if let weeklyFillFraction = indicator.weeklyFillFraction,
               weeklyFillFraction > fillFraction {
                Capsule()
                    .strokeBorder(Color.accent(for: indicator.accent).opacity(opacity), lineWidth: 1)
                    .frame(width: size.width * weeklyFillFraction)
            }
            if fillWidth > 0 {
                Capsule()
                    .fill(Color.accent(for: indicator.accent).opacity(opacity))
                    .frame(width: size.width, height: size.height)
                    .offset(x: fillWidth - size.width)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
    }

    private var dashedBar: some View {
        Capsule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .foregroundStyle(.secondary)
    }
}
