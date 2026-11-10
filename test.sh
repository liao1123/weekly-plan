#!/bin/sh
set -eu

source_dir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$source_dir/build/module-cache"
staging=$(mktemp -d "$source_dir/build/.tests.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM

/usr/bin/xcrun swiftc -swift-version 6 -module-cache-path "$source_dir/build/module-cache" \
    "$source_dir"/Shared/*.swift "$source_dir/Sources/Plan.swift" "$source_dir/Tests/PlanChecks.swift" \
    -o "$staging/PlanChecks"
"$staging/PlanChecks" "$staging/fixture"
