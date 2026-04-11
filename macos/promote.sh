#!/bin/bash
#
# promote.sh — promote the freshly built "Ghostty Dev" into "Ghostty WRB".
#
# The ReleaseLocal Xcode configuration installs to /Applications/Ghostty Dev.app
# with bundle id com.mitchellh.ghostty.wrb.dev. That's our testing sandbox.
#
# When a build has been tested and is ready to be the daily driver, run this
# script to copy the Dev bundle into /Applications/Ghostty WRB.app with a
# distinct bundle id, display name, and menu-bar name, then re-sign it ad-hoc
# so Launch Services will open it without error -54.
#
# WRB and Dev can coexist because they have distinct bundle ids and therefore
# distinct ~/Library/Application Support state. They share the session
# snapshots under ~/.config/ghostty/sessions/.

set -euo pipefail

SRC="/Applications/Ghostty Dev.app"
DEST="/Applications/Ghostty WRB.app"

if [[ ! -d "$SRC" ]]; then
    echo "error: $SRC does not exist — build ReleaseLocal first" >&2
    exit 1
fi

echo "promote: removing old $DEST"
rm -rf "$DEST"

echo "promote: copying $SRC → $DEST"
ditto "$SRC" "$DEST"

echo "promote: rewriting Info.plist identity"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Ghostty WRB"        "$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Ghostty WRB" "$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mitchellh.ghostty.wrb" "$DEST/Contents/Info.plist"

echo "promote: re-signing ad-hoc"
codesign --force --deep --sign - "$DEST"

echo "promote: registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

echo "promote: verifying"
codesign -dv "$DEST" 2>&1 | grep -E "Identifier|Signature"

echo "promote: done — $DEST is ready"
