# Banner native regression — scope and evidence

Run on macOS/Xcode after the Preferences native smoke selects and boots an iOS simulator:

```sh
bash Scripts/test_banner_native.sh
```

The script reuses `build-evidence/simulator-choice.json`. It never downloads a runtime or boots another device. It compiles **production `src/NLBannerDust.m`** as a separate translation unit against the real Simulator SDK and UIKit/Foundation/CoreGraphics/QuartzCore/Metal, signs a uniquely identified CI app, installs/launches it only in the selected simulator, and uninstalls that app afterward. A real UIApplication/window is required for visible card geometry. Missing runtime, timeout, nonzero exit, or missing/duplicate `BANNER NATIVE PASS:` completion marker fails the script.

`main.m` dynamically creates its own synthetic NCNotificationRequest, NCNotificationShortLookView and BNContentViewController classes. It fails if real classes with those names already exist. Its MSHookMessageEx replacement only records/swaps Objective-C IMPs. NLWithdrawalEffect and renderer/dependency implementations are **test doubles**: they do not snapshot, compile Metal or draw dust. Passing this test demonstrates resolver/native-forwarding contracts, NOT Substrate integration, private SpringBoard compatibility, physical banner clicks, or real particle rendering.

Coverage: direct/wrapped/controller-owned request identity; source and card pointer binding; equal identifiers on different requests rejected without reading identifiers; malformed/scalar getters, cycles, depth bounds, ambiguous controller trees, unloaded/hidden/offscreen/fullscreen/generic views and another request's child card rejected; nil prepare preserves native animated YES and NO; arbitrary reason/userInfo objects forwarded unchanged; island/off-main bypass; prepare reentrancy; capture/native/finalize exceptions; same native exception propagation without a second original call; partial install repair and idempotency.

Production diagnostics add fixed counters `requestresolved`, `no_request`, `nohost`, `capturefail`, `clickpathunknown` and fixed `lastResolver`/`clickPath=unverified`. `clickpathunknown` counts a dismissal-hook capability declaration once per install, **not a click**. No request identifier/body is read or logged. Existing reason/hierarchy diagnostics remain unchanged in privacy scope.

Public header evidence (read-only, 2026-11-16):
- https://github.com/qingralf/iOS16-Runtime-Headers/blob/main/PrivateFrameworks/BannerKit.framework/BNContentViewController.h declares `_dismissPresentable:withReason:animated:userInfo:` and identification-based dismissal entry points.
- https://github.com/qingralf/iOS16-Runtime-Headers/blob/main/protocols/BNPresentable.h declares optional `viewController`.

These declarations do not show which method a notification's default-action click invokes. No tap hook or reason-text special case is added. The supplied 6.285 s video is not evidence of a banner tap; parent review identified notification-list deletion only.

Known engine boundary: this caller cancels a returned/registered effect when capture/finalize/native throws, but cannot reclaim an overlay allocated inside a factory that throws before returning/registering it. Engine exception safety and renderer/overlay coordinate handling belong to the parent-owned NLWithdrawalEffect/renderer work.
