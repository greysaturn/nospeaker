#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/integration
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
swiftc InstrumentEngine.swift tests/main.swift -o build/instrument-tests
./build/instrument-tests
# Compile the real callback and renderer with a hardware-free integration entry point.
sed '/^\/\/ MARK: - Main$/,$d' nospeaker.swift > build/integration/main.swift
cat tests/integration.swift >> build/integration/main.swift
swiftc build/integration/main.swift InstrumentEngine.swift -o build/integration-tests
./build/integration-tests
