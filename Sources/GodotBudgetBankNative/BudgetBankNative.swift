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
#if os(iOS) && canImport(LinkKit)
import LinkKit   // Plaid Link SDK (iOS only; Package.swift adds it for iOS)
import WebKit    // PlaidLinkHost: find Link's web view to dismiss the keyboard
#endif

@Godot
class BudgetBankNative: RefCounted, @unchecked Sendable {
    /// The space-bar trackpad on the iOS keyboard moved the caret. Offsets are
    /// in characters (Unicode scalars, like Godot's String); length > 0 = selection.
    @Signal("column", "length")
    var keyboard_caret_moved: SignalWithArguments<Int, Int>

    /// Plaid Link connected a bank. `public_token` goes to the server
    /// (plaid-exchange-token, with the session_id from plaid-link-token).
    /// `metadata` is a text dump of Plaid's metadata, for logging only.
    @Signal("public_token", "metadata")
    var plaid_link_success: SignalWithArguments<String, String>

    /// Plaid Link closed without connecting. `error_code` is empty when the
    /// player just closed it; otherwise Plaid's code and message.
    @Signal("error_code", "error_message", "metadata")
    var plaid_link_exit: SignalWithArguments<String, String, String>

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

    /// Opens Plaid Link (LinkKit 7) over the game with a link_token from the
    /// plaid-link-token Edge Function. The result comes back as
    /// plaid_link_success / plaid_link_exit. Returns false when Link can't
    /// open (not iOS, no window to present from, or Plaid rejects the token).
    @Callable
    func open_plaid_link(link_token: String) -> Bool {
#if os(iOS) && canImport(LinkKit)
        return MainActor.assumeIsolated { self.openPlaidLink(token: link_token) }
#else
        return false
#endif
    }

#if os(iOS) && canImport(LinkKit)
    // LinkKit 7: the session must stay alive for the whole Link flow.
    nonisolated(unsafe) private static var plaidSession: PlaidLinkSession?

    @MainActor
    private func openPlaidLink(token: String) -> Bool {
        guard let presenter = BudgetBankNative.topViewController() else {
            NSLog("BBNative plaid: no view controller to present from")
            return false
        }
        let target = self
        let configuration = LinkTokenConfiguration(
            token: token,
            onSuccess: { success in
                BudgetBankNative.plaidSession = nil
                NSLog("BBNative plaid: success")
                target.plaid_link_success.emit(success.publicToken, String(describing: success.metadata))
            },
            onExit: { exit in
                BudgetBankNative.plaidSession = nil
                let code = exit.error.map { "\($0.errorCode)" } ?? ""
                let message = exit.error?.errorMessage ?? ""
                NSLog("BBNative plaid: exit %@", code)
                target.plaid_link_exit.emit(code, message, String(describing: exit.metadata))
            },
            onEvent: nil,
            onLoad: {}
        )
        do {
            let session = try Plaid.createPlaidLinkSession(configuration: configuration)
            BudgetBankNative.plaidSession = session
            // Present Link inside PlaidLinkHost so it stays inside the safe area
            // (the game is landscape: full-screen Link ran under the camera
            // cutout) and taps outside a field close the keyboard.
            session.open(using: .custom({ linkViewController in
                MainActor.assumeIsolated {
                    presenter.present(PlaidLinkHost(content: linkViewController), animated: true)
                }
            }, { _ in
                MainActor.assumeIsolated {
                    presenter.dismiss(animated: true)
                }
            }))
            return true
        } catch {
            NSLog("BBNative plaid: couldn't create the Link session: %@", "\(error)")
            return false
        }
    }

