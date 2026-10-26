# License and dependency inventory

Original Commonbeam source and documentation: Apache-2.0; see LICENSE and NOTICE.
The project name/logo remain identifiers, not a trademark license or clearance claim.

| Component | Selection | License / distribution scope |
|---|---|---|
| Hummingbird | Exact 2.28.0 | Apache-2.0 upstream; used for maintained HTTP parsing/server |
| SwiftNIO | >=2.101.0 as required by Hummingbird security fixes | Apache-2.0 root license; embedded notices remain applicable |
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

## Resolved package license files

The root license file at each locked revision was inspected on 26 October 2026.
This table includes test-only/transitive packages; it is not a claim that every
vendored C/C++ file has the same license. Embedded notices (including BoringSSL)
must be collected before distributing compiled binaries.

| Package / pinned license source | Version | Root license |
|---|---|---|
| [async-http-client](https://github.com/swift-server/async-http-client/blob/4c005f955e83f888d5616e579717a36d2dfc6301/LICENSE.txt) | 1.36.2 | Apache-2.0 |
| [hummingbird](https://github.com/hummingbird-project/hummingbird/blob/e12178302dacb8226fc78157f89078a59c75dd98/LICENSE.txt) | 2.28.0 | Apache-2.0 |
| [swift-algorithms](https://github.com/apple/swift-algorithms/blob/87e50f483c54e6efd60e885f7f5aa946cee68023/LICENSE.txt) | 1.2.1 | Apache-2.0 with Swift runtime exception |
| [swift-asn1](https://github.com/apple/swift-asn1/blob/3b6410f7dee09eb33cdd26260c5fd47fda19b0e2/LICENSE.txt) | 1.7.3 | Apache-2.0 |
| [swift-async-algorithms](https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/LICENSE.txt) | 1.1.7 | Apache-2.0 with Swift runtime exception |
| [swift-atomics](https://github.com/apple/swift-atomics/blob/0442cb5a3f98ab802acb777929fdb446bda11a34/LICENSE.txt) | 1.3.1 | Apache-2.0 with Swift runtime exception |
| [swift-certificates](https://github.com/apple/swift-certificates/blob/84f03fafeca28c19f5fc4b528df3d22ce8896bd7/LICENSE.txt) | 1.21.1 | Apache-2.0 |
| [swift-collections](https://github.com/apple/swift-collections/blob/844289ac455816e193f1dbbe014f3c4dbe429410/LICENSE.txt) | 1.7.4 | Apache-2.0 with Swift runtime exception |
| [swift-configuration](https://github.com/apple/swift-configuration/blob/4e916072eb34f3c136ae64bd2859d6072cdb1b6e/LICENSE.txt) | 1.3.0 | Apache-2.0 |
| [swift-crypto](https://github.com/apple/swift-crypto/blob/c2cbadd7263439d8015189668f96ff5b5be565ce/LICENSE.txt) | 5.0.3 | Apache-2.0 |
| [swift-distributed-tracing](https://github.com/apple/swift-distributed-tracing/blob/297b5b9c82a5631e3199ce3ec0993a3cfb0fbb84/LICENSE.txt) | 1.7.2 | Apache-2.0 |
| [swift-http-structured-headers](https://github.com/apple/swift-http-structured-headers/blob/933538faa42c432d385f02e07df0ace7c5ecfc47/LICENSE.txt) | 1.7.0 | Apache-2.0 |
| [swift-http-types](https://github.com/apple/swift-http-types/blob/bff4b6903cdc99dda49649dd52f46c11cfd3ed50/LICENSE.txt) | 1.8.0 | Apache-2.0 |
| [swift-log](https://github.com/apple/swift-log/blob/c9c6bb9d275ec0d95c3ad16391f3f045dc623104/LICENSE.txt) | 1.16.2 | Apache-2.0 |
| [swift-metrics](https://github.com/apple/swift-metrics/blob/9467f9cc3c32b4386fad1ecc4618328887ef5758/LICENSE.txt) | 2.12.0 | Apache-2.0 |
| [swift-nio](https://github.com/apple/swift-nio/blob/6db9d9abd92ad7399b8a564cafbb87d3507245fa/LICENSE.txt) | 2.104.0 | Apache-2.0 |
| [swift-nio-extras](https://github.com/apple/swift-nio-extras/blob/8e1249b29f92574e05e0d91637f239e378a9a95b/LICENSE.txt) | 1.35.2 | Apache-2.0 |
| [swift-nio-http2](https://github.com/apple/swift-nio-http2/blob/0f3e54e29c944c2e835ad52159da7d9e1c94ac69/LICENSE.txt) | 1.46.0 | Apache-2.0 |
| [swift-nio-ssl](https://github.com/apple/swift-nio-ssl/blob/322f3c2a4a21df31c84ca416bf65ee5e9059e440/LICENSE.txt) | 2.37.5 | Apache-2.0 |
| [swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services/blob/67787bb645a5e67d2edcdfbe48a216cc549222d5/LICENSE.txt) | 1.28.0 | Apache-2.0 |
| [swift-numerics](https://github.com/apple/swift-numerics/blob/0c0290ff6b24942dadb83a929ffaaa1481df04a2/LICENSE.txt) | 1.1.1 | Apache-2.0 with Swift runtime exception |
| [swift-service-context](https://github.com/apple/swift-service-context/blob/853ba3d9ce78851b9cc20108e8bd4f13f7fa546c/LICENSE.txt) | 1.5.1 | Apache-2.0 |
| [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle/blob/a18ee16b8039866fd919bdb4e8e906882d4ecc75/LICENSE.txt) | 2.13.0 | Apache-2.0 |
| [swift-system](https://github.com/apple/swift-system/blob/869129b7bf4ecc57b97d0193ad29690ca2134750/LICENSE.txt) | 1.8.1 | Apache-2.0 with Swift runtime exception |
