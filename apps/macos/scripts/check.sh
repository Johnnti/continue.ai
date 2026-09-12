#!/bin/sh

set -eu

package_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

swift package --package-path "$package_directory" dump-package >/dev/null
swift run --package-path "$package_directory" -Xswiftc -warnings-as-errors ContinueCoreChecks
swift build --package-path "$package_directory" -Xswiftc -warnings-as-errors --product ContinueApp
