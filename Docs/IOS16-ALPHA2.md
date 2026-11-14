# iOS16.0.3 alpha2 investigation

User reports alpha1 installed on RootHide iOS16.0.3 and SpringBoard resprung, with no visible effect. No device connection is available/authorized in this task. Treat root cause as unconfirmed, not as an enable-switch issue.

## Scope
- New fix branch only; leave alpha1 intact. Add Swift Settings entry and privacy-safe diagnostics.
- Record bootstrap, installed capabilities, request/list callback counts and capture/commit rejection codes. No notification text/IDs, view descriptions, snapshots or addresses in persisted diagnostics.
- Keep original removal exactly once and fail closed for unrelated/asynchronous events.
- Inspect exact iOS16 headers where possible; label absence of dynamic evidence.
- Replace assumptions that all SpringBoard notification UI must have an active UIWindowScene only with justified host-aware policy, tested separately; preserve visible window/ancestor/surface checks.
- Bounded late class-load retry, never repeatedly install hooks.

## Unconfirmed root cause / retained boundary
Exact iOS16.0.3 binaries/runtime headers and device execution evidence are unavailable. The scene gate and late loading are candidate failure causes, not the established device root cause.

Review found that successful prepare suppresses original animated, but finish can reject when source remains attached or surface becomes invalid. In those paths no custom animation is shown; replaying removal to recover native animation is unsafe. alpha2 retains that conservative boundary and exposes commit.source_attached / commit.invalid_surface rather than claiming perfect native fallback after commit rejection. Unknown asynchronous paths remain unsupported; request identity and synchronous scope are not weakened.

Review corrections applied: keep probing for the entire bounded 60-second window despite partial readiness; per-hook installation flags prevent duplicate replacement. Fixed off-main diagnostic loss through a fixed-key synchronized accumulator with at most one pending 0.5s flush. Nil request and getter ABI/exception have distinct codes. Native UI/hook runtime validation is still required beyond syntax contracts and Core tests.

## Validation / independent failures
- Native RootHide compile all production Swift/ObjC and Preferences bundle both slices; Core XCTest and source checks.
- Missing Settings entry, no diagnostic startup after respring, zero request callbacks, list with no scope, getter mismatch, capture rejection and commit rejection are separate signals.
- Verify RootHide package includes PreferenceLoader registration and bundle; minimum15/signatures and no var/jb paths.
- Real SpringBoard behavior/animation remains device-unverified; diagnostic alpha2 must not be called a proven device fix without feedback.
