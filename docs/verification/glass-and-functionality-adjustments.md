# Glass and functionality adjustments — 2026-09-26

This change edits the application itself. It preserves the pre-existing WindowAppearance, ShortcutsHomeView, LifeOSApp and Theme edits in the working tree.

## Rendering contract

- Use `glassControl` for custom buttons and `LifeOSGlassButtonStyle` for ordinary module buttons.
- Use `raisedSurface`, `card`, `liquidGlassCard`, or the Apple Preview helpers for container surfaces. These are shared by iPhone, iPad and Mac Catalyst.
- Outer surfaces retain native glass, with a restrained inner reflection. Nested surfaces share the edge treatment with a lighter fill.
- Keep foreground labels opaque. Keep selected-state colors and progress/chart colors meaningful.
- Do not add a second card shadow over native glass. Do not reintroduce Theme.card/cardFill as container backgrounds.
- Accessibility Reduce Transparency retains an opaque fallback. Glass interaction honors Reduce Motion.
- System permission dialogs, keyboards and system sheets remain system-controlled.

Migrated legacy module/card fills, conditional selection surfaces, dark workout surfaces and 43 standard bordered/prominent buttons. The shared primary button no longer paints an opaque accent slab and colored shadow.

## Functional corrections

1. Account opening-balance migration is tracked on each persisted Account instead of a global UserDefaults flag. Restoring a different store no longer skips its migration because another store migrated previously. New accounts start with the current version; legacy stored accounts default to version zero. The migration version and reconstructed balance save together in SwiftData.
2. CountdownEngine publishes a display invalidation each second while deriving time from its absolute deadline. This also refreshes the HIIT screen, which did not use TimerDial's TimelineView.
3. Added regression coverage for independent store migrations, new-account balances, and observed countdown refreshes.

## Validation

Run `python3 scripts/check-glass-surfaces.py` to detect old card-fill bypasses.
Run `bash scripts/run-logic-tests.sh` and the LifeOS Xcode test scheme.
Use the DEBUG `-glassGallery` launch argument for the actual shared button, panels, nested controls and white/grey/content backgrounds. `-skipPermissionPrompts` suppresses the app's launch-time notification request for visual QA only; it does not grant permissions.

Passing a build or these tests does not establish feature parity with every reference app. Hardware-dependent integrations, provider-backed operations and all 87 module workflows still require their own end-to-end evidence. Visual approval must use the actual OS/device/build; static screenshots cannot certify touch/refraction behavior.
