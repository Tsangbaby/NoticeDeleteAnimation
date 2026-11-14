# Verification / known limitations

## Actually performed in Minis/iSH

- Verified uploaded reference duration 9.52s, 692x1280. Independent OCR and 12/24fps pixel analysis confirm fragmentation/upward movement, roughly 1.4–1.5s visible disappearance; actual fragment shape, size and physics are not recoverable with certainty. Single-item deletion observed; clear-all behavior not established.
- Researched version-labeled public runtime headers for iOS15.5 and iOS17.0.3. See SYSTEM-API.md. No private method invoked on a device.
- Installed local tree-sitter Swift grammar. `python3 Scripts/check_source.py` runs grammar checks plus metadata, injection and safety text contracts. Result is recorded separately in `LOCAL-CHECKS.txt`.
- Independent source review performed. Fixed nonzero scroll bounds coordinate origin, explicit CA child durations, source-to-window visibility/crop checks, outdated default-value test expectations. Removed unsupported collection/batch animation route; added iOS15 contentViewController fallback, group request scope, installation getter gate, and synchronous-detachment postcondition.
- No git repository was initialized; no existing code was overwritten. Delivery hash manifest and ZIP contents are verified by `Scripts/archive_source.py`.

## Not performed

- No Swift compiler, Xcode or iOS SDK exists in this shell. **No native typecheck, Theos compilation/link, Swift XCTest, UIKit XCTest or device test was executed.** Grammar checking is not equivalent.
- No DEB, codesign, RootHide package validation, CI, git commit/push/tag/release, SSH, Frida, installation or respring.
- No measured device CPU/GPU/memory/frame-time results. Bitmap budgets do not include all UIKit temporary buffers or Core Animation/GPU allocations.

## Authored tests (pending native execution)

- Swift Core XCTest: deterministic SplitMix64 vectors and plans, grid coverage/aspect/caps, drift direction/ranges, hostile numbers, admission limits, overflow, duplicate/stale lease idempotence, expiry boundary, backwards monotonic clock, invalid time, batch bounds and cancellation.
- UIKit XCTest: real UIView coordinate conversion with zero/nonzero UIScrollView bounds origin. Not a complete renderer test, not a SpringBoard integration test.

## Remaining integration risks

1. Header presence/ABI validity does not prove actual clear paths nest synchronously. Strict identity and full-visibility gates can result in no animation. No claim of every 15+ version supported is warranted until tested.
2. If animated:NO removes visually but keeps source attached until later, custom overlay is canceled after native call. The notification still follows system deletion but may disappear without the desired animation. Do not fix by hiding reused cells or weakening semantic gates.
3. Private getter/capture can fail or throw; prep returns nil. Objective-C exceptions from original deletion propagate after cleanup; this plugin does not try to repair preexisting system exceptions. Fatal OOM/Swift traps cannot be made recoverable by @catch.
4. Modern cards may use nonidentity sublayer transforms, masks, active animations or partially clipped stacks; these deliberately fall back. Axis-aligned positive source scale/translation is accepted; rotation/shear/perspective is not.
5. Native list's own corner/background/blur composition may not flatten perfectly through drawViewHierarchy. Snapshot shape/color and fragment visual tuning require a real device.
6. Full batches, clear-all, group disappearance, request wrapping, asynchronous model delivery, notification withdrawal and competing tweaks need explicit coverage testing. No UI added for settings; Enabled boolean defaults true.
7. Pending/active overlays are in-memory, list-local and noninteractive. Main-runloop 30Hz sweep cancels on bounds/visibility/window loss or deadline; cleanup cannot run during main-thread stalls. Short transient stale display is possible between checks. No content is persisted or logged.
8. Reference implementation details are not copied. At most 900 texture cells/effect and 1800 overall are an approximation; they may look coarser or cost more than the video renderer.

## Native acceptance matrix for the next authorized stage

- Compile/link arm64 and arm64e with iOS15 deployment, upstream/rootless and actual RootHide toolchain as applicable; verify package metadata and Mach-O deployment/ABI.
- Run `swift test`, add UIKit tests to an iOS XCTest host and run them; production animator smoke tests still need to be added to a host.
- Instrument only anonymous counts/hook outcomes, never notification text, to establish actual user clear → request scope → list removal → source detachment.
- Real notification single clear, collapsed/expanded groups, clear-all, app withdrawal, rapid repeated removal and multiple notification sources.
- Scroll during animation, dismiss Notification Center, lock/unlock, incoming notifications, rotation, Reduce Motion, memory warning, unsupported capability fallback.
- Verify no duplicate original card, no wrong-card effect, no content shown when parent is concealed, no overlay leftovers, notification database unchanged except native deletion; compare exact baseline with plugin disabled.

Stop at source delivery in this task; user decides the next stage.
