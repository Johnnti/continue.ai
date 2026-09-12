import ContinueCore
import SwiftUI

struct WaveformView: View {
    let state: VoiceState
    let levels: [Double]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || !isAnimated)) { timeline in
            Canvas { context, size in
                drawWaveform(
                    context: &context,
                    size: size,
                    date: timeline.date
                )
            }
        }
        .frame(height: 68)
        .padding(.horizontal, 10)
        .background(waveColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice waveform")
        .accessibilityValue(accessibilityState)
    }

    private func drawWaveform(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        let barCount = 32
        let spacing: CGFloat = 3
        let availableWidth = max(0, size.width - spacing * CGFloat(barCount - 1))
        let barWidth = max(2, availableWidth / CGFloat(barCount))
        let samples = WaveformMath.normalizedLevels(levels, barCount: barCount)
        let phase = date.timeIntervalSinceReferenceDate * 4

        for (index, sample) in samples.enumerated() {
            let movement = reduceMotion ? 1 : 0.9 + 0.1 * sin(phase + Double(index) * 0.55)
            let barHeight = max(5, size.height * CGFloat(sample * movement))
            let x = CGFloat(index) * (barWidth + spacing)
            let y = (size.height - barHeight) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
            let opacity = 0.55 + 0.45 * sample

            context.fill(path, with: .color(waveColor.opacity(opacity)))
        }
    }

    private var isAnimated: Bool {
        switch state {
        case .connecting, .listening, .thinking, .speaking:
            true
        case .disconnected, .muted, .failed:
            false
        }
    }

    private var waveColor: Color {
        switch state {
        case .listening:
            ContinueTheme.success
        case .failed:
            .red
        case .disconnected, .muted:
            .secondary
        case .connecting, .thinking, .speaking:
            ContinueTheme.accent
        }
    }

    private var accessibilityState: String {
        switch state {
        case .disconnected:
            "Voice is disconnected"
        case .connecting:
            "Voice is connecting"
        case .listening:
            "Voice is listening"
        case .thinking:
            "Voice is preparing a response"
        case .speaking:
            "Voice is speaking"
        case .muted:
            "Voice is muted"
        case let .failed(message):
            "Voice error: \(message)"
        }
    }
}
