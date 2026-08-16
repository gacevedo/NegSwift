//
//  PreferencesView.swift
//  NegSwift
//

import SwiftUI

struct PreferencesView: View {
    @Bindable var session: EngineSession

    @AppStorage(AppPreferences.Key.previewQuality, store: AppPreferences.userDefaults) private var previewQualityRaw =
        AppPreferences.PreviewQuality.standard.rawValue
    @AppStorage(AppPreferences.Key.useGPU, store: AppPreferences.userDefaults) private var useGPU = true
    @AppStorage(AppPreferences.Key.dataLocation, store: AppPreferences.userDefaults) private var dataLocationRaw =
        AppPreferences.DataLocation.negSwift.rawValue

    @State private var isRestarting = false

    var body: some View {
        Form {
            Section {
                Picker("Preview quality", selection: previewQualityBinding) {
                    ForEach(AppPreferences.PreviewQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .onChange(of: previewQualityRaw) { _, _ in
                    Task { await session.refreshAfterPreferenceChange() }
                }
                .accessibilityIdentifier("negSwift.prefs.previewQuality")

                Toggle("Use GPU for preview and export", isOn: $useGPU)
                    .onChange(of: useGPU) { _, _ in
                        Task { await session.refreshAfterPreferenceChange() }
                    }
                    .accessibilityIdentifier("negSwift.prefs.useGPU")
            } header: {
                Text("Rendering")
            } footer: {
                Text("Lower preview quality renders faster. GPU falls back to CPU when unavailable.")
            }

            Section {
                Picker("NegPy data folder", selection: dataLocationBinding) {
                    ForEach(AppPreferences.DataLocation.allCases) { location in
                        Text(location.label).tag(location)
                    }
                }
                .onChange(of: dataLocationRaw) { _, newValue in
                    guard AppPreferences.DataLocation(rawValue: newValue) == .custom else {
                        Task { await restartEngineForDataFolder() }
                        return
                    }
                }
                .accessibilityIdentifier("negSwift.prefs.dataLocation")

                if dataLocation == .custom {
                    HStack {
                        Text(customDataLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("Choose…") {
                            Task { await chooseCustomDataFolder() }
                        }
                    }
                } else {
                    Text(dataFolderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Data")
            } footer: {
                Text(
                    "Sets NEGPY_USER_DIR for the engine (edits.db, cache, presets). "
                        + "Choose NegPy desktop to share the database with full NegPy. Changing this restarts the engine."
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .accessibilityIdentifier("negSwift.settings")
        .disabled(isRestarting)
        .overlay {
            if isRestarting {
                ProgressView("Restarting engine…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var previewQuality: AppPreferences.PreviewQuality {
        AppPreferences.PreviewQuality(rawValue: previewQualityRaw) ?? .standard
    }

    private var dataLocation: AppPreferences.DataLocation {
        AppPreferences.DataLocation(rawValue: dataLocationRaw) ?? .negSwift
    }

    private var previewQualityBinding: Binding<AppPreferences.PreviewQuality> {
        Binding(
            get: { previewQuality },
            set: { previewQualityRaw = $0.rawValue }
        )
    }

    private var dataLocationBinding: Binding<AppPreferences.DataLocation> {
        Binding(
            get: { dataLocation },
            set: { dataLocationRaw = $0.rawValue }
        )
    }

    private var dataFolderPath: String {
        AppPreferences.negpyUserDirectoryPath
    }

    private var customDataLabel: String {
        if let path = AppPreferences.customDataDirectoryPath, !path.isEmpty {
            return path
        }
        return "Choose a folder for edits.db and cache"
    }

    private func chooseCustomDataFolder() async {
        guard let url = await FolderPicker.chooseFolder(
            prompt: "NegPy Data Folder",
            recentKind: .importFolder
        ) else { return }
        AppPreferences.setCustomDataDirectory(url)
        dataLocationRaw = AppPreferences.DataLocation.custom.rawValue
        await restartEngineForDataFolder()
    }

    private func restartEngineForDataFolder() async {
        isRestarting = true
        defer { isRestarting = false }
        await session.restart()
    }
}

#Preview {
    PreferencesView(session: .preview)
}
