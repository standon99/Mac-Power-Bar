#!/bin/zsh
set -eu
cd -- "${0:A:h:h}"
zsh build.sh
mkdir -p docs build/preview-source
cp scripts/render-preview.swift build/preview-source/main.swift
xcrun swiftc -O -module-cache-path build/module-cache \
    -framework AppKit -framework IOKit -import-objc-header Sources/SMCPower.h \
    build/SMCPower.o Sources/PowerReading.swift Sources/PowerHistory.swift \
    Sources/PowerGraph.swift Sources/PowerPane.swift build/preview-source/main.swift \
    -o build/RenderPreview
build/RenderPreview docs/powerbar.png
