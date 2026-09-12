#if compiler(>=6.2)
import AppIntents
import SwiftUI
import WidgetKit

@main
@available(macOS 26.0, *)
struct ContinueControl: ControlWidget {
    static let kind = "ai.continue.control.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(
                action: OpenURLIntent(URL(string: "continue://conversation")!)
            ) {
                Label("Open Continue", systemImage: "waveform.circle.fill")
            }
        }
        .displayName("Continue")
        .description("Open your latest checkpoint and voice conversation.")
    }
}
#else
import Foundation

@main
enum ContinueControlUnavailable {
    static func main() {
        FileHandle.standardError.write(
            Data("Continue Control requires the macOS 26 SDK.\n".utf8)
        )
    }
}
#endif
