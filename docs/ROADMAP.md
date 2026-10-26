# Roadmap

## Phase 1: broker and developer contract

Native in-process administration; per-integration grants; local HTTP discovery;
strict validation; fair bounded queue; streaming, deadlines and cancellation;
Swift/Node source clients; synthetic integration harness; CI and issue templates.
Developer preview source is available for feedback. See STATUS.md for verification.

## Phase 2: real text inference

Ollama is the intended first optional backend. It remains separately installed
and user-owned. Commonbeam must never install it automatically or alter its settings.
A ready adapter must verify installed approved digests and supported local-only
configuration, recheck mutable names, reject uncertain/cloud execution, bound output,
detect context overflow without silent truncation and prove cancellation.

Contribution evidence should record exact Ollama/model versions, provenance,
licenses, both callers using the same digest, and inference under controlled blocked
egress. A stub server cannot supply this evidence. Models are never bundled in PRs.

## Later, driven by actual integrations

Signed/notarized app distribution; separately signed sandbox clients; quality and
hardware matrices; developer setup studies. Apple requires both runtime and terms
review. Managed MLX, model downloads, speech and browser integration are deferred.
No cloud fallback, arbitrary plugins, autonomous tools or multi-user/LAN service.
