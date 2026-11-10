#!/bin/sh
set -eu

source_dir=$(cd "$(dirname "$0")" && pwd)
destination=${1:-"$source_dir/dist"}
mkdir -p "$destination" "$source_dir/build"
destination=$(cd "$destination" && pwd)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_dir/Resources/Info.plist")
archive="$destination/WeeklyPlan-v$version-macOS-universal.zip"
if [ -e "$archive" ]; then
    printf '安装包已存在：%s\n' "$archive" >&2
    exit 1
fi

staging=$(mktemp -d "$source_dir/build/.package.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
/bin/sh "$source_dir/build.sh" "$staging" universal >/dev/null
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staging/周计划.app" "$staging/WeeklyPlan.zip"
mv "$staging/WeeklyPlan.zip" "$archive"
printf '%s\n' "$archive"
