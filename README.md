# PSSO Shared User Login Fix

Temporary macOS workaround for a repeat-login failure seen on **shared / multi-user Macs using Microsoft Entra Platform SSO (PSSO)**.

> [!IMPORTANT]
> This is an **independent, community-tested workaround**, not an official Microsoft, Apple, or Jamf fix. It terminates an Apple system login-context process at the login window so `launchd` can start a fresh instance for the next PSSO login. Test carefully in your own environment and remove the workaround when the underlying platform issue is fixed.

## The problem

In the affected shared-Mac scenario, the first PSSO login for a user succeeds, but a later user can fail to sign in after another PSSO user logs out. A restart may temporarily clear the condition.

A representative sequence is:

```text
User A login  -> success
User A logout
User B login  -> success
User B logout
User C login  -> success
User C logout
User A/B repeat login -> failure
```

The important observation is that **Microsoft/Entra password authentication can already have succeeded**. The failure occurs later in the macOS Platform SSO / CryptoTokenKit handoff.

In testing, the failing path showed errors such as:

```text
NSCocoaErrorDomain Code=4099
The connection to service created from an endpoint was invalidated

com.apple.PlatformSSO Code=-1001
No driver config for user.

Certificate or key not found for token verification.
```

The affected login-context process is Apple's system instance of `AppSSOAgent`:

```text
_securityagent .../AppSSOAgent -l
```

This is different from the normal per-user `AppSSOAgent` process.

## What the workaround does

At a real macOS login-window transition, `/dev/console` reports `root`.

The workaround:

1. Tracks the current GUI console user.
2. Detects a transition from a real user to `root` (logout -> login window).
3. Waits 2 seconds and verifies that the Mac is **still** at the login window.
4. Finds only the exact Apple login-context process running as `_securityagent` with the `-l` argument.
5. Revalidates that PID immediately before acting.
6. Sends `TERM` to that process only.
7. Lets macOS/`launchd` demand-start a fresh login-context `AppSSOAgent` for the next PSSO login.

It does **not** kill normal per-user `AppSSOAgent` processes, modify PSSO tokens, delete keychain items, disable SIP, unregister Platform SSO, or require a reboot.

## Test results

This workaround was reproduced on **two independent test Macs**, including macOS Tahoe 26 and a newer macOS test system. Cross-user and same-user logout/login cycles succeeded after the workaround was installed.

Examples tested included:

```text
B -> C -> success
C -> A -> success
A -> B -> success
B -> B -> success
```

During testing, some users received a **one-time login keychain password prompt**. After entering the user's existing login-keychain password once, subsequent user switching continued to work. Treat this as an observed side effect, not guaranteed behavior.

## Requirements / assumptions

This project is intended for Macs already configured for Microsoft Platform SSO shared-device use. Microsoft's shared-device documentation requires settings such as **Use Shared Device Keys**, user creation/authorization configuration, and appropriate token-to-user mapping. Confirm your PSSO configuration independently before using this workaround.

The workaround was developed around the password-based shared-user scenario. It should not be treated as a generic repair for every Platform SSO login problem.

## Installation

The easiest deployment method for Jamf Pro is the installer in [`jamf/PSSO-Shared-User-Login-Fix.sh`](jamf/PSSO-Shared-User-Login-Fix.sh).

Recommended Jamf policy configuration:

- Script: `PSSO Shared User Login Fix`
- Trigger: **Recurring Check-in**
- Execution Frequency: **Once per computer**
- Scope: test Macs first; expand only after validation

Jamf runs scripts as root. The installer creates:

```text
/usr/local/bin/psso-login-agent-reset.sh
/Library/Rian/PSSO/psso-logout-watcher.sh
/Library/LaunchDaemons/com.rian.psso-logout-watcher.plist
/Library/Rian/PSSO/psso-reset.log
```

The LaunchDaemon executes a very small state watcher every 2 seconds. The reset itself only occurs on a detected real-user -> login-window transition.

## Verify installation

Check the LaunchDaemon:

```bash
sudo launchctl print system/com.rian.psso-logout-watcher
```

A short-lived interval job can normally show `state = not running` or `state = spawn scheduled` between executions. Check `last exit code` for successful runs.

Check reset history:

```bash
sudo tail -n 20 /Library/Rian/PSSO/psso-reset.log
```

A successful automatic reset looks similar to:

```text
2026-09-16 10:20:45 | reset | terminated login AppSSOAgent PID 34643
```

The PID will differ on every system.

## Safety design

The reset helper deliberately requires all of the following before sending `TERM`:

```text
user       = _securityagent
executable = /System/Library/PrivateFrameworks/AppSSO.framework/Support/AppSSOAgent.app/Contents/MacOS/AppSSOAgent
argument   = -l
```

It then checks the PID again immediately before termination. If it no longer matches, the script aborts.

**Do not replace this with `killall AppSSOAgent`.** A broad kill would also target users' normal AppSSOAgent processes and is not what was tested.

## Troubleshooting

Before assuming you have this exact issue, verify that PSSO authentication itself succeeds and inspect the failing login for PlatformSSO / CryptoTokenKit errors. This workaround is specifically based on the repeat shared-user login failure where the login-context `AppSSOAgent`/CTK handoff becomes unhealthy across user transitions.

If the reset log says:

```text
reset | no login AppSSOAgent found
```

no matching login-context process existed at that moment, so the helper made no change.

If it says:

```text
SAFETY ABORT
```

the PID changed or stopped matching before termination; the helper intentionally made no change.

## Removal

Use [`uninstall.sh`](uninstall.sh) to unload the LaunchDaemon and remove only the files installed by this workaround.

## Why this repository exists

The goal is to give Mac administrators a **temporary, narrowly scoped recovery mechanism** while the underlying PSSO/macOS component behavior is investigated or corrected by the platform vendors.

The evidence currently supports the practical recovery mechanism described here. It does **not** establish with certainty which vendor component contains the ultimate root-cause bug. Please avoid presenting this project as proof that Microsoft, Apple, Jamf, Entra ID, Conditional Access, or a user's password is definitively at fault.

## Official references

- Microsoft: Platform SSO shared/multi-user Mac configuration
- Microsoft: Platform SSO troubleshooting / known issues

See the Microsoft Entra documentation for current supported configuration and vendor guidance.

## Privacy

This public repository intentionally contains **no tenant names, user names, email addresses, device names, registration tokens, customer logs, or other organization-specific diagnostic material**.

## License / support

Use at your own risk. Validate on non-production Macs first. This is a community workaround and carries no Microsoft, Apple, Jamf, or OpenAI support commitment.
