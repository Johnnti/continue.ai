# continue.ai

Continue is a local-first context-resume assistant. The repository contains a
native macOS client and a separate web harness. The macOS client reads the
shared SQLite checkpoint database, starts ElevenLabs conversations through the
official Swift SDK, and presents a voice-first return checkpoint without
focusing another app, reopening windows, or writing raw screen/audio data to
Continue's store.

The product decisions are recorded in
[`docs/PRODUCT_DECISIONS.md`](docs/PRODUCT_DECISIONS.md). The longer research
and implementation plan—including data contracts, security boundaries, trusted
reference repositories, and future integration work—is in
[`docs/IMPLEMENTATION_ARCHITECTURE.md`](docs/IMPLEMENTATION_ARCHITECTURE.md).

## Run the macOS desktop preview

Requirements:

- macOS 14 or later.
- Swift 6 toolchain (Xcode 16 or the matching Command Line Tools).
- A Metal-capable Mac for the iridescent waveform renderer.

From the repository root, run:

```bash
apps/macos/scripts/run-app.sh
```

The script builds a local `ContinuePreview.app` in the macOS user cache,
embeds the Control Center extension, signs both bundles for local use, opens the
Continue window, and adds a Continue item to the menu bar. Quit Continue from
its menu-bar item when you finish using the preview.

The native client uses `PreviewRuntimeProvider` until the live Screenpipe
coordinator is connected, but its checkpoint and voice boundaries are live:
`SQLiteCheckpointProvider` reads the shared `data/memory.sqlite` schema,
`StoredCheckpointResumeProvider` validates targets from that database, and
`ElevenLabsVoiceProvider` starts the configured public agent or requests a
short-lived conversation token. If the database has no records, the UI shows
an empty state instead of silently substituting fixture data.

Useful native commands:

```bash
# Compile only the desktop executable.
swift build --package-path apps/macos --product ContinueApp

# Build and validate the Control Center extension without opening the app.
apps/macos/scripts/run-app.sh --no-open

# Run the deterministic core checks (26 checks at the time of writing).
swift run --package-path apps/macos ContinueCoreChecks

# Run Swift checks, build with warnings-as-errors, then run workspace checks.
apps/macos/scripts/check.sh
```

The final command also checks the web workspaces. If an upstream web commit has
introduced a dependency that is not yet declared in `apps/web/package.json`,
the web typecheck can fail even when the macOS checks pass; fix that dependency
in the web owner's change before treating the full command as green.

To open the package in Xcode for previews or signing work:

```bash
open apps/macos/Package.swift
```

## Configure local policies

Settings are saved in `UserDefaults` under `continue.app-preferences.v1` and
restored the next time Continue opens. The preview exposes:

- **Record activity with Screenpipe** and **Create return summaries** as
  separate switches, so pausing summaries never stops raw capture.
- **Create checkpoints** to choose automatic checkpoints, manual **I'm stepping
  away** checkpoints, or both.
- **Away threshold** from 1 to 60 minutes before a return counts as a
  checkpoint-worthy break.
- **Tracking schedule** to limit activity to a daily window, including windows
  that cross midnight.
- **Observation window** of 5, 15, 30, or 60 minutes of source context for a
  summary.
- **Excluded applications** that are trimmed, deduplicated case-insensitively,
  and skipped when summaries are created.
- **Checkpoint retention** of 1, 7, or 30 days for interpreted summaries.
- **Screenpipe raw-data retention**, where **Screenpipe manages** is the
  default; Continue keeps only its own interpreted checkpoints.
- **Voice conversations** enabled or disabled separately from capture.

Older saved payloads are decoded with conservative defaults for any preference
that does not exist yet, so upgrades do not reset the controls a person set.

## Live integrations

The native app reads the same SQLite database used by the TypeScript memory
package. Set `CONTINUE_MEMORY_DATABASE_PATH` when the database is outside the
repository; the preview script automatically points the app at
`data/memory.sqlite`. The native adapter creates the compatible `memories`
table when the database is new and reads only compact interpreted checkpoint
JSON, never raw Screenpipe frames or microphone audio.

Voice uses the pinned ElevenLabs Conversational AI Swift SDK (`3.3.1`). A
public agent can connect with `CONTINUE_ELEVENLABS_AGENT_ID` (the existing
public demo agent is the default). Private agents should set
`CONTINUE_ELEVENLABS_TOKEN_URL` to a backend endpoint that returns
`{"token":"..."}` or `{"conversation_token":"..."}`. The ElevenLabs API key
must remain on that backend and is never bundled in the macOS app.

The voice adapter passes the current checkpoint as dynamic context, sends the
written briefing after connection, maps agent/VAD state into the waveform, and
handles the initial client tools: `get_last_session`, `get_session_context`,
and `request_resume_workspace`. The last tool only opens Continue's local
approval sheet; it cannot open a file, URL, or application by itself.

## Add the Control Center button

