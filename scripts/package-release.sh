#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
release_dir="${1:-$PWD/dist/release-0.7.0}"
case "$release_dir" in /*) ;; *) echo 'Use an absolute release directory.' >&2; exit 1 ;; esac
if [[ -e "$release_dir" ]]; then
  echo "Output already exists; choose a new directory: $release_dir" >&2
  exit 1
fi
mkdir -p "$release_dir/staging"
if [[ -n "${2:-}" ]]; then
  # Ship the exact application bundle that was approved and tested locally.
  codesign --verify --strict "$2"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$2/Contents/Info.plist")" == "local.qiushan.MBAR" ]]
  ditto "$2" "$release_dir/staging/MBAR.app"
else
  MBAR_APP_DIR="$release_dir/staging/MBAR.app" ./scripts/build-app.sh
fi
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$release_dir/staging/MBAR.app/Contents/Info.plist")
arch=$(uname -m)
base="MBAR-${version}-macos-${arch}"
codesign --verify --strict "$release_dir/staging/MBAR.app"
cp README.md CONTRIBUTORS.md CONTRIBUTING.md CHANGELOG.md "$release_dir/staging/"
mkdir -p "$release_dir/staging/docs/images" "$release_dir/staging/docs/releases"
cp docs/images/*.png docs/images/README.md "$release_dir/staging/docs/images/"
cp docs/releases/v*.md "$release_dir/staging/docs/releases/"
cp docs/icon-extraction.md docs/menu-bar-lifecycle.md "$release_dir/staging/docs/"
cp LICENSE THIRD_PARTY_NOTICES.md "$release_dir/staging/"
ln -s /Applications "$release_dir/staging/Applications"
ditto -c -k --sequesterRsrc --keepParent "$release_dir/staging/MBAR.app" "$release_dir/$base.zip"
diskutil image create from --volumeName "MBAR $version" --format UDZO "$release_dir/staging" "$release_dir/$base.dmg"
(cd "$release_dir" && shasum -a 256 "$base.dmg" "$base.zip" > SHA256SUMS.txt)
echo "Release artifacts: $release_dir"
