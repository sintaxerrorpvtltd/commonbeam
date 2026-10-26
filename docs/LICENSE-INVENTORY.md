# License and dependency inventory

Original Commonbeam source and documentation: Apache-2.0; see LICENSE and NOTICE.
The project name/logo remain identifiers, not a trademark license or clearance claim.

| Component | Selection | License / distribution scope |
|---|---|---|
| Hummingbird | Exact 2.28.0 | Apache-2.0 upstream; used for maintained HTTP parsing/server |
| SwiftNIO | >=2.101.0 as required by Hummingbird security fixes | Upstream license and runtime-library exception retained by dependency |
| SwiftNIO Extras | >=1.34.1 | Upstream license; typed HTTP transport |
| SwiftLog | >=1.14.0 | Upstream license; no-op logging configuration |
| Transitive Swift packages | Resolved by SwiftPM, recorded by CI | Separate upstream notices; not vendored here |
| Node SDK runtime | Node standard libraries only | No npm runtime dependencies or Node binary bundled |
| Apple frameworks | Existing platform frameworks | Foundation, SwiftUI, AppKit, Security and CryptoKit; not redistributed here |
| Ollama/model weights | None included | Exact runtime/model license review deferred to Phase 2 |
| Apple Foundation Models | Not implemented | Technical and brokering terms review pending |
| Brand/architecture assets | Project handoff assets | Project documentation assets; no third-party logos |

No third-party source or model weights are copied into this repository. Anyone
distributing compiled bundles must include the complete resolved dependency notices.
The committed Package.resolved records the full graph resolved by macOS CI.
Source dependency minima and resolution are not a completed license audit.

Official source: https://github.com/hummingbird-project/hummingbird/tree/2.28.0
