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
  signal `keyboard_caret_moved(column, length)`.
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
