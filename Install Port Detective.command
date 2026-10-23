#!/bin/bash
# Double-click this file in Finder to build Port Detective and install it.
# It compiles the app on your Mac with Apple's free Command Line Tools,
# copies it to your Applications folder and opens it.

APP_NAME="Port Detective"
EXECUTABLE="PortDetective"
HERE="$(cd "$(dirname "$0")" && pwd)"
# The source sits next to this file in the GitHub repository,
# or in a PortDetective-source folder in the older download.
if [ -f "$HERE/Package.swift" ]; then
  SOURCE="$HERE"
else
  SOURCE="$HERE/PortDetective-source"
fi
LOG="$HOME/Library/Logs/Port Detective install.log"

heading() { printf '\n\033[1m%s\033[0m\n' "$1"; }

pause_and_exit() {
  echo
  read -n 1 -s -r -p "Press any key to close this window."
  echo
  exit "$1"
}

alert() {
  # alert "Title" "Message"
  /usr/bin/osascript - "$1" "$2" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display dialog (item 2 of argv) with title (item 1 of argv) buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

clear
heading "Port Detective installer"

# 1. macOS version
VERSION="$(sw_vers -productVersion)"
MAJOR="${VERSION%%.*}"
if [ "$MAJOR" -lt 14 ]; then
  heading "Port Detective needs macOS 14 Sonoma or later. This Mac has macOS $VERSION."
  pause_and_exit 1
fi

# 2. Source code next to this file
if [ ! -f "$SOURCE/Package.swift" ]; then
  heading "The app’s source code is missing."
  echo "Keep everything from the download together in one folder, then run this again."
  pause_and_exit 1
fi

# 3. Apple's developer tools
if ! xcode-select -p >/dev/null 2>&1; then
  heading "Apple's Command Line Tools are needed to build the app."
  echo "Asking macOS to install them:"
  xcode-select --install 2>&1 | sed 's/^/    /'
  echo
  echo "A window should open asking to install them. If it's hidden, look for"
  echo "\"Install Command Line Developer Tools\" in the Dock. Click Install, wait for it"
  echo "to finish (usually 5 to 15 minutes), then run this installer again."
  alert "Port Detective" "Click Install in the Command Line Tools window. When it has finished, run the installer again."
  pause_and_exit 0
fi

SWIFT_CHECK="$(xcrun --find swift 2>&1)"
if [ $? -ne 0 ]; then
  if echo "$SWIFT_CHECK" | grep -qi "license"; then
    heading "Apple's developer tools need their license accepted first."
    echo "Run this command and type your Mac password when asked (it won't show as you type):"
    echo
    echo "    sudo xcodebuild -license accept"
  else
    heading "Apple's Command Line Tools are installed but not working."
    echo "macOS said:"
    echo "$SWIFT_CHECK" | sed 's/^/    /'
    echo
    echo "Run this command and type your Mac password when asked (it won't show as you type):"
    echo
    echo "    sudo xcode-select --reset"
  fi
  echo
  echo "Then run this installer again."
  pause_and_exit 1
fi

# 4. Build in a temporary folder, so spaces in the download path can't trip the compiler
WORK="$(mktemp -d /tmp/portdetective.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
ditto "$SOURCE" "$WORK/src"
xattr -cr "$WORK/src" 2>/dev/null

heading "Building Port Detective. The first build takes a minute or two…"
mkdir -p "$(dirname "$LOG")"
( cd "$WORK/src" && /bin/bash build.sh ) 2>&1 | tee "$LOG"
BUILD_STATUS=${PIPESTATUS[0]}

if [ "$BUILD_STATUS" -ne 0 ] || [ ! -d "$WORK/src/build/$APP_NAME.app" ]; then
  if grep -qiE "xcode license|license agreement" "$LOG"; then
    heading "Apple's developer tools need their license accepted first."
    echo "Open Terminal, run this command and type your Mac password when asked:"
    echo
    echo "    sudo xcodebuild -license accept"
    echo
    echo "Then double-click this installer again."
  else
    heading "The build didn't finish."
    echo "The full log is saved at:"
    echo "    $LOG"
    echo "Copy the lines above that start with \"error:\" and send them over to get them fixed."
  fi
  pause_and_exit 1
fi

# 5. Install
DEST="/Applications"
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi
pkill -x "$EXECUTABLE" >/dev/null 2>&1
sleep 0.5
rm -rf "$DEST/$APP_NAME.app"
if ! ditto "$WORK/src/build/$APP_NAME.app" "$DEST/$APP_NAME.app"; then
  heading "Couldn't copy the app into $DEST."
  pause_and_exit 1
fi

# 6. Launch
open "$DEST/$APP_NAME.app"
heading "Installed to $DEST/$APP_NAME.app"
echo "Look for the connector icon in your menu bar, then plug in a drive, hub or charger."
alert "Port Detective is installed" "Look for the connector icon near the clock in your menu bar. Plug in a drive, hub or charger to try it."
pause_and_exit 0
