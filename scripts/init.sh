#!/usr/bin/env bash
# Bootstrap a fresh VPS. Runs every scripts/install/*.sh in order, then prints a summary.
# Usage: ./scripts/init.sh            # all steps
#        ./scripts/init.sh docker zsh # only steps whose name matches
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"   # re-run under bash if started via `sh`
set -uo pipefail                  # no -e: a failed step is recorded, the rest still run
cd "$(dirname "$0")/install"

selected() {                      # no args = run everything
  [ $# -eq 1 ] && return 0
  local step=$1; shift
  for want in "$@"; do [[ $step == *"$want"* ]] && return 0; done
  return 1
}

log=$(mktemp); trap 'rm -f "$log"' EXIT
results=(); failed=0

for step in [0-9][0-9]-*.sh; do
  selected "$step" "$@" || continue
  start=$SECONDS
  if bash "$step" 2>&1 | tee "$log"; then
    # ponytail: detects skips by the "skipping" line each step prints; switch to an exit code if that ever drifts.
    if grep -q 'skipping$' "$log"; then status="SKIPPED"; else status="INSTALLED"; fi
  else
    status="FAILED"; failed=$((failed + 1))
  fi
  results+=("$(printf '%-22s %-10s %4ss' "$step" "$status" $((SECONDS - start)))")
done

echo
echo "==================== Summary ===================="
if [ ${#results[@]} -eq 0 ]; then
  echo "  no steps matched: $*"; exit 1
fi
printf '  %s\n' "${results[@]}"
echo "================================================="

if [ $failed -gt 0 ]; then
  echo "$failed step(s) failed. Fix and re-run; finished steps will be skipped."
  exit 1
fi
echo "Next: copy secrets into .env, then run: docker compose up -d && ./scripts/deploy.sh"
