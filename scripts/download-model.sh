#!/bin/bash
# Downloads Whisper ggml models into ./models.
# Usage: scripts/download-model.sh [model ...]
# With no arguments it fetches the two models the app uses by default:
#   medium-q5_0          (~540 MB) — German → English translation (EN mode)
#   large-v3-turbo-q5_0  (~550 MB) — German transcription (DE mode)
# Any other name from https://huggingface.co/ggerganov/whisper.cpp works too,
# e.g. "small" for a lighter, faster model.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -gt 0 ] || set -- medium-q5_0 large-v3-turbo-q5_0
mkdir -p models
for MODEL in "$@"; do
  echo "Downloading ggml-$MODEL.bin…"
  curl -fL -C - -o "models/ggml-$MODEL.bin" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin"
done
echo "Done. Models are in ./models"
