#!/bin/zsh
set -eu
cd -- "${0:A:h}"
zsh build.sh
xcrun swiftc -O -module-cache-path build/module-cache \
    -framework IOKit -import-objc-header Sources/SMCPower.h build/SMCPower.o \
    Sources/PowerReading.swift Sources/PowerHistory.swift Tests/main.swift \
    -o build/PowerReadingTests
build/PowerReadingTests
