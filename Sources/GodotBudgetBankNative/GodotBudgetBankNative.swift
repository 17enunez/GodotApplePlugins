// BudgetBank fork: registration for the BudgetBankNative module (same shape
// as GodotAuthenticationServices.swift). Ships as its own split framework that
// shares GodotApplePluginsRuntime with the other modules (one SwiftGodot runtime).
import SwiftGodotRuntime

private func makeGodotApplePluginsBudgetBankNativeTypes() -> [ExtensionInitializationLevel: [Object.Type]] {
    do {
        return try [
            BudgetBankNative.self,
        ].prepareForRegistration()
    } catch {
        fatalError("Failed to prepare BudgetBankNative registrations: \(error)")
    }
}

private let godotApplePluginsBudgetBankNativeTypes = makeGodotApplePluginsBudgetBankNativeTypes()

public let godotApplePluginsBudgetBankNativeMinimumInitializationLevel = minimumInitializationLevel(
    for: godotApplePluginsBudgetBankNativeTypes
)

public func godotApplePluginsBudgetBankNativeInitialize(level: ExtensionInitializationLevel) {
    godotApplePluginsBudgetBankNativeTypes[level]?.forEach(register)
}

public func godotApplePluginsBudgetBankNativeDeinitialize(level: ExtensionInitializationLevel) {
    godotApplePluginsBudgetBankNativeTypes[level]?.reversed().forEach(unregister)
}

@_cdecl("godot_apple_plugins_budgetbank_native_start")
public func godotApplePluginsBudgetBankNativeStart(interface: OpaquePointer?, library: OpaquePointer?, extension: OpaquePointer?) -> UInt8 {
    guard let interface, let library, let `extension` else {
        print("Error: Not all parameters were initialized.")
        return 0
    }

    initializeSwiftModule(
        interface,
        library,
        `extension`,
        initHook: godotApplePluginsBudgetBankNativeInitialize,
        deInitHook: godotApplePluginsBudgetBankNativeDeinitialize,
        minimumInitializationLevel: godotApplePluginsBudgetBankNativeMinimumInitializationLevel
    )
    return 1
}
