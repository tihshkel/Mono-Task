#!/bin/bash
set -euo pipefail

repository="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${DERIVED_DATA_PATH:-$repository/build/macOS}"
output_directory="${OUTPUT_DIR:-$repository/build/releases}"
package_arguments=(-clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH:-$derived_data/SourcePackages}")
if [[ -n "${SOURCE_PACKAGES_PATH:-}" ]]; then
    package_arguments+=(-disableAutomaticPackageResolution)
fi

xcodebuild -project "$repository/MonoTask.xcodeproj" -scheme MonoTask \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" "${package_arguments[@]}" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="${MAC_SIGN_IDENTITY:--}" \
    DEVELOPMENT_TEAM="${MAC_DEVELOPMENT_TEAM:-}" build

application="$derived_data/Build/Products/Release/MonoTask.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application/Contents/Info.plist")"
binary="$application/Contents/MacOS/MonoTask"
lipo "$binary" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$application"
mkdir -p "$output_directory"
archive="MonoTask-$version-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$application" "$output_directory/$archive"
(cd "$output_directory" && shasum -a 256 "$archive" > "$archive.sha256")
printf '\nApplication: %s\nArchive: %s/%s\n' "$application" "$output_directory" "$archive"
