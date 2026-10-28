# Menu-bar visibility across system transitions

## Incident evidence (2026-10-26, macOS 27.0.1)

AlDente and Codex Pulse were still assigned Visible, but their native menu-bar
items disappeared while MBAR hiding was enabled. Pausing/re-enabling hiding and
restarting MBAR did not restore them under hiding. Restarting MenuBarAgent, then
restarting MBAR and re-enabling the same categories, restored the items.

This locates a failure in the interaction with the system menu-bar host. It does
not establish the exact internal macOS renderer fault or prove that every such
fault has the same trigger.

## Confirmed code defects and repair

- HidingService deduplicated solely by allowed bundles. After a MenuBarAgent
  replacement, identical bundles could suppress a necessary new native session.
  Request identity now includes the live host PID; missing/dead hosts cannot
  receive a new assertion.
- Sleep and wake previously used the same immediate apply/refresh path. Sleep
  now suspends native submissions and invalidates in-flight AX scans and their
  eight-second watchdogs. Application refresh bursts are cancelled during sleep.
- Startup, wake, display changes and host replacement now share a coalesced
  reconciliation path. It waits 600 ms for notification bursts, then requires
  the existing bounded layout-settling gate to observe a stable host and layout.
  The layout signature includes host PID. Only the latest environment token may
  resume, including after an asynchronous AX refresh completes.
- A native callback during a transition cannot publish a settled state, report
  an obsolete failure or disable the user's enabled preference. Successful leases
  remain retained as protection until a settled replacement is active. An older
  restrictive active lease is retained if the pending request was a temporary
  reveal cancelled by sleep/reconfiguration.

Normal identical requests within a settled environment remain deduplicated.
Explicit Show All and quit still release all leases. Categories are unchanged.
No automatic process termination, system preference changes or periodic restart
loop is introduced. If layout does not settle within the bounded check, MBAR
retains its existing leases and offers Refresh to retry; menu opening waits until
reconciliation finishes.

## Verification

`HidingServiceTests` exercises the real service with an injected native-session
boundary: host replacement, unchanged requests, suspended submissions, success
and failure during transitions, cancelled temporary reveals, late callbacks,
explicit restore and missing hosts. `SystemTransitionTests` covers sleep/wake,
display notification bursts and rejection of obsolete asynchronous work.

The host-replacement and suspended-submission tests were observed failing against
the old behavior before their fixes. Retention tests also caught and corrected
an intermediate implementation that released protection too early. New transition
policy tests initially failed to compile because their type did not yet exist;
that compile failure is not presented as a semantic regression reproduction.

Run `swift test`, `swift test -c release`, and `scripts/build-app.sh` with a distinct
absolute `MBAR_APP_DIR` for a local review bundle. Native-renderer and real
sleep/wake validation must be performed with the installed, authorized build;
the injected-session tests do not emulate macOS composition or prove permanent
elimination of a private-API defect.
