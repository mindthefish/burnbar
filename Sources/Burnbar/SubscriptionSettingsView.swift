import AppKit
import SwiftUI

struct SubscriptionSettingsView: View {
    @ObservedObject var store: QuotaSnapshotStore
    @State private var editor: SubscriptionEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Subscriptions")
                    .font(.title2.weight(.semibold))
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
                    VStack(spacing: 0) {
                        ForEach(store.configuration.profiles) { profile in
                            HStack(spacing: 12) {
                                Text(profile.indicator)
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
                            .padding(.vertical, 12)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            Divider()
            HStack {
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
                .frame(width: 135)
                Spacer()
                Button("Open config…") { store.openConfiguration() }
                Button("Reload") { store.reloadConfiguration() }
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 330)
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

    init(store: QuotaSnapshotStore, original: BurnbarConfiguration.Profile?) {
        self.store = store
        self.original = original
        _draft = State(initialValue: original ?? .init(
            id: UUID().uuidString, provider: .codex, name: "", indicator: "",
            home: "", enabled: true
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
                                          enabled: draft.enabled, color: draft.color)
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
                    Text("Abbreviation")
                    TextField("Abbreviation", text: $draft.indicator, prompt: Text("P"))
                        .labelsHidden()
                }
                GridRow(alignment: .center) {
                    Text("Color")
                    ColorPicker("Color", selection: Binding(
                        get: { Color.accent(for: draft.accent) },
                        set: { draft.color = $0.hexRGB }
                    ), supportsOpacity: false)
                    .labelsHidden()
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
                              || !(1...2).contains(draft.indicator.count) || draft.indicator.contains(where: \.isWhitespace))
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
        if draft.color == nil { draft.color = Color.accent(for: draft.accent).hexRGB }
        if store.saveProfile(draft, replacing: original) { dismiss() }
        else { error = store.configurationError }
    }
}
