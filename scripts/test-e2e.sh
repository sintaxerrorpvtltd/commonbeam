#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fixture_parent=$(mktemp -d)
fixture_state="$fixture_parent/state"
fixture_port=52443
fixture_pid=''
cleanup() {
    if [ -n "$fixture_pid" ]; then kill -TERM "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; fi
    rm -rf "$fixture_parent"
}
trap cleanup EXIT INT TERM
.build/debug/CommonbeamFixtureServer "$fixture_port" "$fixture_state" > "$fixture_parent/server.log" 2>&1 &
fixture_pid=$!
attempt=0
until curl --noproxy '*' --max-time 1 -fsS "http://127.0.0.1:$fixture_port/healthz" > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 40 ] || ! kill -0 "$fixture_pid" 2>/dev/null; then
        printf '%s\n' 'Fixture server did not become ready within 10 seconds.'
        exit 1
    fi
    sleep 0.25
done
COMMONBEAM_TEST_PORT="$fixture_port" COMMONBEAM_TEST_STATE="$fixture_state" node --test Tests/e2e.test.mjs
(cd packages/CommonbeamKit && COMMONBEAM_TEST_PORT="$fixture_port" COMMONBEAM_TEST_STATE="$fixture_state" sh ../../scripts/swift-local.sh test --filter LiveTests)
