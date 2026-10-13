import AppKit
import Combine
import SwiftUI

@main
enum BurnbarApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let controller = StatusItemController()
        application.setActivationPolicy(.accessory)
        application.delegate = controller
        application.mainMenu = controller.makeApplicationMenu()
        withExtendedLifetime(controller) {
            application.run()
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
        hostingView.frame = button.bounds
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

    func makeApplicationMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Burnbar")
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Burnbar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        false
    }

    @objc func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Burnbar Settings"
            window.minSize = NSSize(width: 540, height: 448)
            window.contentViewController = NSHostingController(rootView: SubscriptionSettingsView(store: snapshotStore))
            window.setContentSize(NSSize(width: 600, height: 440))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() {
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
                    Text("updated \(lastUpdated, style: .relative) ago")
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

            switch card.state {
            case .available, .stale:
                ForEach(Array(card.windows.enumerated()), id: \.offset) { _, window in
                    HStack(spacing: 8) {
                        Text(window.label)
                            .frame(width: CGFloat(max(3, card.windows.map { $0.label.count }.max() ?? 3)) * 7, alignment: .leading)
                            .foregroundStyle(Color(white: 0.7))
                        PopoverWindowBar(
                            remainingFraction: window.remainingPercentage / 100,
                            accent: card.accent,
                            quotaColors: card.quotaColors
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
    let quotaColors: QuotaColors?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let color = Color.quota(remainingFraction: remainingFraction, accent: accent, colors: quotaColors)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.quotaTrack())
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.quotaOutline(), lineWidth: 1 / displayScale)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * remainingFraction)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PopoverQuotaBar: View {
    let barState: PopoverQuotaCard.BarState
    let accent: ProviderQuotaSnapshot.Accent
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            switch barState {
            case let .available(fillFraction, _):
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.quotaTrack())
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.quotaOutline(), lineWidth: 1 / displayScale)
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
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var store: QuotaSnapshotStore

    init(store: QuotaSnapshotStore) {
        self.store = store
    }

    var body: some View {
        let presentation = MenuBarPresentation(providers: store.providers)

        GeometryReader { geometry in
            let rows = max(1, min(3, presentation.indicators.count))
            let rowSpacing: CGFloat = rows == 3 ? 1 / displayScale : 2
            let availableHeight = max(0, geometry.size.height - (rows == 3 ? 0 : 4))
            let rowHeight = max(0, floor(
                (availableHeight - CGFloat(rows - 1) * rowSpacing) / CGFloat(rows) * displayScale
            ) / displayScale)
            let contentHeight = rowHeight * CGFloat(rows) + rowSpacing * CGFloat(rows - 1)
            let topInset = floor((geometry.size.height - contentHeight) / 2 * displayScale) / displayScale
            let labelFontSize: CGFloat = rows == 3 ? 7 : (rows == 2 ? 9 : 11)
            let labelFont = NSFont.monospacedSystemFont(ofSize: labelFontSize, weight: .medium)
            let labelWidth = max(16, presentation.indicators.filter { $0.symbol == nil }.map {
                ceil(($0.indicator as NSString).size(withAttributes: [.font: labelFont]).width) + 1
            }.max() ?? 0)

            HStack(spacing: 8) {
                if presentation.indicators.isEmpty {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                } else {
                    ForEach(0..<((presentation.indicators.count + 2) / 3), id: \.self) { column in
                        VStack(alignment: .leading, spacing: rowSpacing) {
                            ForEach(column * 3..<min(column * 3 + 3, presentation.indicators.count), id: \.self) { index in
                                let item = presentation.indicators[index]
                                HStack(spacing: 3) {
                                    Group {
                                        if let symbol = item.symbol {
                                            Image(systemName: symbol.rawValue)
                                        } else {
                                            Text(item.indicator)
                                        }
                                    }
                                        .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(width: labelWidth, alignment: .center)
                                    MenuBarQuotaBar(indicator: item, dividerPixels: CGFloat(4 - rows))
                                        .frame(height: min(
                                            presentation.indicators.count == 1 && item.windowFillFractions.count > 1
                                                ? 14 : 10,
                                            rowHeight
                                        ))
                                }
                                .frame(height: rowHeight)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .frame(width: geometry.size.width, height: contentHeight)
            .position(x: geometry.size.width / 2, y: topInset + contentHeight / 2)
        }
        .accessibilityLabel("Burnbar usage")
    }
}

private struct MenuBarQuotaBar: View {
    let indicator: MenuBarIndicator
    let dividerPixels: CGFloat
    @Environment(\.displayScale) private var displayScale

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
        let fractions = indicator.windowFillFractions.isEmpty
            ? [min(1, max(0, fillFraction))]
            : indicator.windowFillFractions
        let spacing = dividerPixels / displayScale
        let stripHeight = max(0, floor(
            (size.height - CGFloat(fractions.count - 1) * spacing) / CGFloat(fractions.count) * displayScale
        ) / displayScale)
        let barHeight = stripHeight * CGFloat(fractions.count) + spacing * CGFloat(fractions.count - 1)
        let topInset = floor((size.height - barHeight) / 2 * displayScale) / displayScale

        // Tracks and outline sit behind the fills, sharing one outer mask.
        return ZStack {
            VStack(spacing: spacing) {
                ForEach(fractions.indices, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.quotaTrack(opacity: opacity))
                        .frame(width: size.width, height: stripHeight)
                }
            }
            Capsule()
                .strokeBorder(Color.quotaOutline(opacity: opacity), lineWidth: 1 / displayScale)
            VStack(spacing: spacing) {
                ForEach(fractions.indices, id: \.self) { index in
                    let color = Color.quota(remainingFraction: fractions[index], accent: indicator.accent, colors: indicator.quotaColors)
                    ZStack(alignment: .leading) {
                        if fractions.count == 1 {
                            if fractions[index] > 0 {
                                Capsule()
                                    .fill(color.opacity(opacity))
                                    .frame(width: size.width, height: stripHeight)
                                    .offset(x: size.width * (fractions[index] - 1))
                            }
                        } else {
                            Rectangle()
                                .fill(color.opacity(opacity))
                                .frame(width: size.width * fractions[index])
                        }
                    }
                    .frame(width: size.width, height: stripHeight, alignment: .leading)
                }
            }
        }
        .frame(width: size.width, height: barHeight)
        .clipShape(Capsule())
        .offset(y: topInset)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var dashedBar: some View {
        Capsule()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .foregroundStyle(.secondary)
    }
}
