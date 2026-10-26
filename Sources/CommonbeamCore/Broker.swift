import Foundation

public struct AdapterResult: Sendable {
    public let finishReason: String
    public let usage: Usage
    public init(finishReason: String = "stop", usage: Usage = Usage()) { self.finishReason = finishReason; self.usage = usage }
}

public protocol TextAdapter: Sendable {
    func generate(_ request: GenerateRequest, emit: @escaping @Sendable (String) async throws -> Void) async throws -> AdapterResult
}

/// No listener or provider lifecycle is hidden here. The native owner composes the transport.
public actor Broker {
    private struct Job {
        let owner: String
        let request: GenerateRequest
        let continuation: AsyncThrowingStream<TextEvent, Error>.Continuation
        var task: Task<Void, Never>?
        var timer: Task<Void, Never>?
        var cancellationTimer: Task<Void, Never>?
        var terminal = false
        var outputBytes = 0
    }
    private struct Rate { var tokens = 2.0; var updated: ContinuousClock.Instant }
    private var store: GrantStore
    private let adapter: any TextAdapter
    private var profile: Profile
    private var jobs: [String: Job] = [:]
    private var queues: [String: [String]] = [:]
    private var turns: [String] = []
    private var active: String?
    private var rates: [String: Rate] = [:]
    private var terminalOwners: [String: String] = [:]
    private var terminalOrder: [String] = []
    private var paused = false
    private var quarantined = false
    private let clock = ContinuousClock()
    private let cancellationGrace: Duration

    public init(store: GrantStore, profile: Profile, adapter: any TextAdapter, cancellationGrace: Duration = .seconds(2)) {
        self.store = store; self.profile = profile; self.adapter = adapter; self.cancellationGrace = cancellationGrace
    }

    public func grants() -> [Grant] { store.grants }
    public func createGrant(label: String) throws -> (Grant, String) {
        try store.create(label: label, profiles: [profile.id: profile.revision])
    }
    public func capabilities(token: String) throws -> [Profile] {
        let grant = try store.authenticate(token)
        guard grant.scopes.contains("text.generate"), grant.profiles[profile.id] == profile.revision else { return [] }
        var current = profile
        if paused { current.state = "disabled" }
        if quarantined { current.state = "blockedByPolicy" }
        return [current]
    }
    public func revoke(_ id: String) throws {
        try store.revoke(id)
        rates.removeValue(forKey: id)
        for requestID in jobs.keys.filter({ jobs[$0]?.owner == id }) { terminate(requestID, error: BeamError("cancelled")) }
    }
    public func setPaused(_ value: Bool) {
        paused = value
        if value { for id in Array(jobs.keys) { terminate(id, error: BeamError("cancelled")) } }
    }
    public func shutdown() { setPaused(true) }
    public func isQuarantined() -> Bool { quarantined }

    public func submit(token: String, body: Data, receivedAt: ContinuousClock.Instant? = nil) throws -> AsyncThrowingStream<TextEvent, Error> {
        let grant = try store.authenticate(token)
        let request = try GenerateRequest.decode(body)
        let deadline = (receivedAt ?? clock.now).advanced(by: .milliseconds(request.deadlineMs))
        guard clock.now < deadline else { throw BeamError("deadlineExceeded") }
        guard grant.scopes.contains("text.generate"), grant.profiles[request.profile] != nil else { throw BeamError("permissionDenied") }
        guard request.profile == profile.id else { throw BeamError("unknownProfile") }
        guard request.profileRevision == profile.revision, grant.profiles[profile.id] == profile.revision else { throw BeamError("profileChanged") }
        guard !paused else { throw BeamError("serviceUnavailable") }
        guard !quarantined else { throw BeamError("backendUnavailable") }
        guard profile.state == "ready" else { throw BeamError("modelNotReady") }
        guard queues.values.reduce(0, { $0 + $1.count }) < 8, (queues[grant.id]?.count ?? 0) < 2 else { throw BeamError("queueFull") }
        try admitRate(grant.id)
        let id = UUID().uuidString
        let (stream, continuation) = AsyncThrowingStream<TextEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        continuation.onTermination = { @Sendable [weak self] _ in Task { await self?.disconnect(id) } }
        jobs[id] = Job(owner: grant.id, request: request, continuation: continuation)
        var start = TextEvent(type: "start", id: id)
        start.profile = profile.id; start.profileRevision = profile.revision
        start.execution = profile.execution; start.backend = profile.backend; start.modelDigest = profile.modelDigest
        continuation.yield(start)
        if queues[grant.id] == nil { queues[grant.id] = []; turns.append(grant.id) }
        queues[grant.id]!.append(id)
        jobs[id]?.timer = Task { [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous); await self?.expire(id) } catch {}
        }
        pump()
        return stream
    }

    public func cancel(token: String, id: String) throws -> Int {
        let grant = try store.authenticate(token)
        if let job = jobs[id], job.owner == grant.id {
            if job.terminal { return 204 }
            terminate(id, error: BeamError("cancelled")); return 202
        }
        if terminalOwners[id] == grant.id { return 204 }
        throw BeamError("unknownRequest")
    }
    private func admitRate(_ id: String) throws {
        let now = clock.now
        var rate = rates[id] ?? Rate(updated: now)
        let elapsed = rate.updated.duration(to: now).components
        rate.tokens = min(2, rate.tokens + (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) / 6)
        rate.updated = now
        guard rate.tokens >= 1 else { rates[id] = rate; throw BeamError("rateLimited") }
        rate.tokens -= 1; rates[id] = rate
    }
    private func pump() {
        guard active == nil, !paused, !quarantined else { return }
        while !turns.isEmpty {
            let owner = turns.removeFirst()
            guard var queue = queues[owner], !queue.isEmpty else { queues.removeValue(forKey: owner); continue }
            let id = queue.removeFirst()
            if queue.isEmpty { queues.removeValue(forKey: owner) } else { queues[owner] = queue; turns.append(owner) }
            guard let job = jobs[id], !job.terminal else { continue }
            active = id
            let adapter = self.adapter
            jobs[id]?.task = Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await adapter.generate(job.request) { text in
                        try await self.emit(id, text: text)
                    }
                    await self.finished(id, result: result, error: nil)
                } catch {
                    await self.finished(id, result: nil, error: error as? BeamError ?? BeamError(error is CancellationError ? "cancelled" : "backendUnavailable"))
                }
            }
            return
        }
    }
    private func emit(_ id: String, text: String) throws {
        guard var job = jobs[id], !job.terminal else { throw CancellationError() }
        // 240 KiB text leaves room for bounded event metadata beneath 256 KiB.
        guard text.utf8.count <= 16_384, job.outputBytes + text.utf8.count <= 245_760 else {
            terminate(id, error: BeamError("payloadTooLarge")); throw BeamError("payloadTooLarge")
        }
        job.outputBytes += text.utf8.count; jobs[id] = job
        var event = TextEvent(type: "delta", id: id); event.text = text
        switch job.continuation.yield(event) {
        case .enqueued: break
        case .dropped: terminate(id, error: BeamError("payloadTooLarge")); throw BeamError("payloadTooLarge")
        case .terminated: terminate(id, error: BeamError("cancelled")); throw CancellationError()
        @unknown default: throw BeamError("backendProtocolError")
        }
    }
    private func finished(_ id: String, result: AdapterResult?, error: BeamError?) {
        guard let job = jobs[id] else { return }
        if !job.terminal {
            if let error { sendTerminal(id, error: error) }
            else if let result, ["stop", "length"].contains(result.finishReason) {
                var done = TextEvent(type: "done", id: id); done.finishReason = result.finishReason; done.usage = result.usage
                finishContinuation(job.continuation, event: done)
                remember(id, owner: job.owner)
            } else { sendTerminal(id, error: BeamError("backendProtocolError")) }
        }
        job.timer?.cancel(); job.cancellationTimer?.cancel()
        jobs.removeValue(forKey: id)
        if active == id {
            active = nil
            // New work from the just-served grant takes its turn after other grants.
            if let index = turns.firstIndex(of: job.owner) { turns.remove(at: index); turns.append(job.owner) }
        }
        pump()
    }
    private func finishContinuation(_ continuation: AsyncThrowingStream<TextEvent, Error>.Continuation, event: TextEvent) {
        if case .dropped = continuation.yield(event) { continuation.finish(throwing: BeamError("payloadTooLarge")) }
        else { continuation.finish() }
    }
    private func sendTerminal(_ id: String, error: BeamError) {
        guard var job = jobs[id], !job.terminal else { return }
        job.terminal = true; job.timer?.cancel(); jobs[id] = job
        var event = TextEvent(type: error.code == "cancelled" ? "cancelled" : "error", id: id)
        var safe = BeamError(error.code, requestID: id); safe.requestID = id; event.error = safe
        finishContinuation(job.continuation, event: event)
        remember(id, owner: job.owner)
    }
    private func terminate(_ id: String, error: BeamError) {
        guard let job = jobs[id], !job.terminal else { return }
        sendTerminal(id, error: error)
        if active == id {
            job.task?.cancel()
            jobs[id]?.cancellationTimer = Task { [weak self, cancellationGrace] in
                do { try await Task.sleep(for: cancellationGrace); await self?.quarantineIfActive(id) } catch {}
            }
        } else {
            queues[job.owner]?.removeAll { $0 == id }
            if queues[job.owner]?.isEmpty == true { queues.removeValue(forKey: job.owner); turns.removeAll { $0 == job.owner } }
            jobs.removeValue(forKey: id)
        }
    }
    private func quarantineIfActive(_ id: String) {
        guard active == id else { return }
        quarantined = true
        for queuedID in jobs.keys.filter({ $0 != id }) { terminate(queuedID, error: BeamError("backendUnavailable")) }
    }
    private func expire(_ id: String) { terminate(id, error: BeamError("deadlineExceeded")) }
    private func disconnect(_ id: String) { terminate(id, error: BeamError("cancelled")) }
    private func remember(_ id: String, owner: String) {
        terminalOwners[id] = owner; terminalOrder.append(id)
        if terminalOrder.count > 256 { terminalOwners.removeValue(forKey: terminalOrder.removeFirst()) }
    }
}
