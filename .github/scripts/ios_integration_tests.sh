#!/usr/bin/env bash
# Runs example/integration_test/picker_test.dart on the iOS simulator $1, with a watchdog.
#
# flutter test sometimes never sees the app's VM service URL on iOS simulators and then waits
# forever after the build (https://github.com/flutter/flutter/issues/181771). When no test has
# started 5 minutes after the build, the attempt is stopped and retried, up to 3 attempts.
set -uo pipefail

udid=$1
grace=${GRACE:-300}

attempt() {
  local log
  log=$(mktemp)
  (flutter test integration_test/picker_test.dart -d "$udid" 2>&1 | tee "$log") &
  local pid=$! built=""
  while kill -0 "$pid" 2>/dev/null; do
    if [ -z "$built" ] && grep -q "Xcode build done" "$log"; then built=$(date +%s); fi
    # Test progress lines look like "00:05 +3: export video: ...", after "+0: loading ...".
    if [ -n "$built" ] && ! grep -E ' \+[0-9]+( -[0-9]+)?: ' "$log" | grep -vq ': loading ' &&
      [ $(($(date +%s) - built)) -gt $grace ]; then
      echo "::warning::No test started ${grace}s after the build (flutter/flutter#181771): retrying."
      pkill -f "flutter_tools.snapshot test" || true
      wait "$pid"
      xcrun simctl terminate "$udid" dev.noegnh.filmkitPickerExample 2>/dev/null || true
      return 2
    fi
    sleep 5
  done
  wait "$pid"
}

for n in 1 2 3; do
  echo "::group::Integration tests, attempt $n"
  attempt
  status=$?
  echo "::endgroup::"
  [ "$status" -ne 2 ] && exit "$status"
done
echo "::error::The integration tests never started in 3 attempts."
exit 1
