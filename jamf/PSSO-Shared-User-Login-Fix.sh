#!/bin/bash

# PSSO Shared User Login Fix
# Temporary community workaround for repeat-login failures on shared Macs
# using Microsoft Entra Platform SSO.
#
# Installs an automatic login-context AppSSOAgent reset at the GUI logout
# transition. Test on non-production Macs before wider deployment.

BASE_DIR="/Library/Rian/PSSO"
RESET_SCRIPT="/usr/local/bin/psso-login-agent-reset.sh"
WATCHER_SCRIPT="$BASE_DIR/psso-logout-watcher.sh"
PLIST="/Library/LaunchDaemons/com.rian.psso-logout-watcher.plist"
LABEL="com.rian.psso-logout-watcher"

echo "Installing PSSO Shared User Login Fix..."

mkdir -p /usr/local/bin
mkdir -p "$BASE_DIR"

# ------------------------------------------------------------
# Reset script
# ------------------------------------------------------------

cat > "$RESET_SCRIPT" <<'RESET_EOF'
#!/bin/bash

LOG_FILE="/Library/Rian/PSSO/psso-reset.log"
TARGET="/System/Library/PrivateFrameworks/AppSSO.framework/Support/AppSSOAgent.app/Contents/MacOS/AppSSOAgent"

TIMESTAMP=$(/bin/date '+%Y-%m-%d %H:%M:%S')

PID=$(/bin/ps -axo user=,pid=,command= | /usr/bin/awk -v target="$TARGET" \
    '$1 == "_securityagent" && $3 == target && $4 == "-l" {print $2; exit}')

if [[ -z "$PID" ]]; then
    /bin/echo "$TIMESTAMP | reset | no login AppSSOAgent found" >> "$LOG_FILE"
    exit 0
fi

PROCESS=$(/bin/ps -p "$PID" -o user=,command=)

case "$PROCESS" in
    "_securityagent $TARGET -l")
        /bin/kill -TERM "$PID"
        RESULT=$?

        if [[ "$RESULT" -eq 0 ]]; then
            /bin/echo "$TIMESTAMP | reset | terminated login AppSSOAgent PID $PID" >> "$LOG_FILE"
            exit 0
        fi

        /bin/echo "$TIMESTAMP | reset | ERROR terminating PID $PID (exit $RESULT)" >> "$LOG_FILE"
        exit 1
        ;;
    *)
        /bin/echo "$TIMESTAMP | reset | SAFETY ABORT: PID $PID no longer matches login AppSSOAgent" >> "$LOG_FILE"
        exit 1
        ;;
esac
RESET_EOF

# ------------------------------------------------------------
# Logout watcher
# ------------------------------------------------------------

cat > "$WATCHER_SCRIPT" <<'WATCHER_EOF'
#!/bin/bash

RESET_SCRIPT="/usr/local/bin/psso-login-agent-reset.sh"
STATE_FILE="/Library/Rian/PSSO/last-console-user"

CURRENT_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null)

[[ -z "$CURRENT_USER" ]] && exit 0

LAST_USER=""
[[ -f "$STATE_FILE" ]] && LAST_USER=$(/bin/cat "$STATE_FILE")

# Reset only when we transition from a real GUI user to the login window.
if [[ "$CURRENT_USER" == "root" && -n "$LAST_USER" && "$LAST_USER" != "root" ]]; then
    /bin/sleep 2

    # Make sure we are STILL at the login window before touching AppSSOAgent.
    VERIFY_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null)

    if [[ "$VERIFY_USER" == "root" ]]; then
        "$RESET_SCRIPT"
        /usr/bin/logger -t PSSOLogoutWatcher \
            "Logout detected: $LAST_USER -> root; login AppSSOAgent reset requested"
    fi
fi

/bin/echo "$CURRENT_USER" > "$STATE_FILE"

exit 0
WATCHER_EOF

# ------------------------------------------------------------
# LaunchDaemon
# ------------------------------------------------------------

cat > "$PLIST" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rian.psso-logout-watcher</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Library/Rian/PSSO/psso-logout-watcher.sh</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StartInterval</key>
    <integer>2</integer>

    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLIST_EOF

# ------------------------------------------------------------
# Ownership and permissions
# ------------------------------------------------------------

chown root:wheel "$RESET_SCRIPT"
chmod 755 "$RESET_SCRIPT"

chown -R root:wheel "$BASE_DIR"
chmod 755 "$BASE_DIR"
chmod 755 "$WATCHER_SCRIPT"

chown root:wheel "$PLIST"
chmod 644 "$PLIST"

# ------------------------------------------------------------
# Validate before loading
# ------------------------------------------------------------

/bin/bash -n "$RESET_SCRIPT"
if [[ $? -ne 0 ]]; then
    echo "ERROR: Reset script failed syntax validation."
    exit 1
fi

/bin/bash -n "$WATCHER_SCRIPT"
if [[ $? -ne 0 ]]; then
    echo "ERROR: Watcher script failed syntax validation."
    exit 1
fi

/usr/bin/plutil -lint "$PLIST"
if [[ $? -ne 0 ]]; then
    echo "ERROR: LaunchDaemon plist failed validation."
    exit 1
fi

# ------------------------------------------------------------
# Load / refresh LaunchDaemon
# ------------------------------------------------------------

/bin/launchctl bootout system/"$LABEL" 2>/dev/null
/bin/launchctl bootstrap system "$PLIST"
RESULT=$?

if [[ "$RESULT" -ne 0 ]]; then
    echo "ERROR: Failed to bootstrap $LABEL"
    exit 1
fi

echo "PSSO Shared User Login Fix installed successfully."
echo "Reset log: /Library/Rian/PSSO/psso-reset.log"

exit 0
