# Butler permissions

Butler role creates `/var/lib/butler` owned by `hermes`, mode `0770`, with ACL `u:ubuntu:rwx` and defaults for both users. During `butler-deploy`, role grants root ACL to existing data before Compose starts: backend runs as root only because host `hermes` UID is not portable into images, drops all capabilities, applies `umask 0007`, and mounts only `/var/lib/butler` read-write.

Host CLI runs as `hermes` at `/usr/local/bin/butler`; `butler-deploy` exports it from backend image. Do not add `hermes` to Docker group: it is root-equivalent. Ubuntu retains `rwx` only while something runs CLI as ubuntu: ubuntu orchestrator profile carries a copy of `butler-tasks` skill. Remove it later:

```sh
sudo setfacl -R -x u:ubuntu,d:u:ubuntu /var/lib/butler
```

Butler role links `/var/lib/butler/wiki` to configured `WIKI_DIR` from `/etc/personal-agent-infra.paths`. Butler backend mounts that same absolute path read-only; `hermes` keeps normal write access for librarian. Protection is application-level only: notes adapter opens files `O_RDONLY` via a single function, never follows symlinks, hides dot paths (`.git`/`.data-git`), never runs git; notes API is GET/HEAD only; tests enforce it (`TestNoWriteAPIs`, `TestScanIsReadOnly`, `TestNotesMethods`).
