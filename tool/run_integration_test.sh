#!/usr/bin/env bash
# Runs the end-to-end tests on this desktop OS, one file per app launch
# (launching several desktop test apps back to back is flaky).
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -s)" in
  Darwin)
    device=macos
    # If the test app can't come to the front (you're using another app),
    # App Nap throttles its timers and a 20 s test can take an hour.
    defaults write dev.crumediaplayer.app.debug NSAppSleepDisabled -bool YES
    ;;
  Linux) device=linux ;;
  *) device=windows ;;
esac
status=0
for f in integration_test/*_test.dart; do
  echo "=== $f"
  flutter test "$f" -d "$device" \
    --dart-define=FIXTURES="$PWD/integration_test/fixtures" "$@" || status=1
done
exit $status