    /// The view controller on top (Godot's, or whatever it presented).
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        var vc = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
#endif

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
        // Path 3 (diagnostic): log the space-bar trackpad's own calls, so a
        // device run shows whether iOS sends drags and where they land.
        let addedFloating = addFloatingCursorLogging(to: cls)
        // UITextView may have cached the delegate's answers when Godot set it,
        // before our method existed, so set the same delegate again.
        var refreshed = false
        var sized = false
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let tv = findView(of: cls, in: window) {
                    let d = tv.delegate
                    tv.delegate = nil
                    tv.delegate = d
                    refreshed = true
                    sized = giveKeyboardViewALayout(tv)
                }
            }
        }
        NSLog("BBNative caret: delegate hook %d, setter hook %d, delegate refreshed %d, floating log %d, sized %d",
              addedDelegate ? 1 : 0, addedSetter ? 1 : 0, refreshed ? 1 : 0,
              addedFloating ? 1 : 0, sized ? 1 : 0)
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

    /// Godot creates the keyboard view with `[GDTKeyboardInputView new]`
    /// (0x0 frame, hidden) and never sizes it. The space-bar trackpad moves a
    /// floating cursor in points and asks the view which character is under
    /// it; with no width that answer never changes, so the caret never moves.
    /// A wide frame gives the text a real layout (one line per line of text,
    /// no wrapping). The view stays hidden, so nothing shows on screen.
    @MainActor
    private static func giveKeyboardViewALayout(_ tv: UITextView) -> Bool {
        tv.frame = CGRect(x: 0, y: 0, width: 10_000, height: 2_000)
        // Same size as a native iOS text field, so a drag moves the caret
        // about as far per character as it would in a normal app.
        tv.font = UIFont.systemFont(ofSize: 17)
        tv.textContainerInset = .zero
        tv.isScrollEnabled = false
        return tv.bounds.width > 0
    }

    /// Overrides UITextView's floating-cursor methods on Godot's keyboard view:
    /// each calls UITextView's own version, then logs what happened. The
    /// update also moves the caret under the trackpad point itself, because
    /// UIKit doesn't for this hidden view (seen on the iPhone 2026-10-09).
    /// Remove the logging once the caret works.
    @MainActor
    private static func addFloatingCursorLogging(to cls: AnyClass) -> Bool {
        typealias PointFn = @convention(c) (AnyObject, Selector, CGPoint) -> Void
        typealias VoidFn = @convention(c) (AnyObject, Selector) -> Void
        var added = 0

        let beginSel = NSSelectorFromString("beginFloatingCursorAtPoint:")
        if let m = class_getInstanceMethod(UITextView.self, beginSel) {
            let callSuper = unsafeBitCast(method_getImplementation(m), to: PointFn.self)
            let block: @convention(block) (UITextView, CGPoint) -> Void = { view, point in
                callSuper(view, beginSel, point)
                BudgetBankNative.lastLoggedOffset = -1
                BudgetBankNative.floatUpdates = 0
                BudgetBankNative.floatMinX = point.x
                BudgetBankNative.floatMaxX = point.x
                NSLog("BBNative float begin at (%.0f, %.0f), view %.0fx%.0f, hidden %d, selection %d+%d",
                      point.x, point.y, view.bounds.width, view.bounds.height,
                      view.isHidden ? 1 : 0, view.selectedRange.location, view.selectedRange.length)
            }
            if class_addMethod(cls, beginSel, imp_implementationWithBlock(block), "v@:{CGPoint=dd}") { added += 1 }
        }

        let updateSel = NSSelectorFromString("updateFloatingCursorAtPoint:")
        if let m = class_getInstanceMethod(UITextView.self, updateSel) {
            let callSuper = unsafeBitCast(method_getImplementation(m), to: PointFn.self)
            let block: @convention(block) (UITextView, CGPoint) -> Void = { view, point in
                callSuper(view, updateSel, point)
                BudgetBankNative.floatUpdates += 1
                BudgetBankNative.floatMinX = min(BudgetBankNative.floatMinX, point.x)
                BudgetBankNative.floatMaxX = max(BudgetBankNative.floatMaxX, point.x)
                var offset = -2
                if let pos = view.closestPosition(to: point) {
                    offset = view.offset(from: view.beginningOfDocument, to: pos)
                }
                // Updates come many times a second: log when the character
                // under the point changes, and every 15th update.
                if offset != BudgetBankNative.lastLoggedOffset || BudgetBankNative.floatUpdates % 15 == 0 {
                    BudgetBankNative.lastLoggedOffset = offset
                    NSLog("BBNative float update #%d at (%.0f, %.0f): char under point %d, selection %d+%d",
                          BudgetBankNative.floatUpdates, point.x, point.y, offset,
                          view.selectedRange.location, view.selectedRange.length)
                }
                // Fallback: UIKit doesn't move the caret of Godot's hidden
                // keyboard view during the drag, so put it under the point
                // ourselves (UTF-16 offsets, like selectedRange). reportCaret
                // sends it to Godot and skips it if nothing changed.
                let length = (view.text ?? "").utf16.count
                if offset >= 0 && offset <= length {
                    let wanted = NSRange(location: offset, length: 0)
                    if !NSEqualRanges(view.selectedRange, wanted) {
                        view.selectedRange = wanted
                    }
                    BudgetBankNative.reportCaret(view)
                }
            }
            if class_addMethod(cls, updateSel, imp_implementationWithBlock(block), "v@:{CGPoint=dd}") { added += 1 }
        }

        let endSel = NSSelectorFromString("endFloatingCursor")
        if let m = class_getInstanceMethod(UITextView.self, endSel) {
            let callSuper = unsafeBitCast(method_getImplementation(m), to: VoidFn.self)
            let block: @convention(block) (UITextView) -> Void = { view in
                callSuper(view, endSel)
                NSLog("BBNative float end, selection %d+%d, %d updates, x %.0f..%.0f",
                      view.selectedRange.location, view.selectedRange.length,
                      BudgetBankNative.floatUpdates, BudgetBankNative.floatMinX, BudgetBankNative.floatMaxX)
                // In case UIKit set the final range without the setter.
                BudgetBankNative.reportCaret(view)
            }
            if class_addMethod(cls, endSel, imp_implementationWithBlock(block), "v@:") { added += 1 }
        }
        NSLog("BBNative caret: floating cursor methods hooked %d/3", added)
        return added == 3
    }

    nonisolated(unsafe) private static var lastLoggedOffset = -1
    nonisolated(unsafe) private static var floatUpdates = 0
    nonisolated(unsafe) private static var floatMinX: CGFloat = 0
    nonisolated(unsafe) private static var floatMaxX: CGFloat = 0

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

