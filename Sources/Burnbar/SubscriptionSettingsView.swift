import AppKit
import SwiftUI

private extension SubscriptionSymbol {
    var title: String {
        switch self {
        case .person: "Person"
        case .briefcase: "Briefcase"
        case .terminal: "Terminal"
        case .bolt: "Bolt"
        case .star: "Star"
        case .flame: "Flame"
        case .heart: "Heart"
        }
    }
}

struct SubscriptionSettingsView: View {
    @ObservedObject var store: QuotaSnapshotStore
    @State private var editor: SubscriptionEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscriptions")
                        .font(.title2.weight(.semibold))
                    Text("Choose up to \(BurnbarConfiguration.maximumActiveSubscriptions) subscriptions. Drag to reorder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editor = SubscriptionEditorRequest(profile: nil)
                } label: {
                    Label("Add subscription", systemImage: "plus")
                }
            }

            if let error = store.configurationError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.configuration.profiles.isEmpty {
                ContentUnavailableView(
                    "No subscriptions yet",
                    systemImage: "chart.bar",
                    description: Text("Add an existing Codex or Claude profile folder to show its remaining budget.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(store.configuration.profiles) { profile in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 12)
                                    .help("Drag to reorder")
                                    .accessibilityLabel("Drag to reorder \(profile.name)")
                                    .draggable(profile.id)
                                Group {
                                    if let symbol = profile.symbol {
                                        Image(systemName: symbol.rawValue)
                                    } else {
                                        Text(profile.indicator)
                                    }
                                }
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Color.accent(for: profile.accent))
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name).fontWeight(.medium)
                                    Text("\(profile.provider == .codex ? "Codex" : "Claude") · \(profile.home)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Toggle("Enabled", isOn: Binding(
                                    get: { profile.enabled },
                                    set: { store.setEnabled($0, profileID: profile.id) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .disabled(!profile.enabled && store.activeProfiles.count >= BurnbarConfiguration.maximumActiveSubscriptions)
                                .help(!profile.enabled && store.activeProfiles.count >= BurnbarConfiguration.maximumActiveSubscriptions
                                      ? "Disable another subscription to enable this one."
                                      : "Show this subscription in the menu bar.")
                                .accessibilityLabel("Enable \(profile.name)")
                                Button {
                                    editor = SubscriptionEditorRequest(profile: profile)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .help("Edit subscription")
                                .accessibilityLabel("Edit \(profile.name)")
                                Button {
                                    store.removeProfile(profile)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .help("Remove from Burnbar; keep provider credentials")
                                .accessibilityLabel("Remove \(profile.name) from Burnbar")
                            }
                            .buttonStyle(.borderless)
                            .padding(14)
                            .background {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first,
                                      id != profile.id,
                                      store.configuration.profiles.contains(where: { $0.id == id }) else { return false }
                                return store.moveProfile(id: id, to: profile.id)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Refresh every")
                Picker("Refresh interval", selection: Binding(
                    get: { store.configuration.refreshIntervalMinutes },
                    set: { store.setRefreshInterval($0) }
                )) {
                    ForEach(Array(Set([5, 10, 15, 30, 60, store.configuration.refreshIntervalMinutes])).sorted(), id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                Button("Open config…") { store.openConfiguration() }
                Button("Reload") { store.reloadConfiguration() }
            }
            .font(.callout)
            .controlSize(.small)
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 420)
        .sheet(item: $editor) { request in
            SubscriptionEditor(store: store, original: request.profile)
        }
    }
}

private struct SubscriptionEditorRequest: Identifiable {
    let id = UUID()
    let profile: BurnbarConfiguration.Profile?
}

private struct SubscriptionEditor: View {
    @ObservedObject var store: QuotaSnapshotStore
    let original: BurnbarConfiguration.Profile?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BurnbarConfiguration.Profile
    @State private var error: String?
    @State private var lastQuotaColors: QuotaColors

    init(store: QuotaSnapshotStore, original: BurnbarConfiguration.Profile?) {
        self.store = store
        self.original = original
        _lastQuotaColors = State(initialValue: original?.quotaColors ?? .standard)
        _draft = State(initialValue: original ?? .init(
            id: UUID().uuidString, provider: .codex, name: "", indicator: "",
            home: "", enabled: store.activeProfiles.count < BurnbarConfiguration.maximumActiveSubscriptions
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(original == nil ? "Add subscription" : "Edit subscription")
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .center) {
                    Text("Provider")
                        .gridColumnAlignment(.trailing)
                    Picker("Provider", selection: Binding(
                        get: { draft.provider },
                        set: { provider in
                            draft = .init(id: draft.id, provider: provider, name: draft.name,
                                          indicator: draft.indicator, home: draft.home,
                                          enabled: draft.enabled, color: draft.color, symbol: draft.symbol,
                                          quotaColors: draft.quotaColors)
                        }
                    )) {
                        Text("Codex").tag(BurnbarConfiguration.Profile.Provider.codex)
                        Text("Claude").tag(BurnbarConfiguration.Profile.Provider.claude)
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow(alignment: .center) {
                    Text("Profile folder")
                    HStack(spacing: 8) {
                        Text(draft.home.isEmpty ? "No folder selected" : draft.home)
                            .foregroundStyle(draft.home.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(draft.home)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                GridRow(alignment: .center) {
                    Text("Name")
                    TextField("Name", text: $draft.name, prompt: Text("Personal"))
                        .labelsHidden()
                }
                GridRow(alignment: .center) {
                    Text("Menu bar label")
                    Picker("Menu bar label", selection: $draft.symbol) {
                        Text("Abbreviation").tag(Optional<SubscriptionSymbol>.none)
                        ForEach(SubscriptionSymbol.allCases, id: \.self) { symbol in
                            Label(symbol.title, systemImage: symbol.rawValue)
                                .tag(Optional(symbol))
                        }
                    }
                        .labelsHidden()
                }
                if draft.symbol == nil {
                    GridRow(alignment: .center) {
                        Text("Abbreviation")
                        TextField("Abbreviation", text: $draft.indicator, prompt: Text("P"))
                            .labelsHidden()
                            .onChange(of: draft.indicator) { _, value in
                                draft.indicator = String(value.prefix(2))
                            }
                            .help("Up to 2 characters, including emoji.")
                    }
                }
                GridRow(alignment: .top) {
                    Text("Colors").padding(.top, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Color by remaining quota", isOn: Binding(
                            get: { draft.quotaColors != nil },
                            set: { enabled in
                                if enabled {
                                    draft.quotaColors = lastQuotaColors
                                } else {
                                    lastQuotaColors = draft.quotaColors ?? lastQuotaColors
                                    draft.quotaColors = nil
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        if let colors = draft.quotaColors {
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 3) {
                                    ColorPicker("Full", selection: Binding(
                                        get: { Color.accent(for: .custom(hex: draft.quotaColors?.full ?? colors.full)) },
                                        set: { draft.quotaColors?.full = $0.hexRGB }
                                    ), supportsOpacity: false)
                                    Text("100% remaining")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    ColorPicker("Empty", selection: Binding(
                                        get: { Color.accent(for: .custom(hex: draft.quotaColors?.empty ?? colors.empty)) },
                                        set: { draft.quotaColors?.empty = $0.hexRGB }
                                    ), supportsOpacity: false)
                                    Text("0% remaining")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            LinearGradient(
                                colors: (0...20).map {
                                    Color.quota(remainingFraction: 1 - Double($0) / 20, accent: draft.accent, colors: colors)
                                },
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(height: 8)
                            .clipShape(Capsule())
                            .accessibilityLabel("Color transition from full to empty quota")
                            Text("Each limit uses its own remaining quota.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ColorPicker("Fixed color", selection: Binding(
                                get: { Color.accent(for: draft.fixedAccent) },
                                set: { draft.color = $0.hexRGB }
                            ), supportsOpacity: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            }

            Text("Choose the configuration folder of an already signed-in provider. Limit windows are read automatically from its usage response.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.home.isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || !draft.hasValidIndicator)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose provider profile folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = draft.home.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser : draft.homeURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.home = url.path
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.color == nil { draft.color = Color.accent(for: draft.fixedAccent).hexRGB }
        if store.saveProfile(draft, replacing: original) { dismiss() }
        else { error = store.configurationError }
    }
}
