#!/bin/sh
set -eu

source_dir=$(cd "$(dirname "$0")" && pwd)
destination=${1:-"$source_dir/build"}
architecture=${2:-$(/usr/bin/uname -m)}
signing_identity=${WEEKPLAN_SIGNING_IDENTITY:--}
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
widget="$bundle/Contents/PlugIns/WeekPlanWidget.appex"
widget_entitlements="$staging/Widget.entitlements"
app_entitlements="$staging/App.entitlements"
signing_timestamp=--timestamp=none
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$widget/Contents/MacOS"

compile() {
    target_architecture=$1
    shift
    /usr/bin/xcrun swiftc -swift-version 6 -O -target "$target_architecture-apple-macosx14.0" \
        -module-cache-path "$source_dir/build/module-cache" "$@"
}

build_binary() {
    executable=$1
    shift
    case "$architecture" in
        universal)
            slice_prefix="$staging/$(basename "$executable")"
            compile arm64 "$@" -o "$slice_prefix-arm64"
            compile x86_64 "$@" -o "$slice_prefix-x86_64"
            /usr/bin/lipo -create "$slice_prefix-arm64" "$slice_prefix-x86_64" -output "$executable"
            ;;
        arm64|x86_64)
            compile "$architecture" "$@" -o "$executable"
            ;;
        *)
            printf '不支持的架构：%s\n' "$architecture" >&2
            exit 1
            ;;
    esac
}

sign_bundle() {
    if [ "$signing_identity" = "-" ]; then
        /usr/bin/codesign --force --sign - --timestamp=none "$@"
    else
        /usr/bin/codesign --force --sign "$signing_identity" "$signing_timestamp" --options runtime "$@"
    fi
}

build_binary "$bundle/Contents/MacOS/WeekPlan" \
    "$source_dir"/Shared/*.swift "$source_dir"/Sources/*.swift
build_binary "$widget/Contents/MacOS/WeekPlanWidget" -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain -framework Foundation \
    "$source_dir"/Shared/*.swift "$source_dir"/Widget/*.swift
cp "$source_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$source_dir/Resources/WidgetInfo.plist" "$widget/Contents/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
    value=$(/usr/bin/plutil -extract "$key" raw "$bundle/Contents/Info.plist")
    /usr/bin/plutil -insert "$key" -string "$value" "$widget/Contents/Info.plist"
done

cp "$source_dir/Resources/Widget.entitlements" "$widget_entitlements"
if [ "$signing_identity" != "-" ]; then
    # Read the team from the selected certificate without embedding a local team ID in the source.
    signing_probe="$staging/signing-probe"
    cp "$bundle/Contents/MacOS/WeekPlan" "$signing_probe"
    /usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$signing_probe"
    signing_details=$(/usr/bin/codesign --display --verbose=4 "$signing_probe" 2>&1)
    team_id=$(printf '%s\n' "$signing_details" | /usr/bin/sed -n 's/^TeamIdentifier=//p')
    case "$team_id" in
        ''|*[!A-Z0-9]*)
            printf '小组件共享数据需要有团队标识的 Apple 签名身份。\n' >&2
            exit 1
            ;;
    esac
    case "$signing_details" in
        *'Authority=Developer ID Application:'*) signing_timestamp=--timestamp ;;
    esac
    group_id="$team_id.$(/usr/bin/plutil -extract CFBundleIdentifier raw "$bundle/Contents/Info.plist")"
    /usr/bin/plutil -create xml1 "$app_entitlements"
    for entitlements in "$app_entitlements" "$widget_entitlements"; do
        /usr/libexec/PlistBuddy -c 'Add :com.apple.security.application-groups array' \
            -c "Add :com.apple.security.application-groups:0 string $group_id" "$entitlements"
    done
    for info in "$bundle/Contents/Info.plist" "$widget/Contents/Info.plist"; do
        /usr/bin/plutil -insert WeekPlanWidgetGroupIdentifier -string "$group_id" "$info"
    done
fi

/usr/bin/xcrun swift -module-cache-path "$source_dir/build/module-cache" \
    "$source_dir/DrawIcon.swift" "$staging/icon.png"
/usr/bin/sips -z 512 512 "$staging/icon.png" --out "$staging/icon-512.png" >/dev/null
/usr/bin/sips -s format icns "$staging/icon-512.png" \
    --out "$bundle/Contents/Resources/AppIcon.icns" >/dev/null
sign_bundle --entitlements "$widget_entitlements" "$widget"
if [ -f "$app_entitlements" ]; then
    sign_bundle --entitlements "$app_entitlements" "$bundle"
else
    sign_bundle "$bundle"
fi
/usr/bin/codesign --verify --strict --deep --all-architectures "$bundle"
mv "$bundle" "$app"
printf '%s\n' "$app"
