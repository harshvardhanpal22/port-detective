#!/bin/bash
# Double-click this file in Finder to remove Port Detective.

APP_NAME="Port Detective"
pkill -x PortDetective >/dev/null 2>&1

removed=0
for dir in /Applications "$HOME/Applications"; do
  if [ -d "$dir/$APP_NAME.app" ]; then
    rm -rf "$dir/$APP_NAME.app" && echo "Removed $dir/$APP_NAME.app" && removed=1
  fi
done
defaults delete com.harshvardhanpal.portdetective >/dev/null 2>&1
defaults delete com.example.portdetective >/dev/null 2>&1
rm -f "$HOME/Library/Logs/Port Detective install.log"

echo
if [ "$removed" -eq 1 ]; then
  echo "Port Detective has been removed."
else
  echo "Port Detective wasn't installed."
fi
echo "If you turned on Open at login, also check System Settings > General > Login Items."
echo
read -n 1 -s -r -p "Press any key to close this window."
echo
