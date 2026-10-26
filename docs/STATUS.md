# Status and evidence

Phase 1 developer preview, 26 October 2026.

Implemented source: native grant controls, HTTP service, protocol validation,
bounded fair scheduling, typed errors, both client SDKs, synthetic adapter and
model-free test harness. No Ollama/model installation was performed.

## Evidence before first publication

- Foundation baseline: 18 Swift core tests, 5 Swift SDK fixture tests and 6 Node
  pure-fixture tests passed locally.
- The revised core and Swift SDK are rechecked locally without external dependencies.
- This execution sandbox denies local listeners and dependency downloads.
- Seven Node socket tests, four HTTP tests and two-SDK integration coverage are
  included in CI. Their current outcome is visible in the repository's Actions tab;
  no passing CI badge is claimed before a successful run.
- The old foundation app compiled but its first LaunchServices attempt failed.
  The packaging script now ad-hoc signs the completed bundle and verifies its
  signature; interactive native launch, Keychain and accessibility remain unverified.

## Not established

Real Ollama compatibility, exact model locality/provenance, offline inference,
model quality, RAM/CPU/latency numbers, separately signed sandbox clients,
macOS 27, 8/16 GB hardware matrix, notarization and independent security review.
The public preview intentionally does not require these Phase 2+ proofs to let
developers examine the broker contract and report integration problems.

CI runs on macOS 26, records its toolchain, tests the live Swift HTTP service using
synthetic responses, then builds an ad-hoc developer app. It never installs Ollama,
loads a model, uploads prompts or uses signing credentials.
