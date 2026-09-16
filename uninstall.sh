#!/bin/bash

# Removes only the files installed by PSSO Shared User Login Fix.

LABEL="com.rian.psso-logout-watcher"
PLIST="/Library/LaunchDaemons/com.rian.psso-logout-watcher.plist"
BASE_DIR="/Library/Rian/PSSO"
RESET_SCRIPT="/usr/local/bin/psso-login-agent-reset.sh"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root."
    exit 1
fi

/bin/launchctl bootout system/"$LABEL" 2>/dev/null || true

/bin/rm -f "$PLIST"
/bin/rm -f "$RESET_SCRIPT"
/bin/rm -rf "$BASE_DIR"

echo "PSSO Shared User Login Fix removed."
echo "No PSSO registration, keychain, CryptoTokenKit, or user account data was modified."

exit 0
