//
//  AudioLevelMeterView.swift
//  AudioCapture
//
//  Created by Talal El Zeini on 3/11/26.
//

import SwiftUI

struct AudioLevelMeterView: View {
    let level: Float

    private let barCount = 22

    var body: some View {
        GeometryReader { geo in
            let barWidth = (geo.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let threshold = Float(i + 1) / Float(barCount)
                    let isActive  = level >= threshold

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(barColor(index: i).opacity(isActive ? 1.0 : 0.12))
                        .frame(width: barWidth)
                        .animation(.easeOut(duration: 0.06), value: level)
                }
            }
        }
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
        .accessibilityHint("Displays the current microphone input level")
    }

    private func barColor(index: Int) -> Color {
        let ratio = Double(index) / Double(barCount)
        switch ratio {
        case ..<0.55: return .green
        case ..<0.78: return .yellow
        default:      return .red
        }
    }
}

#Preview("Level meter") {
    VStack(spacing: 16) {
        ForEach([0.0, 0.3, 0.6, 0.9, 1.0] as [Float], id: \.self) { v in
            HStack {
                Text(String(format: "%.0f%%", v * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 36, alignment: .trailing)
                AudioLevelMeterView(level: v)
                    .frame(height: 24)
            }
        }
    }
    .padding()
}
