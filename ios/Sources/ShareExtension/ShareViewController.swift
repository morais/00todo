import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private var model: ShareComposerModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareComposerModel(context: extensionContext)
        self.model = model
        let host = UIHostingController(rootView: ShareComposerView(model: model))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareComposerView: View {
    @ObservedObject var model: ShareComposerModel

    var body: some View {
        NavigationStack {
            Form {
                if model.loading {
                    ProgressView("Reading shared content…")
                } else {
                    Section("Task") {
                        TextField("What needs doing?", text: $model.title)
                            .submitLabel(.done)
                        TextEditor(text: $model.notes)
                            .frame(minHeight: 100)
                            .accessibilityLabel("Description")
                    }
                    if model.suggesting {
                        Section { ProgressView("Suggesting a title on this device…") }
                    }
                }
                if let error = model.errorText {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add to \(AppBrand.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await model.save() } }
                        .disabled(!model.canSave)
                }
            }
            .task { await model.load() }
            .onChange(of: model.title) { _, value in
                let cleaned = ShareTaskContent.cleanTitle(value)
                if cleaned != value { model.title = cleaned }
            }
        }
    }
}
