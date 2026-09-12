#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PACKAGE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen 2.46 or later is required. Install it with: brew install xcodegen" >&2
    exit 1
fi

(
    cd "$PACKAGE_ROOT"
    xcodegen generate --spec project.yml
)
