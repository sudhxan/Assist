#!/usr/bin/env bash
# Rebuilds and relaunches Assist. Extra args are passed to the app (e.g. --demo).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x Assist 2>/dev/null || true
sleep 0.5
if [ $# -gt 0 ]; then open build/Assist.app --args "$@"; else open build/Assist.app; fi
