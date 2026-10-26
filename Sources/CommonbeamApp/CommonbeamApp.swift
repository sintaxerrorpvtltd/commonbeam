import SwiftUI
import AppKit
import CommonbeamCore
import CommonbeamHTTP

private struct UnavailableAdapter: TextAdapter {
    func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult {
        throw BeamError("localExecutionUnverified")
    }
}

@MainActor
final class ControlModel: ObservableObject {
    @Published var grants: [Grant] = []
    @Published var label = ""
    @Published var secret: String?
    @Published var status = "Phase 1 developer preview · service stopped"
    @Published var paused = false
    @Published var enabled = false
    @Published var fixtureMode = false
    @Published var starting = false
    @Published var serving = false
    private var broker: Broker?
    private var serverTask: Task<Void, Never>?

    func enableStorage() async {
        guard !enabled, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let key = try GrantKeychain.loadOrCreate()
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Commonbeam-Local-Alpha")
            let store = try GrantStore(key: key, file: directory.appendingPathComponent("grants.json"))
            let profile = fixtureMode ? DevelopmentAdapter.profile : Profile(id: "local-text", revision: 2, state: "notInstalled", backend: "ollama")
            let selected: any TextAdapter = fixtureMode ? DevelopmentAdapter() : UnavailableAdapter()
            let owner = Broker(store: store, profile: profile, adapter: selected)
            broker = owner
            grants = await owner.grants(); enabled = true
            status = "Starting local service…"
            serverTask = Task { [weak self] in
                do {
                    try await CommonbeamServer.run(broker: owner, onReady: { [weak self] in
                        await self?.didStart()
                    })
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.serving = false
                    self?.status = "Service could not start. Port 52441 may be in use. Quit and retry."
                }
            }
        } catch { status = "Could not open secure grant storage. No service was started." }
    }
    private func didStart() {
        serving = true
        status = fixtureMode ? "Listening on 127.0.0.1:52441 · synthetic test mode, no AI" : "Listening on 127.0.0.1:52441 · no verified inference backend"
    }
    func create() async {
        guard let broker else { return }
        do {
            let (_, value) = try await broker.createGrant(label: label)
            secret = value; label = ""; grants = await broker.grants()
            status = "New credential shown once. It is not a verified app identity."
        } catch { status = "Could not create the grant. Check its name and storage permissions." }
    }
    func revoke(_ grant: Grant) async {
        do { try await broker?.revoke(grant.id); grants = await broker?.grants() ?? []; secret = nil; status = "Grant revoked." }
        catch { status = "Revocation could not be saved. Quit Commonbeam and check storage permissions." }
    }
    func togglePause() async { paused.toggle(); await broker?.setPaused(paused) }
    func quit() async {
        secret = nil; await broker?.shutdown(); serverTask?.cancel()
        await serverTask?.value
        NSApplication.shared.terminate(nil)
    }
}

struct ControlView: View {
    @ObservedObject var model: ControlModel
    private let ink = Color(red: 0.035, green: 0.149, blue: 0.290)
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Commonbeam").font(.title2.bold())
                    Text("Local intelligence. Shared by your apps.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Phase 1 · developer preview", systemImage: "hammer").font(.headline)
                Text("Test permissions, streaming and cancellation without installing a model. Synthetic mode returns labelled test text, not AI output.")
                Text("Ollama adapter: planned · Apple: deferred").font(.caption.bold())
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            if !model.enabled {
                Toggle("Synthetic test mode (no AI model)", isOn: $model.fixtureMode).disabled(model.starting)
                Text("Starting creates an app-specific Keychain key and private grant file, then listens only on this Mac.").font(.callout)
                Button(model.starting ? "Starting…" : "Start local service") { Task { await model.enableStorage() } }.buttonStyle(.borderedProminent).disabled(model.starting)
            } else {
                HStack {
                    Text("Integration grants").font(.headline)
                    Spacer()
                    Button(model.paused ? "Resume" : "Pause") { Task { await model.togglePause() } }
                }
                Text("Anyone holding a credential can use its grant. Names are user labels, not verified app identities.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Integration name", text: $model.label).textFieldStyle(.roundedBorder).accessibilityLabel("Integration name")
                    Button("Create") { Task { await model.create() } }.disabled(model.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let secret = model.secret {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Save this credential securely. It is shown only now.").font(.caption.bold())
                        Text(secret).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Button("I have saved it — hide") { model.secret = nil }
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                if model.grants.isEmpty { Text("No integration grants yet.").foregroundStyle(.secondary) }
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.grants) { grant in
                            HStack {
                                VStack(alignment: .leading) { Text(grant.label); Text(grant.profiles.keys.sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("Revoke", role: .destructive) { Task { await model.revoke(grant) } }.accessibilityLabel("Revoke \(grant.label)")
                            }
                        }
                    }
                }.frame(maxHeight: 160)
            }
            Divider()
            Text(model.status).font(.caption).foregroundStyle(.secondary).accessibilityLabel("Status: \(model.status)")
            HStack {
                Text("No model downloads · No cloud fallback").font(.caption)
                Spacer()
                Button("Quit") { Task { await model.quit() } }.keyboardShortcut("q")
            }
        }.padding(24).frame(width: 470).foregroundStyle(ink).background(Color(red: 1, green: 0.988, blue: 0.957)).preferredColorScheme(.light)
    }
}

@main
struct CommonbeamApp: App {
    @StateObject private var model = ControlModel()
    var body: some Scene {
        WindowGroup("Commonbeam") { ControlView(model: model) }.windowResizability(.contentSize)
        MenuBarExtra("Commonbeam", systemImage: "point.3.connected.trianglepath.dotted") { ControlView(model: model) }.menuBarExtraStyle(.window)
    }
}
