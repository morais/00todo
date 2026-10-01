import SwiftUI
import UIKit

struct MCPConnectionsView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var connections: [MCPConnection] = []
    @State private var loading = true
    @State private var disconnecting: Set<String> = []
    @State private var selectedConnection: MCPConnection?
    @State private var errorText: String?

    private var endpoint: String {
        store.serverAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/mcp"
    }

    private var claudeConnectorURL: URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let escaped = endpoint.addingPercentEncoding(withAllowedCharacters: allowed),
              let name = AppBrand.name.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://claude.ai/customize/connectors?modal=add-custom-connector&connectorName=\(name)&connectorUrl=\(escaped)")
    }

    var body: some View {
        List {
            Section {
                Text("Connect an assistant through MCP. It will ask you to sign in with the same Apple account as \(AppBrand.name) and approve access. You never need to paste an API token.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                MCPGuideCode(text: endpoint, label: "MCP address")
            } header: {
                Text("MCP server address")
            } footer: {
                Text("The address is public. Access is granted only after your Apple sign-in and approval.")
            }

            Section {
                if loading && connections.isEmpty {
                    ProgressView("Loading connections…")
                } else if connections.isEmpty {
                    Text("No assistants connected yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(connections) { connection in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.clientName)
                                .lineLimit(1)
                            Text(connection.scopes.contains("todo:write") ? "Read and change tasks" : "Read tasks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(connection.lastUsedAt.map { "Last used \(Self.displayDate($0))" }
                                 ?? "Connected \(Self.displayDate(connection.connectedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if disconnecting.contains(connection.id) {
                            ProgressView()
                        } else {
                            Button("Disconnect", role: .destructive) { selectedConnection = connection }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Connected assistants")
            } footer: {
                Text("Disconnecting revokes \(AppBrand.name) access immediately. The assistant may still show the connector until you remove it there.")
            }

            Section("Claude") {
                MCPGuideStep(1, "Open Claude’s custom connectors and add \(AppBrand.name). The button below fills in the address.")
                MCPGuideStep(2, "Connect it, then sign in to \(AppBrand.name) with Apple and approve access.")
                if let claudeConnectorURL {
                    Link(destination: claudeConnectorURL) {
                        Label("Connect Claude", systemImage: "arrow.up.forward.app")
                    }
                }
                Text("Using Claude Code? Run this command, then open /mcp in Claude Code to finish sign-in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                MCPGuideCode(text: "claude mcp add --transport http 00todo \(endpoint)", label: "Claude Code command")
                Link("Claude connector instructions", destination: URL(string: "https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp")!)
            }

            Section("ChatGPT") {
                MCPGuideStep(1, "On ChatGPT web, enable Developer mode in Settings → Security and login if your account or workspace allows it.")
                MCPGuideStep(2, "Open ChatGPT Plugins, choose Add, and enter \(AppBrand.name) and the MCP address below.")
                MCPGuideStep(3, "Create the connection and complete the Apple sign-in and access approval when prompted.")
                MCPGuideCode(text: endpoint, label: "ChatGPT MCP address")
                Link("ChatGPT MCP setup instructions", destination: URL(string: "https://developers.openai.com/plugins/deploy/connect-chatgpt")!)
            }

            Section("Manus") {
                MCPGuideStep(1, "In Manus, open Settings → Integrations → Custom MCP Servers and choose Add Server.")
                MCPGuideStep(2, "Name it \(AppBrand.name) and enter this server address.")
                MCPGuideStep(3, "Test the connection and complete Apple sign-in if Manus offers the OAuth flow. \(AppBrand.name) does not provide a static API token.")
                MCPGuideCode(text: endpoint, label: "Manus MCP address")
                Link("Manus custom MCP instructions", destination: URL(string: "https://manus.im/docs/integrations/custom-mcp")!)
            }

            Section("OpenCode") {
                MCPGuideStep(1, "Run this command to add the remote server and start OAuth.")
                MCPGuideStep(2, "Approve \(AppBrand.name) access in the browser window that opens.")
                MCPGuideCode(text: "opencode mcp add 00todo --url \(endpoint) && opencode mcp auth 00todo", label: "OpenCode command")
                Link("OpenCode MCP instructions", destination: URL(string: "https://opencode.ai/docs/mcp-servers/")!)
            }

            Section("Codex") {
                MCPGuideStep(1, "In the ChatGPT desktop app, open Settings → MCP servers → Add server.")
                MCPGuideStep(2, "Name it \(AppBrand.name), choose Streamable HTTP, and enter this address. Save and restart.")
                MCPGuideStep(3, "Select Authenticate and approve access with your Apple account.")
                MCPGuideCode(text: endpoint, label: "Codex MCP address")
                Text("Or use the Codex terminal:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                MCPGuideCode(text: "codex mcp add 00todo --url \(endpoint) && codex mcp login 00todo", label: "Codex command")
                Link("Codex MCP instructions", destination: URL(string: "https://learn.chatgpt.com/docs/extend/mcp")!)
            }

            Section("Other MCP clients") {
                MCPGuideStep(1, "Add a remote MCP server using Streamable HTTP.")
                MCPGuideStep(2, "Enter the address below, then complete OAuth with Apple and approve access.")
                MCPGuideCode(text: endpoint, label: "MCP address")
                Text("The client must support remote Streamable HTTP and OAuth. Some clients require this to be set up on desktop or web first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Cursor", destination: URL(string: "https://cursor.com/docs/mcp")!)
                Link("VS Code", destination: URL(string: "https://code.visualstudio.com/docs/agent-customization/mcp-servers")!)
                Link("Gemini CLI", destination: URL(string: "https://google-gemini.github.io/gemini-cli/docs/tools/mcp-server.html")!)
                Link("Raycast", destination: URL(string: "https://manual.raycast.com/ai/model-context-protocol")!)
            }
        }
        .navigationTitle("MCP connections")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .confirmationDialog(
            "Disconnect \(selectedConnection?.clientName ?? "assistant")?",
            isPresented: Binding(
                get: { selectedConnection != nil },
                set: { if !$0 { selectedConnection = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                if let connection = selectedConnection { Task { await disconnect(connection) } }
                selectedConnection = nil
            }
            Button("Cancel", role: .cancel) { selectedConnection = nil }
        } message: {
            Text("Its access to \(AppBrand.name) will stop immediately. Reconnecting requires a new Apple sign-in approval.")
        }
        .alert("MCP connections", isPresented: Binding(
            get: { errorText != nil }, set: { if !$0 { errorText = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
    }

    private func load() async {
        guard store.isConfigured else { return }
        loading = true
        defer { loading = false }
        do { connections = try await store.fetchMCPConnections() }
        catch { errorText = error.localizedDescription }
    }

    private func disconnect(_ connection: MCPConnection) async {
        disconnecting.insert(connection.id)
        defer { disconnecting.remove(connection.id) }
        do {
            try await store.disconnectMCPConnection(connection.id)
            connections.removeAll { $0.id == connection.id }
        } catch { errorText = error.localizedDescription }
    }

    private static func displayDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso.prefix(10).description }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct MCPGuideStep: View {
    let number: Int
    let instruction: String

    init(_ number: Int, _ instruction: String) {
        self.number = number
        self.instruction = instruction
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(instruction)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct MCPGuideCode: View {
    let text: String
    let label: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = text
                copied = true
                resetTask?.cancel()
                resetTask = Task {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.borderless)
            .accessibilityLabel(copied ? "\(label) copied" : "Copy \(label)")
        }
    }
}
