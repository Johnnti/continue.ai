# continue.ai

Local-first context resume assistant using macOS ScreenCaptureKit and an OpenAI-compatible vision model.

## Quick start

```bash
corepack pnpm install
corepack pnpm dev:web
```

Create a root `.env` file from `.env.example`, add your real key, and start the activity profiler:

```bash
cp .env.example .env
# Edit .env and replace the placeholder key.
corepack pnpm dev:worker
```

The worker requires macOS 14 or newer and Screen Recording permission for the terminal or IDE running it. Accessibility permission is optional but recommended: it lets the helper attach foreground-app changes, clicked controls, focused-control labels, and privacy-scrubbed browser URLs without recording typed text. URL query parameters, fragments, usernames, and passwords are removed before model analysis.

By default it captures a resized JPEG every 30 seconds, follows the display containing the foreground window, groups ten chronological observations into a five-minute episode, and sends the full batch to one OpenAI-compatible multimodal `/chat/completions` call. The saved checkpoint is already a short, voice-ready resume paragraph grounded in the original images and native activity timeline. Adjust `CONTINUE_CAPTURE_INTERVAL_SECONDS`, `CONTINUE_CAPTURE_BATCH_SIZE`, `CONTINUE_CAPTURE_MAX_WIDTH`, and `CONTINUE_CAPTURE_JPEG_QUALITY` in `.env` to tune coverage, cost, and latency. Use `OPENAI_BASE_URL` for another compatible provider.

The web app also exposes recording controls. These endpoints run the capture loop in the web process, so do not run the standalone worker at the same time:

```bash
curl -X POST http://localhost:3000/api/record/start
curl http://localhost:3000/api/record/status
curl -X POST http://localhost:3000/api/record/stop
curl -X POST http://localhost:3000/api/summary
```

`/api/summary` returns the latest episode paragraph directly; it does not summarize prior AI summaries again.

Worker process:

```bash
pnpm dev:worker
```
