#!/bin/sh
set -eu

source_dir=$(cd "$(dirname "$0")" && pwd)
destination=${1:-"$source_dir/dist"}
mkdir -p "$destination" "$source_dir/build"
destination=$(cd "$destination" && pwd)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_dir/Resources/Info.plist")
if [ -n "${WEEKPLAN_NOTARY_PROFILE:-}" ]; then
    if [ "${WEEKPLAN_SIGNING_IDENTITY:--}" = "-" ]; then
        printf '公证需要 Developer ID Application 签名。\n' >&2
        exit 1
    fi
    archive="$destination/WeeklyPlan-v$version-macOS-universal.zip"
else
    archive="$destination/WeeklyPlan-v$version-macOS-native-preview.zip"
fi
if [ -e "$archive" ]; then
    printf '安装包已存在：%s\n' "$archive" >&2
    exit 1
fi

staging=$(mktemp -d "$source_dir/build/.package.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
/bin/sh "$source_dir/build.sh" "$staging" universal >/dev/null
app="$staging/周计划.app"
candidate="$staging/WeeklyPlan.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$candidate"

if [ -n "${WEEKPLAN_NOTARY_PROFILE:-}" ]; then
    /usr/bin/xcrun notarytool submit "$candidate" --keychain-profile "$WEEKPLAN_NOTARY_PROFILE" \
        --wait --output-format json > "$staging/notary.json"
    if [ "$(/usr/bin/plutil -extract status raw "$staging/notary.json")" != Accepted ]; then
        printf 'Apple 公证未通过。\n' >&2
        exit 1
    fi
    /usr/bin/xcrun stapler staple "$app"
    /usr/bin/xcrun stapler validate "$app"
    candidate="$staging/WeeklyPlan-notarized.zip"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$candidate"
fi

mv "$candidate" "$archive"
printf '%s\n' "$archive"
