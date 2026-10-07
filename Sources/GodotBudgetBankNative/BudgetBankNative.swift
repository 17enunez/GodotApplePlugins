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
            NSLog("BBNative caret: GDTKeyboardInputView class not found")
            return false
        }
        // Path 1: the delegate callback (Godot sets the view as its own delegate).
        let didChange: @convention(block) (UITextView, UITextView) -> Void = { _, textView in
            BudgetBankNative.reportCaret(textView)
        }
        let addedDelegate = class_addMethod(
            cls,
            NSSelectorFromString("textViewDidChangeSelection:"),
            imp_implementationWithBlock(didChange),
            "v@:@"
        )
        // Path 2: override the selection setter itself, in case UIKit never
        // asks the delegate (it can cache what the delegate responds to).
        var addedSetter = false
        let setSel = NSSelectorFromString("setSelectedTextRange:")
        if let superMethod = class_getInstanceMethod(UITextView.self, setSel) {
            typealias SetRangeFn = @convention(c) (AnyObject, Selector, UITextRange?) -> Void
            let callSuper = unsafeBitCast(method_getImplementation(superMethod), to: SetRangeFn.self)
            let setter: @convention(block) (UITextView, UITextRange?) -> Void = { view, range in
                callSuper(view, setSel, range)
                BudgetBankNative.reportCaret(view)
            }
            addedSetter = class_addMethod(cls, setSel, imp_implementationWithBlock(setter), "v@:@")
        }
        // UITextView may have cached the delegate's answers when Godot set it,
        // before our method existed, so set the same delegate again.
        var refreshed = false
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let tv = findView(of: cls, in: window) {
                    let d = tv.delegate
                    tv.delegate = nil
                    tv.delegate = d
                    refreshed = true
                }
            }
        }
        NSLog("BBNative caret: delegate hook %d, setter hook %d, delegate refreshed %d",
              addedDelegate ? 1 : 0, addedSetter ? 1 : 0, refreshed ? 1 : 0)
        caretHookInstalled = addedDelegate || addedSetter
        return caretHookInstalled
    }

    /// Sends the keyboard view's caret to Godot when only the caret moved.
    @MainActor
    private static func reportCaret(_ view: UITextView) {
        // If the text changed, Godot's own observeTextChange: is handling it.
        let text = view.text ?? ""
        guard text == (view.value(forKey: "previousText") as? String ?? "") else {
            return
        }
        let range = view.selectedRange
        let ns = text as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else {
            return
        }
        // Both hooks can fire for one move; only send real changes.
        if let prev = (view.value(forKey: "previousSelectedRange") as? NSValue)?.rangeValue,
           NSEqualRanges(prev, range) {
            return
        }
        let column = ns.substring(to: range.location).unicodeScalars.count
        let length = ns.substring(with: range).unicodeScalars.count
        // Keep Godot's typing diff in step with where the caret now is.
        view.setValue(NSValue(range: range), forKey: "previousSelectedRange")
        NSLog("BBNative caret: moved to %d (+%d)", column, length)
        BudgetBankNative.caretTarget?.keyboard_caret_moved.emit(column, length)
    }

    @MainActor
    private static func findView(of cls: AnyClass, in view: UIView) -> UITextView? {
        if view.isKind(of: cls) {
            return view as? UITextView
        }
        for sub in view.subviews {
            if let found = findView(of: cls, in: sub) {
                return found
            }
        }
        return nil
    }
#endif
}
