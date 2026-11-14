# Private interface evidence and adapter contract

## Sources actually read

These are public third-party runtime-header dumps, not Apple SDK APIs. Repository labels are version evidence only, not device execution proof.

### iOS 15.5 (repository label)

Base URL: https://raw.githubusercontent.com/lechium/iPhone_OS_15.5/master/System/Library/PrivateFrameworks/UserNotificationsUIKit/

- [NCNotificationListView.h](https://raw.githubusercontent.com/lechium/iPhone_OS_15.5/master/System/Library/PrivateFrameworks/UserNotificationsUIKit/NCNotificationListView.h): inherits UIScrollView; `_visibleViewAtIndex:` and `removeViewAtIndex:animated:`; no three-argument removal found.
- [NCNotificationGroupList.h](https://raw.githubusercontent.com/lechium/iPhone_OS_15.5/master/System/Library/PrivateFrameworks/UserNotificationsUIKit/NCNotificationGroupList.h): `removeNotificationRequest:`, `_currentCellForNotificationRequest:`.
- [NCNotificationListCell.h](https://raw.githubusercontent.com/lechium/iPhone_OS_15.5/master/System/Library/PrivateFrameworks/UserNotificationsUIKit/NCNotificationListCell.h): inherits UIView; `contentViewController`.
- [NCNotificationViewController.h](https://raw.githubusercontent.com/lechium/iPhone_OS_15.5/master/System/Library/PrivateFrameworks/UserNotificationsUIKit/NCNotificationViewController.h): `notificationRequest`.
- [NCNotificationStructuredListViewController.h](https://raw.githubusercontent.com/lechium/iPhone_OS_15.5/master/System/Library/PrivateFrameworks/UserNotificationsUIKit/NCNotificationStructuredListViewController.h): `removeNotificationRequest:`.

### iOS 17.0.3 (repository README label)

[Version README](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/README.md).

- [NCNotificationListView.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/main/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationListView.h): inherits UIScrollView; both `removeViewAtIndex:animated:` and `removeViewAtIndex:animated:isHorizontallyDisplaced:`; `_visibleViewAtIndex:`.
- [NCNotificationListCell.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/main/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationListCell.h): `notificationViewController`, `contentViewController`.
- [NCNotificationStructuredListViewController.h](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/main/PrivateFrameworks/UserNotificationsUIKit.framework/NCNotificationStructuredListViewController.h): `removeNotificationRequest:`.

The old `nst/iOS-Runtime-Headers` collection-view declaration has no established iOS15+ provenance here. Its collection deletion adapter was removed after review: batch-return is not a proven visual commit boundary, and disabling animation on a partially captured batch would break per-item native fallback.

## Adapter behavior

1. Install only in SpringBoard, on main queue, after exact return/argument-count/type checks; inspect each type without frame offsets. `NSUInteger` and `BOOL` use compiler `@encode`, not guessed complete encodings.
2. `NCNotificationGroupList` and/or `NCNotificationStructuredListViewController.removeNotificationRequest:` establish a synchronous request scope. Nested same-request scopes share dedupe. No global timeout correlation.
3. Hook exactly one list removal variant: prefer three arguments when present; otherwise two arguments. Require `_visibleViewAtIndex:` getter at installation.
4. Get the existing visible cell by index. Get its notification controller via supported getter and require **pointer-identical** request. Snapshot only the already loaded controller view and only when it is inside the cell/list/window and fully visible without unsupported transforms/masks/animations.
5. Successful preparation changes only that native call's `animated` to NO. Index and horizontal-displacement parameters are preserved. Original runs once even on fallback; exceptions are not swallowed/replayed for system deletion.
6. Commit particle snapshot only if original returned normally AND source content has actually left that list hierarchy. Otherwise destroy the snapshot. This conservative postcondition avoids duplicating a still-visible original, but if a private implementation ignores animated:NO or retains removed content, there may be an instantaneous native removal with no custom effect; this is a documented compatibility limitation.
7. Swift never writes original cell alpha/hidden/transform; no restore-to-reused-cell hazards.

## What this does NOT prove

Headers prove declarations, not synchronous call ordering, actual user-clear coverage, model transaction completion or visual equivalence. A removal can originate from app withdrawal as well as user clear. iOS15.0 itself, other 15.x/16.x/18.x/newer releases and all jailbreak variants were not device-tested. Unsupported or asynchronous paths intentionally do not animate. No highest-OS gate is added.

## Build-option evidence

Theos `makefiles/instance/rules.mk` was read from https://raw.githubusercontent.com/theos/theos/master/makefiles/instance/rules.mk . It recognizes `INSTANCE_SWIFT_BRIDGING_HEADER`, defaults Swift language mode to 5 and generates ObjC headers. This moving branch is not a pinned toolchain nor a successful build record.
