#!/usr/bin/env bash
# Print configured Butler and wiki checkout directories as NUL-delimited paths.
set -euo pipefail

paths=${PERSONAL_AGENT_INFRA_PATHS:-/etc/personal-agent-infra.paths}
fail() { echo "Invalid Butler path configuration: $paths" >&2; exit 1; }

[ -f "$paths" ] && [ ! -L "$paths" ] || fail
[ "$(stat -c '%u:%g:%a' "$paths" 2>/dev/null)" = 0:0:644 ] || fail
butler= wiki= seen_butler=0 seen_wiki=0
while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    BUTLER_DIR=*) [ "$seen_butler" -eq 0 ] || fail; butler=${line#*=}; seen_butler=1 ;;
    WIKI_DIR=*) [ "$seen_wiki" -eq 0 ] || fail; wiki=${line#*=}; seen_wiki=1 ;;
    *) fail ;;
  esac
done < "$paths"
[ "$seen_butler" -eq 1 ] && [ "$seen_wiki" -eq 1 ] || fail
[[ $butler == /* && $wiki == /* && $butler != / && $wiki != / ]] || fail
butler=$(realpath -m "$butler") || fail
wiki=$(realpath -m "$wiki") || fail
printf '%s\0%s\0' "$butler" "$wiki"
