#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
probe="$(mktemp -d "${TMPDIR:-/tmp}/token-menu-bar-runner-deadlock.XXXXXX")"
trap 'rm -rf "$probe"' EXIT
export GITHUB_STEP_SUMMARY="$probe/summary"

spindump() {
  local process="$1" frames="$2"
  printf 'Process:          %s [164]\n  Thread 0x33c\n%s\nProcess:          launchd [1]\n' "$process" "$frames"
}

deadlock='    AppleParavirtWorkQueue::addCommandLocked(AppleParavirtCommandDescriptor*, IOGPUEvent*) + 292
    AppleParavirtDevice::deleteMemorylessTexture(AppleParavirtDeleteMemorylessTextureArgs const*) + 384
    ??? (kernel.release.vmapple + 609788) (blocked by turnstile waiting for WindowServer [164] thread 0x106f9)'

expect() {
  local name="$1" annotated="$2"
  shift 2
  : > "$GITHUB_STEP_SUMMARY"
  Scripts/check-runner-deadlock.sh "$@" > "$probe/out"
  if ((annotated)); then
    grep -Fq '::error title=Runner GPU deadlock::' "$probe/out" || {
      echo "$name: expected a runner GPU deadlock annotation" >&2
      exit 1
    }
    grep -Fq 'Runner GPU deadlock' "$GITHUB_STEP_SUMMARY"
  elif [[ -s "$probe/out" || -s "$GITHUB_STEP_SUMMARY" ]]; then
    echo "$name: expected no annotation" >&2
    cat "$probe/out" >&2
    exit 1
  fi
}

mkdir -p "$probe/results/attachments" "$probe/profiles/request"
spindump WindowServer "$deadlock" > "$probe/results/attachments/spindump.txt"
expect "an XCTest spindump of the deadlock" 1 "$probe/results" "$probe/missing"

rm "$probe/results/attachments/spindump.txt"
spindump WindowServer "$deadlock" > "$probe/profiles/request/spindump.txt"
expect "a snapshot-timeout spindump of the deadlock" 1 "$probe/results" "$probe/profiles"

spindump TokenMenuBarDirect "$deadlock" > "$probe/profiles/request/spindump.txt"
expect "the same frames outside WindowServer" 0 "$probe/profiles"

spindump WindowServer "${deadlock%$'\n'*}" > "$probe/profiles/request/spindump.txt"
expect "driver frames without a blocked WindowServer thread" 0 "$probe/profiles"

expect "no evidence directories" 0 "$probe/missing"
echo "Runner deadlock detection passed"
