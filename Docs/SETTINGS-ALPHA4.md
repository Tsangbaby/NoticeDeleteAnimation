# alpha4 Settings content candidate

## Evidence and scope

- User report: iOS 16.0.3 RootHide, other tweak panes work; alpha3 opens a title-only blank pane. Uploaded screenshot OCR finds title/back button but no Enabled, diagnostics, refresh or privacy text. Missing diagnostics alone cannot explain this: NDAMakeSettingsSpecifiers unconditionally creates five specifiers.
- Audited official roothide/preferenceloader commit 88d3795435dfb842bc70f3723fac8df976ed9c06, prefs.xm. Lines 410-452 feed the entry to real Preferences SpecifiersFromPlist. Lines 460-463 add the lazy-bundle property only with isController=true. Lines 288-300 call original lazyLoadBundle and only check bundle loading afterwards: this code does NOT itself select principalClass. Lines 325-327 fall back to PLCustomListController only if detailControllerClass is nil. Therefore alpha3 documentation's stronger assertion that this hook resolves principalClass was unsupported. Whether the system original supplies that class must be measured, not assumed.
- alpha3 also keeps its five specifiers solely in a Swift cache; it never sets the inherited Preferences model. The subclass getter being nonempty does not guarantee inherited table methods see that array.

## Minimal candidate fix

- Keep isController=true AND explicitly name NDASettingsController in detail; retain matching @objc runtime name and NSPrincipalClass. alpha2 had detail without isController, alpha3 isController without detail; alpha4 has both.
- Synchronize getter/setter with super.specifiers and seed static specifiers before super.viewDidLoad. Refresh rebuilds the same five-specifier model even with zero diagnostics.
- No changes to notification animation, hook or diagnostics writer sources.

## Regression evidence strategy

- Local grammar/metadata/safety contracts; old actual alpha3 run43573647501 package must fail the new explicit-detail registration gate.
- Native simulator smoke uses actual UIKit and runtime Preferences.framework, real SpecifiersFromPlist and original lazyLoadBundle. It records chosen class vs bundle principal, checks Swift Objective-C identity, inherited model, view load/appearance, Enabled/refresh rows, empty diagnostic domain and refresh. It separately builds alpha3 source as a negative model control in another process. This is not a RootHide/Substrate/device integration test. A missing runtime is explicitly NOT AVAILABLE, never PASS.
- Native RootHide arm64/arm64e build, Core XCTest, downloaded actual DEB metadata/registration/Mach-O/signature load-command checks remain required before delivery.

## Authorization/boundaries

Public branch fix/settings-content-alpha4 only, remote parent 4ff6ab8af383582b929a12bdf51b97f8319a5d22. No merge, Release, force-push, device access, installation or respring. Local git HTTPS fetch failed; API tree equality verified against remote alpha3, and Git Data API publishes with the exact remote parent.

A successful simulator test still does not prove the user's iOS16 RootHide pane or animation works; real device validation remains outstanding. Final CI and delivered artifact results are recorded in REPORT.
