#!/usr/bin/env bash
set -euo pipefail

# The macOS 27 virtual machine's GPU driver can deadlock WindowServer. Every client then waits on it, so a UI test
# hangs without any fault of ours. A spindump of that state shows WindowServer threads waiting on each other inside
# the paravirtual GPU driver; naming it here saves reading the spindump to tell a runner fault from a test failure.
for directory in "$@"; do
  [[ -d "$directory" ]] || continue
  while IFS= read -r -d '' report; do
    awk '
      /^Process: / { inside = $2 == "WindowServer" }
      inside && /AppleParavirtWorkQueue::addCommandLocked/ { queue = 1 }
      inside && /AppleParavirtDevice::deleteMemorylessTexture/ { texture = 1 }
      inside && /blocked by turnstile waiting for WindowServer/ { cycle = 1 }
      END { exit !(queue && texture && cycle) }
    ' "$report" || continue
    message="WindowServer deadlocked in the virtual machine's GPU driver, so the test could not proceed: $report"
    echo "::error title=Runner GPU deadlock::$message"
    echo "Runner GPU deadlock: $message" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
    exit 0
  done < <(find "$directory" -type f -name '*.txt' -print0)
done
