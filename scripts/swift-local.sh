#!/bin/sh
set -eu
# Keep compiler caches inside the current package, never in global user folders.
mkdir -p .build/clang .build/modules .build/cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/modules"
exec swift "$@" --disable-sandbox --scratch-path .build --cache-path .build/cache
