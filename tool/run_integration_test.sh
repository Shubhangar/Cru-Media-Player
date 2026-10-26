#!/usr/bin/env bash
# Runs the end-to-end player test on this desktop OS.
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)" in
  Darwin) device=macos ;;
  Linux) device=linux ;;
  *) device=windows ;;
esac
flutter test integration_test -d "$device" \
  --dart-define=FIXTURES="$PWD/integration_test/fixtures"
