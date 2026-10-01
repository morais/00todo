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
                    Text("Changing servers signs you out. Sync pending changes first.")
                }
                Section("Sync") {
                    Button("Refresh now") { Task { await store.refresh() } }
                        .disabled(!store.isConfigured || store.refreshing)
                    if store.hasPendingChanges {
                        LabeledContent("Changes waiting to sync", value: "\(store.pendingChanges.count)")
                    }
                    if let message = store.message { Text(message).foregroundStyle(.red) }
                }
                DemoDataSettingsSection()
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
            } message: {
                if store.hasPendingChanges {
                    Text("Unsynced changes stay on this device and will resume when you sign back into this Apple account.")
                }
            }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
            .alert("00Todo", isPresented: Binding(
                get: { errorText != nil }, set: { if !$0 { errorText = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        }
    }

}

private struct DemoDataSettingsSection: View {
    @Environment(TodoStore.self) private var store
    @State private var confirmCreate = false
    @State private var confirmRemove = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        Section {
            Button("Create demo data") { confirmCreate = true }
                .disabled(busy || store.hasDemoData)
            if store.hasDemoData {
                Button("Remove demo data (\(store.demoItemCount) items)", role: .destructive) {
                    confirmRemove = true
                }
                .disabled(busy)
            }
        } header: {
            Text("Screenshots")
        } footer: {
            Text("Adds sample tasks and projects to this account for screenshots. Remove demo data deletes only those sample items.")
        }
        .confirmationDialog("Create screenshot demo data?", isPresented: $confirmCreate) {
            Button("Create demo data") { run { try await store.createDemoData() } }
        } message: {
            Text("This adds sample tasks and projects to your account. You can remove them here later.")
        }
        .confirmationDialog("Remove all demo data?", isPresented: $confirmRemove) {
            Button("Remove demo data", role: .destructive) { run { try await store.removeDemoData() } }
        } message: {
            Text("Only items created by the demo-data button are removed, including any edits you've made to them.")
        }
        .alert("Demo data", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { errorText = error.localizedDescription }
        }
    }
}
