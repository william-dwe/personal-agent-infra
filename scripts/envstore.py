#!/usr/bin/env python3
import datetime
import fcntl
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

MAX_BYTES = 1024 * 1024
NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ASSIGNMENT = re.compile(r"(?:(export) )?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")

def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)

def store_dir():
    path = Path(os.environ.get("ENVSTORE_DIR", "~/secrets")).expanduser()
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path, 0o700)
    return path

def valid_name(name):
    if not NAME.fullmatch(name):
        fail("invalid name", 2)

def target_for(name, directory):
    if name == "infra":
        return Path(os.environ.get("ENVSTORE_INFRA", "/home/ubuntu/services/personal-agent-infra/.env"))
    return directory / (name + ".env")

def read_target(path):
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return None
    if not stat.S_ISREG(mode) or os.path.islink(path):
        fail("unsafe target")
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        fail("unsafe target")
    with os.fdopen(fd, "rb") as input_file:
        if not stat.S_ISREG(os.fstat(input_file.fileno()).st_mode):
            fail("unsafe target")
        return input_file.read()

def parse(data):
    if not data or len(data) > MAX_BYTES:
        fail("invalid input at line 0")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f"invalid input at line {data[:error.start].count(bytes([10])) + 1}")
    values = {}
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        match = ASSIGNMENT.fullmatch(line)
        if not match or match.group(2) in values:
            fail(f"invalid input at line {number}")
        values[match.group(2)] = match.group(3)
    return values

def backup(directory, name, old):
    if old is None:
        return None
    history = directory / ".history"
    history.mkdir(mode=0o700, exist_ok=True)
    os.chmod(history, 0o700)
    stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%SZ")
    path = history / f"{name}.{stamp}.env"
    with open(path, "wb") as output:
        os.chmod(path, 0o600)
        output.write(old)
        output.flush()
        os.fsync(output.fileno())
    backups = sorted(history.glob(f"{name}.*.env"), key=lambda item: item.stat().st_mtime_ns, reverse=True)
    for stale in backups[10:]:
        stale.unlink()
    return path

def put(name):
    valid_name(name)
    data = sys.stdin.buffer.read(MAX_BYTES + 1)
    new_values = parse(data)
    directory = store_dir()
    target = target_for(name, directory)
    with open(directory / ".lock", "a+b") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        old = read_target(target)
        if old == data:
            print(f"unchanged {name}", file=sys.stderr)
            return
        old_values = parse(old) if old is not None else {}
        saved = backup(directory, name, old)
        fd, temporary = tempfile.mkstemp(prefix=".envstore-", dir=target.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as output:
                output.write(data)
                output.flush()
                os.fsync(output.fileno())
            # os.replace replaces final symlink rather than following it.
            os.replace(temporary, target)
            os.chmod(target, 0o600)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    added = sorted(new_values.keys() - old_values.keys())
    removed = sorted(old_values.keys() - new_values.keys())
    changed = sorted(key for key in new_values.keys() & old_values.keys() if new_values[key] != old_values[key])
    changes = " ".join([*("+" + key for key in added), *("-" + key for key in removed), *("~" + key for key in changed)])
    where = str(saved) if saved else "none"
    print(f"saved {name}: {len(new_values)} keys ({changes}), backup {where}", file=sys.stderr)
    if name == "infra":
        print("restart needed for services reading infra .env (ask orchestrator)", file=sys.stderr)

def get(name=None):
    directory = store_dir()
    if name is None:
        names = [item.name[:-4] for item in directory.glob("*.env") if NAME.fullmatch(item.name[:-4]) and item.is_file() and not item.is_symlink()]
        infra = target_for("infra", directory)
        if read_target(infra) is not None:
            names.append("infra")
        for item in sorted(set(names)):
            print(item)
        return
    valid_name(name)
    data = read_target(target_for(name, directory))
    if data is None:
        fail(f"no such env: {name}")
    sys.stdout.buffer.write(data)

def keys(name):
    valid_name(name)
    data = read_target(target_for(name, store_dir()))
    if data is None:
        fail(f"no such env: {name}")
    for key in sorted(parse(data)):
        print(key)

def diff(name):
    valid_name(name)
    local = parse(sys.stdin.buffer.read(MAX_BYTES + 1))
    stored_data = read_target(target_for(name, store_dir()))
    stored = parse(stored_data) if stored_data is not None else {}
    changes = [*("+" + key for key in local.keys() - stored.keys()),
               *("-" + key for key in stored.keys() - local.keys()),
               *("~" + key for key in local.keys() & stored.keys() if local[key] != stored[key])]
    if not changes:
        print("same")
        return
    for change in sorted(changes, key=lambda item: item[1:]):
        print(change)
    raise SystemExit(1)

def usage():
    print("usage: env-put <name> | env-get [name] | env-keys <name> | env-diff <name>")
    print("       envpush [name] [file] | envpull [name] [file] | envdiff [name] [file] | envkeys [name] | envlist")

def main():
    command = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    if command == "envstore.py":
        if not args or args[0] in ("--help", "-h"):
            usage()
            return
        command, args = args[0], args[1:]
    if args in (["--help"], ["-h"]):
        usage()
    elif command in ("env-put", "put") and len(args) == 1:
        put(args[0])
    elif command in ("env-get", "get") and len(args) <= 1:
        get(args[0] if args else None)
    elif command in ("env-keys", "keys") and len(args) == 1:
        keys(args[0])
    elif command in ("env-diff", "diff") and len(args) == 1:
        diff(args[0])
    else:
        usage()
        raise SystemExit(2)

if __name__ == "__main__":
    os.umask(0o077)
    main()
