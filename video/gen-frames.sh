#!/bin/sh
set -e
cd "$(dirname "$0")"
(cd .. && swift build -c release)
node gen-frames.mjs
