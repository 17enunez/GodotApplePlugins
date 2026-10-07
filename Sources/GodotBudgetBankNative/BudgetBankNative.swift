//
//  BudgetBankNative.swift
//  BudgetBank fork of GodotApplePlugins
//
//  Native iOS features BudgetBank needs that the upstream modules don't have.
//  Godot side: res://scripts/StateManager/Native.gd (the only caller).
//

import Foundation
import SwiftGodotRuntime
#if os(iOS)
import UIKit
import StoreKit
import ObjectiveC
#endif

@Godot
class BudgetBankNative: RefCounted, @unchecked Sendable {
    /// The space-bar trackpad on the iOS keyboard moved the caret. Offsets are
    /// in characters (Unicode scalars, like Godot's String); length > 0 = selection.
    @Signal("column", "length")
    var keyboard_caret_moved: SignalWithArguments<Int, Int>

    /// Smoke test: returns "pong" when the module is loaded.
    @Callable
    func ping() -> String {
        return "pong"
    }

    /// Asks iOS to show the App Store review prompt. iOS decides whether it
    /// actually appears (at most a few times a year); nothing elsewhere.
    @Callable
    func request_review() {
#if os(iOS)
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
                return
            }
            AppStore.requestReview(in: scene)
        }
#endif
    }

    /// Godot 4.6's hidden keyboard view (GDTKeyboardInputView, a UITextView)
    /// doesn't implement textViewDidChangeSelection:, so caret moves made with
    /// the space-bar trackpad never reach the game. This adds that method to
    /// the class and forwards each move as keyboard_caret_moved on this object.
    /// Returns true if the hook is installed (safe to call more than once).
    @Callable
    func install_keyboard_caret_hook() -> Bool {
#if os(iOS)
        BudgetBankNative.caretTarget = self
        return MainActor.assumeIsolated { BudgetBankNative.installCaretHookOnce() }
#else
        return false
#endif
    }

#if os(iOS)
    nonisolated(unsafe) private static weak var caretTarget: BudgetBankNative?
    nonisolated(unsafe) private static var caretHookInstalled = false

    @MainActor
    private static func installCaretHookOnce() -> Bool {
        if caretHookInstalled {
            return true
        }
        guard let cls = NSClassFromString("GDTKeyboardInputView") else {
            return false
        }
        let block: @convention(block) (UITextView, UITextView) -> Void = { view, textView in
            // Only pure caret moves: if the text changed, Godot's own
            // observeTextChange: is handling it.
            let text = textView.text ?? ""
            guard text == (view.value(forKey: "previousText") as? String ?? "") else {
                return
            }
            let range = textView.selectedRange
            let ns = text as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else {
                return
            }
            let column = ns.substring(to: range.location).unicodeScalars.count
            let length = ns.substring(with: range).unicodeScalars.count
            // Keep Godot's typing diff in step with where the caret now is.
            view.setValue(NSValue(range: range), forKey: "previousSelectedRange")
            BudgetBankNative.caretTarget?.keyboard_caret_moved.emit(column, length)
        }
        caretHookInstalled = class_addMethod(
            cls,
            NSSelectorFromString("textViewDidChangeSelection:"),
            imp_implementationWithBlock(block),
            "v@:@"
        )
        return caretHookInstalled
    }
#endif
}
