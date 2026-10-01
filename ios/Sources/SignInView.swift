import AuthenticationServices
import CryptoKit
import SwiftUI

struct SignInView: View {
    @Environment(TodoStore.self) private var store
    @State private var nonce = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .accessibilityLabel("\(AppBrand.name) checked-task mark")
            Image("BrandWordmark")
                .resizable()
                .scaledToFit()
                .frame(width: 260, height: 76)
                .accessibilityLabel("\(AppBrand.name)")
            Text("A quiet place for what needs doing. Tasks stay out of the way until their start date.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn, onRequest: { request in
                nonce = Self.makeNonce()
                request.requestedScopes = [.email]
                request.nonce = Self.hash(nonce)
            }, onCompletion: { result in
                switch result {
                case .failure(let error):
                    errorText = error.localizedDescription
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let identityData = credential.identityToken,
                          let codeData = credential.authorizationCode,
                          let identityToken = String(data: identityData, encoding: .utf8),
                          let code = String(data: codeData, encoding: .utf8),
                          !nonce.isEmpty else {
                        errorText = "Apple did not return a usable sign-in. Please try again."
                        return
                    }
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            try await store.signInWithApple(identityToken: identityToken,
                                                            authorizationCode: code, rawNonce: nonce)
                        } catch { errorText = error.localizedDescription }
                    }
                }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .disabled(busy)
            if busy { ProgressView("Signing in…") }
            Text("Your Apple account keeps your tasks separate. Your email is optional and is never used as your account ID.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Could not sign in", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
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