#if os(iOS) && canImport(LinkKit)
/// Full-screen container for Plaid Link's view controller.
/// - Link's view is pinned to the safe area (left/right/top), so in landscape
///   nothing sits under the camera cutout; the white background fills the rest.
/// - A tap that doesn't land on a field, button or link closes the keyboard,
///   and dragging Link's page closes it too.
@MainActor
private final class PlaidLinkHost: UIViewController, UIGestureRecognizerDelegate {
    private let content: UIViewController

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: safe.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        content.didMove(toParent: self)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false   // the tap still reaches Link
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        for web in Self.webViews(in: view) {
            web.scrollView.keyboardDismissMode = .onDrag
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: view)
        let hit = view.hitTest(point, with: nil)
        // Native controls: leave them alone.
        if hit is UITextField || hit is UITextView || hit is UIControl {
            return
        }
        guard let web = Self.webViews(in: view).first(where: { hit?.isDescendant(of: $0) ?? false }) else {
            view.endEditing(true)
            return
        }
        // Inside Link's web page: ask the page whether the tap hit something
        // interactive; if not, blur the focused field and close the keyboard.
        let p = recognizer.location(in: web)
        let js = """
        (function(){var e=document.elementFromPoint(\(p.x),\(p.y));
        while(e){var t=e.tagName;
        if(t==='INPUT'||t==='TEXTAREA'||t==='SELECT'||t==='BUTTON'||t==='A'||t==='LABEL'||t==='IFRAME'||e.isContentEditable||e.getAttribute('role')==='button'||e.getAttribute('role')==='option'){return true;}
        e=e.parentElement;}
        if(document.activeElement){document.activeElement.blur();}
        return false;})()
        """
        web.evaluateJavaScript(js) { [weak self] result, _ in
            if (result as? Bool) != true {
                self?.view.endEditing(true)
            }
        }
    }

    private static func webViews(in root: UIView) -> [WKWebView] {
        var found: [WKWebView] = []
        var stack: [UIView] = [root]
        while let v = stack.popLast() {
            if let web = v as? WKWebView {
                found.append(web)
            } else {
                stack.append(contentsOf: v.subviews)
            }
        }
        return found
    }
}
#endif
