//
//  SettingsView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var apiKeyDraft:  String = ""
    @State private var apiKeySaved:  Bool   = false
    @State private var apiKeyHidden: Bool   = true

    var body: some View {
        NavigationStack {
            List {
                apiKeySection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear(perform: loadAPIKeyFromKeychain)
        }
    }

    private var apiKeySection: some View {
        Section {
            HStack(spacing: 8) {
                Group {
                    if apiKeyHidden {
                        SecureField("sk-…", text: $apiKeyDraft)
                    } else {
                        TextField("sk-…", text: $apiKeyDraft)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .submitLabel(.done)
                .onSubmit(saveAPIKey)

                Button {
                    apiKeyHidden.toggle()
                } label: {
                    Image(systemName: apiKeyHidden ? "eye" : "eye.slash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(apiKeyHidden ? "Show API key" : "Hide API key")

                if apiKeySaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button("Save", action: saveAPIKey)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: apiKeySaved)
        } header: {
            Text("OpenAI API Key")
        } footer: {
            Text("Your key is stored in the iOS Keychain and never transmitted except to api.openai.com. After 5 consecutive Whisper failures the app automatically falls back to on-device Apple Speech Recognition.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(appVersion).foregroundStyle(.secondary)
            }
            LabeledContent("Build") {
                Text(buildNumber).foregroundStyle(.secondary)
            }
        }
    }

    private func loadAPIKeyFromKeychain() {
        apiKeyDraft = (try? KeychainManager.read(forKey: KeychainManager.Keys.openAIAPIKey)) ?? ""
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? KeychainManager.save(trimmed, forKey: KeychainManager.Keys.openAIAPIKey)
        withAnimation { apiKeySaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { apiKeySaved = false }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
