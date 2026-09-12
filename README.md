# continue.ai

Local-first context resume assistant scaffold.

## Implementation plan

The current repository contains a mock Next.js vertical slice. The native macOS
client is being added as an isolated SwiftUI package under `apps/macos`. The
detailed plan—including architecture diagrams, data contracts, security
boundaries, milestones, tests, and trusted upstream reference code—is in
[`docs/IMPLEMENTATION_ARCHITECTURE.md`](docs/IMPLEMENTATION_ARCHITECTURE.md).
The current user-facing decisions and integration acceptance checks are in
[`docs/PRODUCT_DECISIONS.md`](docs/PRODUCT_DECISIONS.md); that decision record
overrides older product-flow wording in the long-form plan.

## Quick start

Native macOS preview app:

```bash
swift run --package-path apps/macos ContinueApp
```

Run the focused Swift checks and compile the app with warnings treated as
errors:

```bash
apps/macos/scripts/check.sh
```

Temporary web harness:

```bash
pnpm install
pnpm dev:web
```

Worker process:

```bash
pnpm dev:worker
```

Optional demo seed:

```bash
pnpm seed:demo
```

Both clients work without API keys and use mock Screenpipe, context, voice, and
resume integrations by default.
