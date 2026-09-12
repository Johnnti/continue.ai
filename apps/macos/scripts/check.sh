#!/bin/sh

set -eu

package_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repository_directory=$(CDPATH= cd -- "$package_directory/../.." && pwd)

swift package --package-path "$package_directory" dump-package >/dev/null
swift run --package-path "$package_directory" -Xswiftc -warnings-as-errors ContinueCoreChecks
swift build --package-path "$package_directory" -Xswiftc -warnings-as-errors --product ContinueApp
swift build --package-path "$package_directory" -Xswiftc -warnings-as-errors --product ContinueControlExtension

(
    cd "$repository_directory"
    corepack pnpm typecheck
    corepack pnpm exec tsc -p apps/macos/ContractVerification/tsconfig.json
    corepack pnpm exec tsx apps/macos/ContractVerification/verify-contracts.ts
)
