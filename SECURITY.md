# Security policy

This is an early developer preview, not a security-audited production runtime.
For private security reports, email **sintaxerror.pvt.ltd@gmail.com**. Include a
minimal reproduction using synthetic data. Never post grants or private prompts
in a public issue. No response-time SLA or bug-bounty program is offered.

## Boundaries

The service binds only to numeric 127.0.0.1 and uses a maintained HTTP parser.
It rejects Origin/Cookie/query-token requests, wrong or duplicate Host,
duplicate authorization, form bodies and oversized input. Public HTTP routes
cannot administer grants or download models. Limits include 32 connections,
16 KiB headers, a two-second header/body receipt budget and bounded output.

Credentials use OS-generated 256-bit secrets and keyed HMAC-SHA256 verifier
records. The native app keeps its verifier key in Keychain and writes a 0700
directory / 0600 file. A grant is an unverified user label plus a bearer secret,
not a signed-app identity. Same-user malware and administrators remain outside
the isolation boundary. Direct backend calls can bypass broker controls.

One generation runs at a time, with bounded fair queues and per-grant rate limits.
Revocation/pause cancels active and queued jobs. An adapter that ignores cancellation
for two seconds is quarantined. This is fixture-tested behavior, not proof of any
real provider's cancellation semantics. Terminal ownership is retained for 256 jobs;
older cancel requests return 404.

There is no prompt/output log file, telemetry, response cache, model installer,
automatic cloud fallback, shell execution or file indexing. HTTP framework logging
uses a no-op handler. OS diagnostics/swap and caller behavior are outside these claims.

Synthetic mode does not use an AI engine. Real Ollama locality, digest revalidation,
context overflow and blocked-egress inference are Phase 2 gates. No localhost
boolean or user checkbox should be treated as proof of offline execution.

See docs/STATUS.md for which checks have actually run. Do not treat a passing
fixture suite as an independent audit or a real offline-inference result.
