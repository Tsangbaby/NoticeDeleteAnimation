# NoticeDeleteAnimation implementation plan

## Scope / assumptions
- User-authorized source implementation only. Name `NoticeDeleteAnimation`; package `com.tsangbaby.noticedeleteanimation`; Author/Maintainer `Tsangbaby`.
- Swift owns effect generation, rendering, resource limits and lifetime. A small Objective-C runtime bridge may validate private selectors/ABIs, preserve original IMPs and contain Objective-C exceptions.
- Deployment iOS 15.0; no maximum-OS version gate. Compatibility is capability-based, not a claim of tested support on all future versions.
- Reference: `/var/minis/attachments/uploads/video_2D96A269.mp4`. Visual characterization is being independently checked before choosing final motion parameters.
- No original-product binaries/code/assets copied. No device access, installation, respring, git commit/push, cloud build or release in this task.

## Success criteria
1. Complete Theos source project with correct metadata and a Swift-driven system notification deletion effect.
2. Only confirmed removal contexts may trigger; original system operation runs exactly once, with no deletion delay, reinsertion or altered request model.
3. Missing runtime capability / snapshot failure / Reduce Motion / resource exhaustion falls back to original system behavior.
4. Snapshots remain in process memory only, in the source collection's own window hierarchy; no notification text logging.
5. Bounded cells/pixels/layers/duration and cancellation paths. No restoration writes to reused system cells.
6. Pure motion/lifecycle logic has authored tests; local static/syntax/algorithm checks and independent source review run where possible.

## Independent failure signals
- Trigger on scroll, grouping or ordinary view disappearance; lost notifications, double deletion; lingering overlays; unexpected respring; temporary sensitive content after source surface disappears; invalid ABI installation; unbounded memory on clear-all.
- Passing local source checks does NOT prove native iOS compilation, hook coverage, visual match or device stability.

## Verification plan
- Research public runtime headers, retain exact URLs/versions and unverified boundaries.
- Check Swift grammar locally if tooling is available; run executable model/contract checks. Author Swift XCTest tests for future native execution; do not report them as run without Swift.
- Review metadata, injection scope, build paths and source archive hashes. No on-device validation in this authorization.
