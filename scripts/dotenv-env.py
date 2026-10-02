#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ASSIGNMENT = re.compile(br"([A-Za-z_][A-Za-z0-9_]*)=.*")
DYNAMIC = {b"TAILSCALE_IP", b"BUTLER_ORIGIN", b"BUTLER_WEB_ORIGIN"}
DROP = {b"DOTENV_PUBLIC_KEY"}


def rewrite(source, destination, tailscale_ip, butler_origin):
    data = Path(source).read_bytes()
    if b"\0" in data or b"\r" in data:
        raise ValueError
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    names = set()
    rendered = []
    for line in lines:
        if line.startswith(b"#/"):
            continue  # dotenvx decrypt --stdout header box, not real content
        if not line.strip() or line.startswith(b"#"):
            rendered.append(line)
            continue
        match = ASSIGNMENT.fullmatch(line)
        if not match or match.group(1) in names:
            raise ValueError
        names.add(match.group(1))
        if match.group(1) not in DYNAMIC and match.group(1) not in DROP:
            rendered.append(line)
    rendered.extend((
        b"TAILSCALE_IP=" + tailscale_ip.encode("ascii"),
        b"BUTLER_ORIGIN=" + butler_origin.encode("ascii"),
        b"BUTLER_WEB_ORIGIN=" + butler_origin.encode("ascii"),
    ))
    Path(destination).write_bytes(b"\n".join(rendered) + b"\n")


def main():
    if len(sys.argv) != 6 or sys.argv[1] != "rewrite":
        return 2
    try:
        rewrite(*sys.argv[2:])
    except (OSError, UnicodeError, ValueError):
        print("Invalid decrypted dotenv output.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
