import ContinueCore
import SwiftUI

struct WaveformView: View {
    let state: VoiceState
    let levels: [Double]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        IridescenceView(
            level: levels.max() ?? 0.08,
            tint: shaderTint,
            isAnimated: !reduceMotion && isAnimated
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice waveform")
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("voice.waveform")
    }

    private var shaderTint: SIMD3<Float> {
        switch state {
        case .failed:
            SIMD3<Float>(1.0, 0.25, 0.12)
        case .listening:
            SIMD3<Float>(0.22, 0.95, 0.72)
        default:
            SIMD3<Float>(0.30, 0.62, 1.0)
        }
    }

    private func drawOrb(
        context: inout GraphicsContext,
        size: CGSize,
        date: Date
    ) {
        let level = CGFloat(min(max(levels.max() ?? 0.08, 0.08), 1))
        let phase = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
        let breathing = reduceMotion ? 1 : 1 + 0.035 * sin(phase * 3.5)
        let scale = (0.78 + level * 0.18) * breathing
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let diameter = min(size.width, size.height) * scale
        let orbRect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        let glowInset = diameter * (0.18 + level * 0.12)
        let glowRect = orbRect.insetBy(dx: -glowInset, dy: -glowInset)
        context.drawLayer { glowLayer in
            glowLayer.addFilter(.blur(radius: diameter * 0.16))
            glowLayer.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [waveColor.opacity(0.62 + level * 0.25), waveColor.opacity(0)]),
                    center: center,
                    startRadius: diameter * 0.08,
                    endRadius: diameter * 0.76
                )
            )
        }
        context.drawLayer { layer in
            layer.fill(
                Path(ellipseIn: orbRect),
                with: .radialGradient(
                    Gradient(colors: orbColors),
                    center: CGPoint(x: orbRect.midX - diameter * 0.16, y: orbRect.midY - diameter * 0.2),
                    startRadius: diameter * 0.04,
                    endRadius: diameter * 0.72
                )
            )

            let highlightOffset = CGFloat(sin(phase * 0.8)) * diameter * 0.12
            let highlightRect = orbRect.offsetBy(dx: highlightOffset, dy: -diameter * 0.12)
                .insetBy(dx: diameter * 0.2, dy: diameter * 0.28)
            layer.fill(
                Path(ellipseIn: highlightRect),
                with: .color(.white.opacity(0.11 + level * 0.12))
            )
        }
    }

    private var orbColors: [Color] {
        switch state {
        case .listening:
            [Color(red: 0.18, green: 0.96, blue: 0.68), Color(red: 0.05, green: 0.48, blue: 0.86), Color(red: 0.08, green: 0.12, blue: 0.42)]
        case .speaking:
            [Color(red: 0.42, green: 0.88, blue: 1), Color(red: 0.26, green: 0.36, blue: 0.96), Color(red: 0.18, green: 0.1, blue: 0.48)]
        case .failed:
            [.red.opacity(0.95), .orange, .red.opacity(0.25)]
        case .disconnected, .muted:
            [Color(red: 0.28, green: 0.82, blue: 0.92), Color(red: 0.22, green: 0.36, blue: 0.86), Color(red: 0.16, green: 0.12, blue: 0.42)]
        case .connecting, .thinking:
            [ContinueTheme.accent.opacity(0.95), .cyan.opacity(0.72), ContinueTheme.accent.opacity(0.2)]
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
