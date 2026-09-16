# Technical Notes

## Scope

These notes document the observed failure and recovery behavior behind this repository. Organization-specific logs, tenant identifiers, users, email addresses, device names, registration tokens, and credentials are intentionally excluded.

## Observed failure sequence

On affected repeat logins, the identity/password portion of Platform SSO can succeed before the login ultimately fails.

The observed sequence was approximately:

```text
PSSO password authentication succeeds
        |
        v
pending SSO tokens saved
        |
        v
AppSSOAgent / PlatformSSO inserts token for user
        |
        v
CryptoTokenKit configuration call fails
        |
        +--> NSCocoaErrorDomain Code=4099
        |    endpoint invalidated / peer may have been unloaded
        |
        +--> com.apple.PlatformSSO Code=-1001
             No driver config for user
        |
        v
expected PlatformSSO token/key cannot be instantiated
        |
        v
token verification later fails
        |
        v
login fails
```

This is why changing the user's password, Conditional Access policy, or Microsoft Entra authentication configuration may not address this particular failure: authentication itself can already have completed successfully.

## Process isolation

The process that proved useful to reset was the login-context Apple AppSSOAgent:

```text
_securityagent      ... /System/Library/PrivateFrameworks/AppSSO.framework/Support/AppSSOAgent.app/Contents/MacOS/AppSSOAgent -l
```

A normal signed-in user also has a separate AppSSOAgent without the `-l` argument, for example:

```text
someuser            ... /System/Library/PrivateFrameworks/AppSSO.framework/Support/AppSSOAgent.app/Contents/MacOS/AppSSOAgent
```

The workaround must not broadly terminate both processes.

## Recovery observation

Terminating only the `_securityagent` login-context `AppSSOAgent -l` after logout repeatedly allowed the next PSSO user to sign in successfully.

A fresh login-context AppSSOAgent is demand-started by macOS when required for the next login.

The workaround therefore performs the reset only after the console transitions to the login window and verifies that it remains there after a short delay.

## Things that were not required for this recovery

The successful workaround did not require:

- rebooting the Mac for each handoff
- disabling SIP
- deleting Platform SSO state
- deleting keychain entries
- deleting CryptoTokenKit state
- unregistering PSSO
- removing Microsoft Company Portal
- disabling Microsoft Entra authentication
- killing every AppSSOAgent process

## Interpretation

The repeated recovery strongly suggests stale or unhealthy login-context Platform SSO / CryptoTokenKit state associated with the system login AppSSOAgent across shared-user transitions.

That statement is intentionally narrower than claiming a definitive vendor root cause. Only Apple/Microsoft with their internal implementation details and telemetry can conclusively identify the underlying defect.

## Testing recommendation

Before deployment, reproduce the original failure on a test Mac and verify that it matches the same general pattern. Then deploy the workaround and test multiple sequences, for example:

```text
User A -> logout -> User B
User B -> logout -> User C
User C -> logout -> User A
User A -> logout -> User A
```

Also leave a user signed in for a period and confirm that the `_securityagent AppSSOAgent -l` PID remains unchanged. This verifies that the watcher is not periodically resetting the login agent during an active desktop session.

## Temporary workaround

Treat this repository as a temporary operational mitigation. Continue testing vendor updates and remove the workaround when the affected shared-user login lifecycle is corrected upstream.
