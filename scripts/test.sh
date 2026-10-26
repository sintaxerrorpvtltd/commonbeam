#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh scripts/swift-local.sh test
(cd packages/CommonbeamKit && sh ../../scripts/swift-local.sh test)
(cd packages/sdk-js && node --test test/*.test.js)
(cd examples/swift-rewriter && sh ../../scripts/swift-local.sh build)
