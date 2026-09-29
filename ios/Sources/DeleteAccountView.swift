import AuthenticationServices
import CryptoKit
import SwiftUI

struct DeleteAccountView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var nonce = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently removes your account, tasks, projects, and MCP connections. You can't undo it.")
                    Toggle("I understand this deletes everything", isOn: $confirmed)
                }
                Section("Confirm with Apple") {
                    SignInWithAppleButton(.continue, onRequest: { request in
                        nonce = Self.makeNonce()
                        request.requestedScopes = [.email]
                        request.nonce = Self.hash(nonce)
                    }, onCompletion: { result in
                        switch result {
                        case .failure(let error): errorText = error.localizedDescription
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                  let identity = credential.identityToken,
                                  let code = credential.authorizationCode,
                                  let identityToken = String(data: identity, encoding: .utf8),
                                  let authorizationCode = String(data: code, encoding: .utf8) else {
                                errorText = "Apple did not return a usable sign-in. Please try again."
                                return
                            }
                            busy = true
                            Task {
                                defer { busy = false }
                                do {
                                    try await store.deleteAccount(identityToken: identityToken,
                                                                  authorizationCode: authorizationCode,
                                                                  rawNonce: nonce)
                                    dismiss()
                                } catch { errorText = error.localizedDescription }
                            }
                        }
                    })
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .disabled(!confirmed || busy)
                    if busy { ProgressView("Deleting account…") }
                }
            }
            .navigationTitle("Delete account")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Could not delete account", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        }
    }

    private static func makeNonce() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
