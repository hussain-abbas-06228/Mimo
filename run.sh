#!/bin/bash
cd "$(dirname "$0")"
[ -d build/Mimo.app ] || ./build.sh
open build/Mimo.app
