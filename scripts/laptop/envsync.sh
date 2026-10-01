# Source from laptop shell rc: source /path/to/envsync.sh
# Optional reminder: call envcheck from git pre-push hook or zsh chpwd. Do not install hook here.
# Set ENVSYNC_HOST once per laptop, e.g. export ENVSYNC_HOST=ubuntu@server.tailnet.ts.net.
: "${ENVSYNC_HOST:?set ENVSYNC_HOST to ubuntu@<server>.<tailnet>.ts.net}"

_envsync_name() {
    if [ -n "$1" ]; then printf '%s\n' "$1"; return; fi
    root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$PWD
    basename "$root" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-'
}

_envsync_file() { printf '%s\n' "${1:-./.env}"; }

envpush() {
    name=$(_envsync_name "$1")
    file=$(_envsync_file "$2")
    ssh "$ENVSYNC_HOST" .local/bin/env-put "$name" < "$file"
}

envdiff() {
    name=$(_envsync_name "$1")
    file=$(_envsync_file "$2")
    ssh "$ENVSYNC_HOST" .local/bin/env-diff "$name" < "$file"
}

envkeys() { ssh "$ENVSYNC_HOST" .local/bin/env-keys "$(_envsync_name "$1")"; }
envlist() { ssh "$ENVSYNC_HOST" .local/bin/env-get; }

envpull() {
    name=$(_envsync_name "$1")
    file=$(_envsync_file "$2")
    dir=$(dirname "$file")
    tmp=$(umask 077 && mktemp "$dir/.envsync.XXXXXX") || return
    if ! ssh "$ENVSYNC_HOST" .local/bin/env-get "$name" > "$tmp"; then rm -f "$tmp"; return 1; fi
    if [ -e "$file" ] && ! cmp -s "$file" "$tmp"; then
        envdiff "$name" "$file"
        printf 'Replace %s? [y/N] ' "$file" >&2
        read answer || answer=
        case $answer in y|Y|yes|YES) cp -p "$file" "$file.bak" ;; *) rm -f "$tmp"; return 1 ;; esac
    fi
    mv "$tmp" "$file" && chmod 600 "$file"
}

envcheck() {
    name=$(_envsync_name "$1")
    file=$(_envsync_file "$2")
    [ -f "$file" ] || return 0
    envdiff "$name" "$file" >/dev/null 2>/dev/null ||
        printf '⚠ %s: local .env differs from VPS — run envpush or envpull\n' "$name"
}
