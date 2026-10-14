#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p desktop/build
node desktop/build-codecs.mjs
swiftc -swift-version 5 -O -module-cache-path /tmp/dcmaster-swift-cache desktop/Sources/*.swift -o desktop/build/GSMaster -framework SwiftUI -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers -framework Quartz -framework AVKit -framework AVFoundation
swift -module-cache-path /tmp/dcmaster-swift-cache desktop/make-icon.swift desktop/build/AppIcon.iconset
python3 desktop/build-icon.py
python3 desktop/build-app.py
