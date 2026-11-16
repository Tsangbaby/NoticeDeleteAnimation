# RootHide rebuild1 execution plan

## Input and repository
User upload notice-rebuild-source.zip, SHA256 6bf878ab238d09c445ec952a0ef8c64f6288a710377dbb2b157306cf194fd94b, 388282B. Original ZIP/extracted tree and per-file hashes remain local, unchanged. New branch `build/noticelist-rebuild-roothide-20261116` in authorized public `Tsangbaby/NoticeDeleteAnimation`, isolated source root; no alpha7 files merged. Source-only original import remote b763856331af62aa321cf7359952f46b9e879808. The upload's pkg/ compiled original binaries are excluded from publication and MUST NOT be substituted into the new DEB. Reconstructed PNG/plist resources retained.

## Goal / assumptions
Assess actual native build readiness, make only necessary source/build fixes, run real RootHide Theos macOS/Xcode compilation and shader/Preferences smoke checks, then independently validate downloaded actual DEB. Preserve reconstructed class names/package ID/features; distinct version `1.0.1+rebuild1`, clearly experimental, not binary-equivalence or iOS16 compatibility claim. Original controls author/maintainer Local User retained. User installs/tests; no device connection/install/respring.

## Known independent failure signals
Original Makefile omits NLNotificationDismissalSnapshot.m, unset static Metal source, snapshot header placeholder NLDustRenderer declarations, inconsistent list-hook prototype, and incomplete prefs Makefile are build risks to verify/fix. Local stubs-only syntax is NOT native compilation. A missing Apple Metal/Preferences runtime, native compiler error, unresolved own class/function, failed shader/prefs smoke, artifact/hash/signature mismatch blocks delivery. REVERIFY control-flow assumptions remain documented and require device A/B; no speculative feature rewrite solely to get green tests. Do not use original pkg binaries or enable alternate renderer to fake success.

## Verification
1. Record raw input/import manifest, source membership and actual shader bytes. Run local syntax only with explicit limitations; check source closure/contracts and privacy/credential scan before public push.
2. Native main+Prefs arm64+arm64e minimum15 under actual pinned roothide/theos, pinned Preferences link stub where Xcode SDK lacks it. Full build warnings/errors saved.
3. Compile exact embedded Metal source with actual Apple Metal compiler/runtime; check vertex/fragment and pipeline expectations, not just NSString nonempty. Missing environment does not become PASS.
4. Actual simulator UIKit/Preferences load of built prefs source and shipped Root.plist; principal, model/rows, read-only status fallback. Synthetic inputs only, not user preferences/clipboard.
5. Download terminal-success CI artifact, match GitHub digest; independently parse actual DEB ar/control/data, verify ID/version/architecture/layout/plists/RootHide dependencies/signature page hashes, own symbols/classes/shader, exclude test/stub/pkg payload and compare new binaries against original to establish genuinely recompiled.
6. Check diff/new tree/remote same-tree and clean status. New branch only, no merge/Release/forcepush. Report exact commit/run/artifacts and remaining iOS16/Metal visual/hook behavior risks. Disable other notification-animation tweak when user tests to avoid double hooking; do not change device settings here.
