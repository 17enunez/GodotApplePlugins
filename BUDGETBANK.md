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
    make split-package

Output: `addons/GodotApplePluginsAuthenticationServices`,
`addons/GodotApplePluginsBudgetBankNative`, `addons/GodotApplePluginsRuntime`.

## Install into BudgetBuddy
Close Godot, then copy those three folders over `BudgetBuddy/addons/` with
Finder or `ditto` (never the AssetLib tab: it flattens the framework symlinks).
Check: `file -L addons/*/bin/*.framework/*` says Mach-O.
