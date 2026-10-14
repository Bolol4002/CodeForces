#!/usr/bin/env bash
#
# open_problems.sh - open CodeForces problems for the solutions in this repo.
#
# Walks the *.cpp solution files, turns each filename into its problem URL,
# then opens the first N problems (in chronological contest order) that have
# NOT been opened before. Already-opened problems are remembered in
# .opened_problems so reruns never reopen them.
#
# Usage:
#   ./open_problems.sh            # open the next 20 unopened problems
#   ./open_problems.sh 10         # open the next 10 unopened problems
#   ./open_problems.sh --reset    # forget all opened problems
#
# Set BROWSER to override the opener, e.g. BROWSER=firefox ./open_problems.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$REPO_DIR/.opened_problems"
COUNT=20

# Pick an opener. Under WSL, xdg-open has no Linux browser, so prefer the
# Windows Brave binary when it's available.
if [[ -n "${BROWSER:-}" ]]; then
  OPENER="$BROWSER"
elif [[ -x "/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe" ]]; then
  OPENER="/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"
elif [[ -x "/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe" ]]; then
  OPENER="/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
else
  OPENER="xdg-open"
fi

case "${1:-}" in
  --reset)
    : > "$STATE_FILE"
    echo "Reset: cleared $STATE_FILE"
    exit 0
    ;;
  "" ) ;;
  *[!0-9]*)
    echo "Usage: $(basename "$0") [COUNT] | --reset" >&2
    exit 1
    ;;
  *)
    COUNT="$1"
    ;;
esac

cd "$REPO_DIR"
touch "$STATE_FILE"

# Build the full list of problem URLs from solution filenames, in chronological
# order (ascending contest id, then problem letter).
# Filename format: <contestId><letter>[-<digits>]-<ProblemName>.cpp
#   e.g. 2266B-ThreePiles.cpp  -> https://codeforces.com/problemset/problem/2266/B
#   e.g. 102694A-CircumferenceOfATree.cpp -> https://codeforces.com/gym/102694/problem/A
all_urls="$(
  for f in *.cpp; do
    base="${f%.cpp}"
    if [[ "$base" =~ ^([0-9]+)([A-Z][0-9]?)- ]]; then
      id="${BASH_REMATCH[1]}"
      letter="${BASH_REMATCH[2]}"
      printf '%s\t%s\t' "$id" "$letter"
      if (( id >= 100000 )); then
        printf 'https://codeforces.com/gym/%s/problem/%s\n' "$id" "$letter"
      else
        printf 'https://codeforces.com/problemset/problem/%s/%s\n' "$id" "$letter"
      fi
    fi
  done | sort -k1,1n -k2,2 | cut -f3 | awk '!seen[$0]++'
)"

# Unopened = all URLs minus what's already in the state file, keeping order.
unopened="$(printf '%s\n' "$all_urls" | grep -Fxv -f <(sort -u "$STATE_FILE") || true)"

total_all="$(printf '%s\n' "$all_urls" | grep -c . || true)"
total_open="$(printf '%s\n' "$unopened" | grep -c . || true)"

if (( total_open == 0 )); then
  echo "Nothing left to open - all $total_all problems have been opened already."
  echo "Run $0 --reset to forget them."
  exit 0
fi

# Pick the next COUNT unopened problems in chronological order.
mapfile -t picked < <(printf '%s\n' "$unopened" | grep . | head -n "$COUNT")

echo "Opening ${#picked[@]} problem(s) (out of $total_open still unopened, $total_all total):"
for url in "${picked[@]}"; do
  echo "  $url"
  echo "$url" >> "$STATE_FILE"
  "$OPENER" "$url" >/dev/null 2>&1 &
  sleep 0.4
done

wait
echo "Done. Progress: $(( total_all - total_open + ${#picked[@]} ))/$total_all opened."
