//
//  PreferencesView.swift
//  NegSwift
//

import SwiftUI

struct PreferencesView: View {
    @Bindable var preferences: AppPreferences
    @Bindable var session: EngineSession

    var body: some View {
        Form {
            Section {
                Picker("Preview quality", selection: $preferences.previewQuality) {
                    ForEach(PreviewQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .accessibilityIdentifier("negSwift.prefs.previewQuality")

                Toggle("Use GPU for preview and export", isOn: $preferences.preferGPU)
                    .accessibilityIdentifier("negSwift.prefs.useGPU")

                Toggle("Auto-detect C-41 / B&W on new scans", isOn: $preferences.autodetectProcessMode)
                    .accessibilityIdentifier("negSwift.prefs.autodetectProcessMode")

                Toggle("Auto crop film borders", isOn: $preferences.autoCropEnabled)
                    .accessibilityIdentifier("negSwift.prefs.autoCropEnabled")
            } header: {
                Text("Rendering")
            } footer: {
                Text(
                    "Lower preview quality renders faster. GPU falls back to CPU when unavailable. "
                        + "Auto-detect runs only on scans without a saved .negpy sidecar. "
                        + "Auto crop trims scanner bed borders on new scans; turn off to keep the full frame."
                )
            }

            Section {
                Picker("NegPy data folder", selection: $preferences.userDataLocation) {
                    ForEach(NegPyUserDataLocation.allCases) { location in
                        Text(location.label).tag(location)
                    }
                }
                .accessibilityIdentifier("negSwift.prefs.dataLocation")

                if preferences.userDataLocation == .custom {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(customFolderLabel)
                                .lineLimit(2)
                                .font(.body)
                        }
                        Spacer()
                        Button("Choose…") {
                            Task { await chooseCustomDataFolder() }
                        }
                    }
                }

                LabeledContent("Active path") {
                    Text(preferences.resolvedUserDataDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
            } header: {
                Text("Engine data")
            } footer: {
                Text(
                    "Stores edits.db and cache. Choose NegPy desktop to share the database with full NegPy. "
                        + "Changing this restarts the engine."
                )
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 480)
        .accessibilityIdentifier("negSwift.settings")
        .disabled(session.isRestartingEngine)
        .overlay {
            if session.isRestartingEngine {
                ProgressView("Restarting engine…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onChange(of: preferences.userDataLocation) { _, location in
            if location == .custom, preferences.customUserDataPath == nil {
                Task { await chooseCustomDataFolder() }
            }
        }
    }

    private var customFolderLabel: String {
        if let path = preferences.customUserDataPath {
            return (path as NSString).lastPathComponent
        }
        return "Not chosen"
    }

    private func chooseCustomDataFolder() async {
        guard let url = await FolderPicker.chooseFolder(
            prompt: "Engine Data Folder",
            recentKind: nil
        ) else { return }
        preferences.updateCustomUserDataPath(url.path)
    }
}

#Preview {
    PreferencesView(preferences: AppPreferences(), session: .preview)
}
