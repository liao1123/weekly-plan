#!/bin/sh
set -eu

source_dir=$(cd "$(dirname "$0")" && pwd)
destination=${1:-"$source_dir/build"}
architecture=${2:-$(/usr/bin/uname -m)}
mkdir -p "$destination" "$source_dir/build/module-cache"
destination=$(cd "$destination" && pwd)
app="$destination/周计划.app"

if [ -e "$app" ]; then
    printf '目标已存在：%s\n' "$app" >&2
    exit 1
fi

staging=$(mktemp -d "$destination/.week-plan.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
bundle="$staging/周计划.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

compile() {
    /usr/bin/xcrun swiftc -swift-version 6 -O -target "$1-apple-macosx14.0" \
        -module-cache-path "$source_dir/build/module-cache" \
        "$source_dir"/Sources/*.swift -o "$2"
}

executable="$bundle/Contents/MacOS/WeekPlan"
case "$architecture" in
    universal)
        compile arm64 "$staging/WeekPlan-arm64"
        compile x86_64 "$staging/WeekPlan-x86_64"
        /usr/bin/lipo -create "$staging/WeekPlan-arm64" "$staging/WeekPlan-x86_64" -output "$executable"
        ;;
    arm64|x86_64)
        compile "$architecture" "$executable"
        ;;
    *)
        printf '不支持的架构：%s\n' "$architecture" >&2
        exit 1
        ;;
esac
cp "$source_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"

/usr/bin/xcrun swift -module-cache-path "$source_dir/build/module-cache" \
    "$source_dir/DrawIcon.swift" "$staging/icon.png"
/usr/bin/sips -z 512 512 "$staging/icon.png" --out "$staging/icon-512.png" >/dev/null
/usr/bin/sips -s format icns "$staging/icon-512.png" \
    --out "$bundle/Contents/Resources/AppIcon.icns" >/dev/null
/usr/bin/codesign --force --sign - --timestamp=none "$bundle"
/usr/bin/codesign --verify --strict --deep "$bundle"
mv "$bundle" "$app"
printf '%s\n' "$app"
