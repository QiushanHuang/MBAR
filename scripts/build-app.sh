#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_dir="${MBAR_APP_DIR:-$PWD/dist/MBAR.app}"
case "$app_dir" in /*) ;; *) echo 'MBAR_APP_DIR must be an absolute path.' >&2; exit 1 ;; esac
# Only refuse to overwrite the bundle being executed; installed copies are independent.
for pid in $(pgrep -x MBAR || true); do
  executable="$(ps -p "$pid" -o comm=)"
  if [[ "$executable" == "$app_dir/Contents/MacOS/MBAR" ]]; then
    echo 'Quit this MBAR bundle before rebuilding it.' >&2
    exit 1
  fi
done
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/MBAR" "$app_dir/Contents/MacOS/MBAR"
cp LICENSE THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
mkdir -p .build/MBAR.iconset
swift scripts/make-icon.swift "$PWD/.build/MBAR.iconset"
iconutil -c icns .build/MBAR.iconset -o "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.qiushan.MBAR</string>
<key>CFBundleName</key><string>MBAR</string>
<key>CFBundleDisplayName</key><string>MBAR</string>
<key>CFBundleExecutable</key><string>MBAR</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>13</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSScreenCaptureUsageDescription</key><string>MBAR 仅在你读取原生图标时获取菜单栏图像，用于预览和保存图标，不录制音频。</string>
</dict></plist>
PLIST
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app_dir"
codesign --verify --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
echo "$app_dir"
