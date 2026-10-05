#!/bin/bash
cd "$(dirname "$0")"
[ -d build/LiveTranslate.app ] || ./build.sh
open build/LiveTranslate.app
