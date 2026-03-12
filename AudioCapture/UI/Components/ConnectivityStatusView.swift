//
//  ConnectivityStatusView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI

struct ConnectivityStatusView: View {
    let isOnline: Bool

    var body: some View {
        if !isOnline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.caption.weight(.semibold))

                Text("No internet connection — transcriptions will be queued")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.orange)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel("Offline. Transcriptions will be queued until a connection is available.")
        }
    }
}
