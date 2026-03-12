//
//  ContentView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        TabView {
            RecordingView(vm: coordinator.recordingViewModel)
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }

            SessionsListView()
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
