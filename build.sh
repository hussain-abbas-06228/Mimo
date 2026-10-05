#!/bin/bash
# Builds Mimo.app from scratch.
# 1. Compiles whisper.cpp (static libs, Metal GPU) if not already built.
# 2. Compiles the Swift app and links the libs.
# 3. Assembles and ad-hoc signs build/Mimo.app.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
WCPP="$ROOT/vendor/whisper.cpp"

# --- 1. whisper.cpp ---------------------------------------------------------
if [ ! -f "$WCPP/CMakeLists.txt" ]; then
  echo "==> Fetching whisper.cpp submodule…"
  git submodule update --init --depth 1 vendor/whisper.cpp
fi
command -v cmake >/dev/null || { echo "cmake is required: brew install cmake"; exit 1; }

if [ ! -f "$WCPP/build/src/libwhisper.a" ]; then
  echo "==> Building whisper.cpp (one-time, takes a few minutes)…"
  cmake -S "$WCPP" -B "$WCPP/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF
  cmake --build "$WCPP/build" -j8 --config Release
fi

# --- 1b. App icon -----------------------------------------------------------
if [ ! -f assets/AppIcon.icns ]; then
  echo "==> Generating app icon…"
  mkdir -p assets
  swift scripts/make-icon.swift assets/AppIcon.iconset
  iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
fi

# --- 2. Swift app -----------------------------------------------------------
echo "==> Compiling Mimo…"
mkdir -p build

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -import-objc-header src/Bridging.h \
  -I "$WCPP/include" -I "$WCPP/ggml/include" \
  src/*.swift \
  -L "$WCPP/build/src" \
  -L "$WCPP/build/ggml/src" \
  -L "$WCPP/build/ggml/src/ggml-blas" \
  -L "$WCPP/build/ggml/src/ggml-metal" \
  -lwhisper -lggml -lggml-base -lggml-cpu -lggml-blas -lggml-metal \
  -lc++ \
  -framework Accelerate -framework Metal -framework MetalKit \
  -framework ScreenCaptureKit -framework CoreMedia -framework CoreAudio \
  -o build/Mimo-bin

# --- 3. App bundle ----------------------------------------------------------
echo "==> Assembling Mimo.app…"
APP="build/Mimo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Mimo-bin "$APP/Contents/MacOS/Mimo"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>Mimo</string>
  <key>CFBundleDisplayName</key>        <string>Mimo</string>
  <key>CFBundleIdentifier</key>         <string>io.github.hussain-abbas-06228.mimo</string>
  <key>CFBundleExecutable</key>         <string>Mimo</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleVersion</key>            <string>1</string>
  <key>LSMinimumSystemVersion</key>     <string>14.0</string>
  <key>NSHighResolutionCapable</key>    <true/>
  <key>CFBundleIconFile</key>           <string>AppIcon</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Mimo listens to your Mac's audio output to translate German speech in real time.</string>
  <key>LTModelDir</key>                 <string>$ROOT/models</string>
</dict>
</plist>
PLIST

# Sign with a stable local certificate so macOS keeps the Screen & System Audio
# Recording permission across rebuilds. If that's unavailable, fall back to an
# ad-hoc signature — which changes on every build, so the old permission entry
# is cleared and the app asks again instead of failing silently.
if scripts/make-signing-cert.sh >/dev/null &&
   codesign --force -s "Mimo Local Signing" "$APP" 2>/dev/null; then
  echo "==> Signed with \"Mimo Local Signing\" (permission survives rebuilds)"
else
  codesign --force -s - "$APP"
  tccutil reset ScreenCapture io.github.hussain-abbas-06228.mimo >/dev/null 2>&1 || true
  echo "==> Ad-hoc signed; macOS will ask for the recording permission again"
fi

echo "==> Done: $APP"
ls models/ggml-*.bin >/dev/null 2>&1 || echo "    No models yet — run scripts/download-model.sh first."
echo "    Launch with: open \"$APP\"   (or ./run.sh)"
