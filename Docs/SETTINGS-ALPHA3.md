# alpha3: Settings registration

User confirmed alpha2 installed on RootHide iOS16.0.3; other tweaks' Settings entries visible, this entry absent. Do not repeat version/respring questions.

Official roothide/preferenceloader branch roothide, prefs.xm: specifier generation reads entry.isController. true selects PLCustomListController and hooks lazy bundle loading; false selects plist/PSListController route. pl_lazyLoadBundleCore loads the bundle and resolves principalClass. alpha2 incorrectly omitted isController and supplied an as-yet-unloaded NDASettingsController detail class.

Fix only registration: isController=true, omit detail; preserve bundle/principalClass and existing Swift UI. No new animation/ABI changes. This is a source-proven registration defect, not proof that it alone explains this device's absent entry. Existing alpha2 package validation checked only detail/principalClass equality and missed loader semantics; replace with isController true + detail absent checks in source and actual DEB validators.

Verification: run source checks, full native RootHide build, Core tests, old alpha2 actual package must fail new validator; alpha3 must pass same validator. Verify downloaded artifact/hash/signatures. Device Settings appearance and animation remain unverified until user installs. No device access, main merge or Release.
