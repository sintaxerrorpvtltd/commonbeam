# Contributing

Start with synthetic fixture mode; no Ollama or model weights are needed.
Use Swift 6.2+, macOS 26+ on Apple silicon and Node 22+.

Run `COMMONBEAM_SOCKET_TESTS=1 sh scripts/test.sh` and `sh scripts/test-e2e.sh`.
Protocol changes must work in both SDKs. Keep fixture results separate from real
provider, offline and performance evidence.

Useful contributions include integration reports, readiness/error recovery,
accessibility, malformed-wire fixtures and cancellation tests. Discuss new adapters
or protocol changes in an issue before a large pull request. Keep inference engines
out of SDKs and preserve validation at trust boundaries.

No silent cloud fallback, background model downloads, telemetry, public admin route
or caller-controlled backend URL. Never commit credentials, private prompts, model
weights or build output. Use the issue templates; security reports follow SECURITY.md.

Contributions are licensed under Apache-2.0. Retain third-party license notices and
provenance. Tests should cover behavior and failure modes, not mirror implementation.
