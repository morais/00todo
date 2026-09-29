import SwiftUI

struct SettingsView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var errorText: String?
    @State private var confirmSignOut = false
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple account") {
                    LabeledContent("Signed in as", value: store.accountEmail ?? "Apple account")
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
                Section {
                    TextField("https://api.00todo.com", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save server") {
                        do {
                            try store.configureServer(address: address)
                        } catch { errorText = error.localizedDescription }
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Changing servers signs you out and clears the local task cache.")
                }
                Section("Sync") {
                    Button("Refresh now") { Task { await store.refresh() } }
                        .disabled(!store.isConfigured || store.refreshing)
                    if let message = store.message { Text(message).foregroundStyle(.red) }
                }
                Section("Integrations") {
                    NavigationLink {
                        MCPConnectionsView()
                    } label: {
                        Label("MCP connections", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }
                Section {
                    Button("Delete account and all tasks", role: .destructive) { showDelete = true }
                } footer: {
                    Text("This permanently removes your tasks, projects, and all connected MCP sessions.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { address = store.serverAddress }
            .confirmationDialog("Sign out of 00Todo?", isPresented: $confirmSignOut) {
                Button("Sign out", role: .destructive) { Task { await store.signOut(); dismiss() } }
            }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
            .alert("Server settings", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        }
    }
}
