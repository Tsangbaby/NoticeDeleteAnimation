# Rebuild1 targeted changes and unresolved behavior

## Definite build / call-ABI fixes
- Build source closure now includes NLNotificationDismissalSnapshot.m and deterministic DustShaderSource.m. Renderer references the actual shared shader pointer. DustShader.metal bytes are unchanged.
- Use one real NLDustRenderer.h instead of a temporary duplicate class interface; list-hook declarations include the actual NSUInteger index argument.
- Remove one identical external NLExistingNotificationSnapshotActive copy, retaining the shared NLPreferences.m implementation.
- Main/prefs targets use actual installed Xcode SDK with minimum15 and explicit RootHide scheme; prefs initializes common.mk and has a pinned official Preferences linker stub search path. No stubs/ header path enters production.
- Each of the three list-hook installs checks its own original slot before writing. Missing/late clearAll can no longer reinstall remove hooks and turn original into replacement recursion.
- Runtime dispatch now distinguishes object getters from BOOL/NSInteger scalars. List installer requires exact object accessor/index/void/BOOL ABI. No bridge cast or warning suppression stands in for correct scalar calls.
- One-argument uninstall guard now expects one argument, and icon signature checks void return. Completion overloads using the unresolved K marker remain fail-closed rather than guessing a block/pointer ABI.
- Package/desktop/preferences labels explicitly identify1.0.1+rebuild1; numeric bundle build15. PackageID/author/maintainer remain as uploaded.

## Not claimed fixed by build work
- Original REVERIFY control-flow points remain reverse-engineering assumptions, not device validation. Original source/notes are preserved by import history; line numbers may shift.
- Third-party island and some lock-screen hook layouts/lifecycles were not proven from target-device method encodings. Preparation sites lacking a demonstrated beginAfterNativeRemoval transition remain a directed behavior-review item; no guessed transition was added to make tests look complete.
- Several original caches, rendering/material/layout assumptions and preference notification routing remain unverified. Source compilation and a Metal source/pipeline compiler test do not establish visual match, private SpringBoard compatibility or original-binary equivalence.
- Runtime smoke (when executed) uses synthetic classes/IMP dependency replacements to isolate installer idempotency; it is not actual Substrate or private OS hook integration.

## User testing boundary
Initial on-device test should compare the same notification-list deletion and ordinary system banner path, with NoticeDeleteAnimation or other overlapping animation tweaks disabled first. Do not use icon uninstallation or third-party island behavior as the first verification step. User installs/resprings; this task does not connect to or modify the device.
