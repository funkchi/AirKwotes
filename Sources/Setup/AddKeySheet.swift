import SwiftUI

struct AddKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (ProviderKind, String, String?) -> Void

    @State private var kind: ProviderKind = .deepseek
    @State private var key: String = ""
    @State private var label: String = ""
    @State private var reveal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a provider").font(.title2.weight(.semibold))
            Text("Pick a provider and paste its credential when needed. Secrets are stored in your macOS Keychain.")
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("", selection: $kind) {
                        ForEach(ProviderKind.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label (optional)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("My account", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(kind.credentialLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if kind.requiresAPIKey {
                    HStack {
                        if reveal {
                            TextField(kind.credentialPlaceholder, text: $key).textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(kind.credentialPlaceholder, text: $key).textFieldStyle(.roundedBorder)
                        }
                        Button { reveal.toggle() } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye")
                        }.buttonStyle(.borderless)
                    }
                } else {
                    Text(kind.credentialPlaceholder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Theme.fieldBG, in: RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    Image(systemName: "info.circle").font(.caption).foregroundStyle(.tertiary)
                    Text(kind.summary).font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Link("Get a key", destination: URL(string: kind.keyAcquireURL)!)
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    onAdd(kind, key, label.isEmpty ? nil : label)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(kind.requiresAPIKey && key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct EditKeySheet: View {
    let config: ProviderConfig
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key: String = ""
    @State private var reveal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(config.kind.credentialLabel.lowercased()) — \(config.label)")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("New \(config.kind.credentialLabel.lowercased())").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    if reveal {
                        TextField(config.kind.credentialPlaceholder, text: $key).textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(config.kind.credentialPlaceholder, text: $key).textFieldStyle(.roundedBorder)
                    }
                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }.buttonStyle(.borderless)
                }
            }
            HStack {
                Link("Get a key", destination: URL(string: config.kind.keyAcquireURL)!)
                    .font(.caption)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(key); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 420)
    }
}
