#!/bin/zsh
set -eu
readonly PROJECT_ROOT=${0:A:h:h}
readonly BUILD_ROOT=${CODEX_UPDATE_HELPER_BUILD_ROOT:-$PROJECT_ROOT/build}
readonly APP="$BUILD_ROOT/Codex Updater.app"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/zsh "$PROJECT_ROOT/scripts/build-icon.sh"
/bin/cp "$BUILD_ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/clang -fobjc-arc -Wall -Wextra -Werror -framework Cocoa -framework ApplicationServices \
  "$PROJECT_ROOT/native/quit-guard.m" "$PROJECT_ROOT/native/settings.m" -o "$APP/Contents/MacOS/codex-update-helper-quit"
/bin/cp "$PROJECT_ROOT/bin/codex-updater" "$APP/Contents/Resources/codex-updater"
/bin/chmod 755 "$APP/Contents/Resources/codex-updater"
/bin/ln -sf codex-updater "$APP/Contents/Resources/codex-update-helper"
/bin/cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.exprmntl.codex-update-helper.quit-guard</string>
<key>CFBundleName</key><string>Codex Updater</string>
<key>CFBundleDisplayName</key><string>Codex Updater</string>
<key>CFBundleExecutable</key><string>codex-update-helper-quit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - --identifier dev.exprmntl.codex-update-helper.quit-guard "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/bin/echo "$APP"
