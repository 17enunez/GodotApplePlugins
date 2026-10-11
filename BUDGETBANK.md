# BudgetBank fork of GodotApplePlugins

Branch `budgetbank`, based on upstream tag `v1.11.0`
(https://github.com/migueldeicaza/GodotApplePlugins, MIT).
Plan: `BudgetBuddy/docs/NATIVE_IOS_PLAN.md`, Phase 2.

## What's different from upstream
- `ASAuthorizationController.signin_with_scopes_and_nonce(scopes, hashed_nonce)`:
  sets `request.nonce` so the identity token carries it (Supabase checks it).
- `ASAuthorizationController` now sets `presentationContextProvider` (key window).
- New module `GodotApplePluginsBudgetBankNative` (class `BudgetBankNative`):
  `ping()`, `request_review()`, `install_keyboard_caret_hook()` +
  signal `keyboard_caret_moved(column, length)`. The caret hook also gives
  Godot's hidden keyboard view a real size (Godot makes it 0x0, so the
  space-bar trackpad can't move its caret) and, for now, logs the trackpad's
  floating-cursor calls (`BBNative float ...`) for device testing.
- `Makefile`: `SPLIT_FRAMEWORK_NAMES` defaults to the two modules BudgetBank
  ships (AuthenticationServices + BudgetBankNative).
- `Makefile`: `XCODEBUILD_SETTINGS` defaults to `-skipPackagePluginValidation
  -skipMacroValidation`; without them a Terminal build stops at "Validate
  plug-in CodeGeneratorPlugin in package swiftgodot" (2026-10-07).

## Build (Mac, Xcode 26)
    make budgetbank-package

Builds iOS, iOS Simulator and Apple-silicon macOS, then packages without the
Intel-Mac (macOS x86_64) frameworks (`MACOS_X86_64=0`). The x86_64 build fails
on an Apple-silicon Mac at "SwiftDriver SwiftGodotMacroLibrary normal arm64"
(SwiftGodot's macro plug-in builds for the arm64 host, its swift-syntax for
x86_64); running it under Rosetta as upstream's CI does didn't help with
Xcode 26 (2026-10-07). BudgetBank doesn't need it. Each target compiles
swift-syntax from scratch, so the first build is slow and needs internet.

If the targets are already built: `make split-dist MACOS_X86_64=0`.

Header padding: the frameworks must be linked with
`-headerpad_max_install_names` (Makefile `XCODEBUILD_SETTINGS` and
`relink_without_swiftsyntax.sh`, as in upstream 0f0c77f), otherwise
split-dist's `install_name_tool` can't add the runtime rpath and stops with
"make: *** [split-dist] Error 1" (2026-10-07).

## Install into BudgetBuddy
Close Godot, then copy those three folders over `BudgetBuddy/addons/` with
Finder or `ditto` (never the AssetLib tab: it flattens the framework symlinks).
Check: `file -L addons/*/bin/*.framework/*` says Mach-O.

## 2026-10-10: `.gdextension` macOS entries
`addons/GodotApplePluginsAuthenticationServices/*.gdextension` and `addons/GodotApplePluginsBudgetBankNative/*.gdextension`
list the Mac framework under plain `macos` (was `macos.arm64` + `macos.x86_64`). There is no Intel build
(`MACOS_X86_64=0`), and with the arch-specific keys a universal macOS export of BudgetBuddy bundled neither
framework, so the exported app aborted at launch (`NSBundle initWithURL` in `OS_MacOS::open_dynamic_library`).
BudgetBuddy's installed copies already have this change. Not committed yet (commit from the Mac: `git commit` and `git push fork budgetbank`).

## 2026-10-10: Plaid Link (Phase 5)
- `Package.swift`: `plaid-link-ios-spm` **exact 7.2.0**, a dependency of `GodotApplePluginsBudgetBankNative` on iOS only (`condition: .when(platforms: [.iOS])`).
- `Sources/GodotBudgetBankNative/BudgetBankNative.swift`: `open_plaid_link(link_token) -> Bool`, signals `plaid_link_success(public_token, metadata)` and `plaid_link_exit(error_code, error_message, metadata)` (LinkKit 7: `LinkTokenConfiguration`, `Plaid.createPlaidLinkSession`, `session.open(using: .viewController(...))`; the session is kept until Link finishes). Everything is inside `#if os(iOS) && canImport(LinkKit)`; macOS returns false.
- LinkKit is a dynamic framework: `make budgetbank-package` copies `LinkKit.xcframework` from `.xcodebuild/SourcePackages/artifacts` into `addons/GodotApplePluginsBudgetBankNative/bin/`, and the module's `.gdextension` lists it under `[dependencies] ios`, so Godot embeds it in the app (not embedded = crash at launch on a device).
- `relink_without_swiftsyntax.sh`: adds `-framework LinkKit` when relinking this module for iOS.
- `doc_classes/BudgetBankNative.xml`: the new method + signals (stubs are generated from it).
- Written without compiling (no Xcode where it was written). First `make budgetbank-package` checks it.
