//
//  ASAuthorizationController.swift
//  GodotApplePlugins
//
//  Created by Miguel de Icaza on 12/07/25.
//

import Foundation
import AuthenticationServices
import SwiftGodotRuntime
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Godot
class ASAuthorizationController: RefCounted, @unchecked Sendable {
    /// Can be either ASAuthorizationAppleIDCredential, ASPasswordCredential or nil for others
    @Signal("credential")
    var authorization_completed: SignalWithArguments<RefCounted?>
    
    @Signal("message")
    var authorization_failed: SignalWithArguments<String>

    var controller: AuthenticationServices.ASAuthorizationController?
    var proxy: Proxy?

    // BudgetBank fork: also the presentation context provider (key window), so
    // the Apple sheet always has a window to attach to.
    class Proxy: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        weak var base: ASAuthorizationController?
        
        init(_ base: ASAuthorizationController) {
            self.base = base
        }

        @MainActor
        func authorizationController(controller: AuthenticationServices.ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard let base else { return }
            
            if let appleIDCredential = authorization.credential as? AuthenticationServices.ASAuthorizationAppleIDCredential {
                let wrapped = ASAuthorizationAppleIDCredential(credential: appleIDCredential)
                base.authorization_completed.emit(wrapped)
            } else if let passwordCredential = authorization.credential as? AuthenticationServices.ASPasswordCredential {
                let wrapped = ASPasswordCredential(credential: passwordCredential)
                base.authorization_completed.emit(wrapped)
            } else {
                // Unknown credential type, might be the enterprise credential, but I dont think any games need that.
                base.authorization_completed.emit(nil)
            }
        }

        @MainActor
        func authorizationController(controller: AuthenticationServices.ASAuthorizationController, didCompleteWithError error: Error) {
            base?.authorization_failed.emit(error.localizedDescription)
        }

        @MainActor
        func presentationAnchor(for controller: AuthenticationServices.ASAuthorizationController) -> ASPresentationAnchor {
#if canImport(UIKit)
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
#else
            return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
#endif
        }
    }

    // BudgetBank fork: one place that builds and runs the Apple ID request.
    // hashedNonce (SHA-256 hex of a random value) is put on the request so the
    // identity token carries it and the server can check it; nil = no nonce.
    private func perform(scopes: [ASAuthorization.Scope], hashedNonce: String?) {
        MainActor.assumeIsolated {
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = scopes
            if let hashedNonce, !hashedNonce.isEmpty {
                request.nonce = hashedNonce
            }

            let controller = AuthenticationServices.ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller

            let proxy = Proxy(self)
            self.proxy = proxy

            controller.delegate = proxy
            controller.presentationContextProvider = proxy
            controller.performRequests()
        }
    }

    private func parseScopes(_ scopeStrings: VariantArray) -> [ASAuthorization.Scope] {
        var requestedScopes: [ASAuthorization.Scope] = []
        for vscope in scopeStrings {
            guard let scope = String(vscope) else { continue }
            if scope == "email" {
                requestedScopes.append(.email)
            } else if scope == "full_name" {
                requestedScopes.append(.fullName)
            }
        }
        return requestedScopes
    }

    // BudgetBank fork: like signin_with_scopes, plus the SHA-256 hash of a nonce.
    @Callable
    func signin_with_scopes_and_nonce(scopeStrings: VariantArray, hashedNonce: String) {
        perform(scopes: parseScopes(scopeStrings), hashedNonce: hashedNonce)
    }

    // The more specific version of it
    @Callable
    func signin_with_scopes(scopeStrings: VariantArray) {
        perform(scopes: parseScopes(scopeStrings), hashedNonce: nil)
    }

    // Just a general purpose easy-to-use version
    @Callable
    func signin() {
        perform(scopes: [.fullName, .email], hashedNonce: nil)
    }
}
