#!/bin/zsh
set -eu
cd -- "${0:A:h}"
mkdir -p build/PowerBar.app/Contents/MacOS build/module-cache
SDK_PATH="$(xcrun --show-sdk-path)"
xcrun clang -O2 -target arm64-apple-macosx13.0 -isysroot "$SDK_PATH" \
    -c Sources/SMCPower.c -o build/SMCPower.o
xcrun swiftc -O -whole-module-optimization -target arm64-apple-macosx13.0 \
    -sdk "$SDK_PATH" -module-cache-path build/module-cache \
    -import-objc-header Sources/SMCPower.h build/SMCPower.o \
    -framework AppKit -framework IOKit -framework ServiceManagement \
    Sources/PowerReading.swift Sources/PowerHistory.swift Sources/PowerGraph.swift Sources/PowerPane.swift Sources/main.swift \
    -o build/PowerBar.app/Contents/MacOS/PowerBar
cp Info.plist build/PowerBar.app/Contents/Info.plist
codesign --force --sign - build/PowerBar.app
print 'Built build/PowerBar.app'
