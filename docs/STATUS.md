# Status and evidence

Phase 1 developer preview, 26 October 2026.

Implemented source: native grant controls, HTTP service, protocol validation,
bounded fair scheduling, typed errors, both client SDKs, synthetic adapter and
model-free test harness. No Ollama/model installation was performed.

## Evidence at publication

- Foundation baseline: 18 Swift core tests, 5 Swift SDK fixture tests and 6 Node
  pure-fixture tests passed locally.
- Revised core and Swift SDK rechecks passed: 18 core and 5 SDK fixture tests.
  The live Swift test is intentionally skipped outside the integration harness.
- This execution sandbox denies local listeners and dependency downloads.
- CI resolved all dependencies on macOS 26.6.2 / Swift 6.3.3. The first build
  found a missing HummingbirdCore import for the connection limit. That fix and
  the resolved lockfile are committed in `bba9956`.
- [The verification rerun](https://github.com/sintaxerrorpvtltd/commonbeam/actions/runs/40357026099)
  was still waiting for a macOS runner after ten minutes when this report was
  written. Full build, four HTTP tests, seven Node socket tests, two-SDK live
  integration and app packaging are **not yet verified**. Consult that run for
  its eventual result. Phase 1 verification is incomplete until these pass.
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