On macOS 26 or later, Continue supplies an **Open Continue** control with the
waveform icon. The button opens the app directly on the current conversation
and checkpoint. It does not start recording, generate a summary, or resume
another application.

The checked-in bundle script compiles, embeds, and registers the extension for
structural verification with the Command Line Tools. The system gallery accepts
an Apple development-signed extension whose App Intents metadata was extracted
by full Xcode. The ad-hoc command-line preview therefore does not appear in the
gallery. To add the button:

1. Open `apps/macos/ContinueMac.xcodeproj` with Xcode 26 or later.
2. Select the same Apple development team for **Continue** and
   **ContinueControlExtension**.
3. Run the **Continue** scheme once.
4. Open macOS Control Center and choose **Edit Controls**.
5. Search for **Continue**, then add **Open Continue** to Control Center or the
   menu bar.

The generated project is defined by `apps/macos/project.yml`. After changing
that file, regenerate the project with:

```bash
brew install xcodegen
apps/macos/scripts/generate-xcode-project.sh
```

macOS 14 and macOS 15 can still run the main app and menu-bar item, but those
releases do not support third-party Control Center controls.

## Review the UI

The left sidebar contains the Conversation destination, a disclosure-controlled
Checkpoint history list, and the Screenpipe, summary, and Settings controls.
The native `NavigationSplitView` sidebar can be hidden with the standard macOS
sidebar button. The main screen puts the live voice state and 360-point
waveform at the center; written checkpoint evidence and explicit actions remain
below it.

![Continue macOS preview](docs/assets/continue-macos-preview.png)

To replace the checked-in screenshot after a UI change, start the preview and
capture only its focused window:

```bash
screencapture -i -w docs/assets/continue-macos-preview.png
```

The interactive capture lets you select the Continue window. Do not capture the
whole desktop when it contains unrelated personal or collaborator content.

## Architecture

The native preview keeps the SwiftUI composition layer separate from service
implementations. `AppModel` runs on the main actor, owns view state, and sends
user intents through narrow protocols. The preview adapters implement those
same protocols with deterministic data so the UI can be tested before live
Screenpipe, model, voice, persistence, and resume integrations land.

```mermaid
flowchart TD
    App["ContinueDesktopApp<br/>SwiftUI scenes"] --> Shell["AppShellView<br/>NavigationSplitView"]
    Control["ContinueControlExtension<br/>macOS 26 ControlWidget"] --> URL["continue://conversation"]
    URL --> App
    Shell --> Sidebar["CheckpointSidebar<br/>Conversation · history · Settings"]
    Shell --> Now["NowView<br/>status · waveform · checkpoint"]
    Shell --> Settings["SettingsView<br/>local policies"]

    Sidebar --> Model["AppModel<br/>@MainActor state + intents"]
    Now --> Model
    Settings --> Model
    Now --> Orb["WaveformView → IridescenceView<br/>Metal renderer"]

    Model --> Runtime["RuntimeProviding<br/>RuntimeControlling"]
    Model --> Checkpoints["CheckpointProviding"]
    Model --> Voice["VoiceProviding"]
    Model --> Resume["ResumeProviding"]
    Model --> Notify["ReturnNotifying"]

    subgraph Adapters["Native adapters"]
        PreviewRuntime["PreviewRuntimeProvider<br/>Screenpipe pending"]
        SQLiteCheckpoints["SQLiteCheckpointProvider"]
        ElevenLabsVoice["ElevenLabsVoiceProvider"]
        StoredResume["StoredCheckpointResumeProvider"]
        SystemNotify["SystemReturnNotifier"]
    end

    Runtime -. implements .-> PreviewRuntime
    Checkpoints -. implements .-> SQLiteCheckpoints
    Voice -. implements .-> ElevenLabsVoice
    Resume -. implements .-> StoredResume
    Notify -. implements .-> SystemNotify

    Screenpipe["Screenpipe local API<br/>live coordinator pending"] -. bounded observations .-> Runtime
    Store["SQLite memory.sqlite"] -. validated records .-> Checkpoints
    VoiceSDK["ElevenLabs Swift SDK"] -. session state + levels .-> Voice
    Workspace["Approved workspace opener<br/>pending"] -. selected targets only .-> Resume
```

The boundaries enforce these rules:

- Screenpipe remains the source of captured activity; Continue consumes bounded
  observations and stores interpreted checkpoint records, not raw screenshots
  or microphone audio.
- The runtime coordinator decides whether the user is away or returning;
  views do not infer that state independently.
- Voice starts only after an explicit user action and exposes connecting,
  listening, thinking, speaking, muted, and failed states as both animation and
  text.
- Resume proposals enter an approval view. Continue never silently focuses an
  application, reopens a target, submits a form, or executes a shell command.

## Web harness and worker

Install the workspace dependencies before using the web commands:

```bash
pnpm install
pnpm dev:web
pnpm dev:worker
```

The optional demo seed is:

```bash
pnpm seed:demo
```
