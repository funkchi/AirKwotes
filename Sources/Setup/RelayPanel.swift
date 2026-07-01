import SwiftUI
import AppKit

struct RelayPanel: View {
    @EnvironmentObject var relay: RelayManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Relay").font(.system(size: 28, weight: .semibold))
                    Text("Expose your ChatGPT subscription as a local OpenAI endpoint for tools like opencode.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                section("OpenAI / Codex") {
                    switch relay.oauthState {
                    case .signedOut:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Not signed in").font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Button {
                                    relay.signIn()
                                } label: { Label("Sign in with ChatGPT", systemImage: "person.badge.key.fill") }
                                    .buttonStyle(.borderedProminent)
                                Button {
                                    relay.useExistingLogin()
                                } label: { Label("Use existing Codex login", systemImage: "link") }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    case .signingIn:
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for browser sign-in…").font(.subheadline)
                            Spacer()
                            Button("Cancel", role: .destructive) { relay.signOut() }
                                .buttonStyle(.borderless)
                        }
                    case .signedIn(let email, let plan):
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(email).font(.subheadline.weight(.semibold))
                                if let plan { Text("Plan: \(plan)").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Sign out", role: .destructive) { relay.signOut() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    case .error(let msg):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            Spacer()
                            Button("Retry") { relay.signIn() }.buttonStyle(.bordered)
                        }
                    }
                }

                section("Google Gemini") {
                    switch relay.geminiState {
                    case .signedOut:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Not signed in").font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                Button {
                                    relay.signInGemini()
                                } label: { Label("Sign in with Google", systemImage: "person.badge.key.fill") }
                                    .buttonStyle(.borderedProminent)
                                Button {
                                    relay.useExistingGeminiLogin()
                                } label: { Label("Use existing Gemini login", systemImage: "link") }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    case .signingIn:
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for browser sign-in…").font(.subheadline)
                            Spacer()
                            Button("Cancel", role: .destructive) { relay.signOutGemini() }
                                .buttonStyle(.borderless)
                        }
                    case .signedIn(let email, _):
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(email).font(.subheadline.weight(.semibold))
                                Text("Gemini base: \(relay.geminiBaseURL)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Sign out", role: .destructive) { relay.signOutGemini() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    case .error(let msg):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            Spacer()
                            Button("Retry") { relay.signInGemini() }.buttonStyle(.bordered)
                        }
                    }
                }

                section("Server") {
                    row("Enabled", hint: "Listen on 127.0.0.1 and accept requests from your tools.") {
                        BlueToggle(isOn: Binding(get: { relay.serverOn },
                                                 set: { relay.setServerOn($0) }))
                    }
                    row("Port") {
                        TextField("8787", text: Binding(
                            get: { "\(relay.port)" },
                            set: { relay.setPort(Int($0) ?? 8787) }))
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                            .disabled(relay.serverOn)
                    }
                    row("Local base URL") { CopyableField(relay.baseURL) }
                    row("Local API key") { CopyableField(relay.localKey, mono: true) }
                }

                section("Plug into opencode") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add this to your opencode provider config:")
                            .font(.subheadline).foregroundStyle(.secondary)
                        CopyableField(snippet, mono: true, multiline: true)
                    }
                    .padding(.vertical, 4)
                }

                if let err = relay.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .onAppear { relay.ensureSecretsLoaded() }
    }

    private var snippet: String {
        """
        OPENAI_BASE_URL=\(relay.baseURL)
        OPENAI_API_KEY=\(relay.localKey)
        """
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fieldBG, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func row<Control: View>(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let hint { Text(hint).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 8)
    }
}

struct CopyableField: View {
    let value: String
    var mono: Bool = false
    var multiline: Bool = false
    @State private var copied = false

    init(_ value: String, mono: Bool = false, multiline: Bool = false) {
        self.value = value
        self.mono = mono
        self.multiline = multiline
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .lineLimit(multiline ? 4 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
        }
    }
}
