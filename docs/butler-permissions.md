# Butler permissions

`80-butler-data.sh` creates `/var/lib/butler` owned by `hermes`, mode `0770`, with ACL `u:ubuntu:rwx` and default ACLs for both users. Task DB is `0660`; Butler services use `UMask=0007`.

Dashboard and CLI run as `hermes`: Telegram gateway `hermes-gateway@hermes` and orchestrator cron. Ubuntu retains `rwx` only while something runs CLI as ubuntu: ubuntu orchestrator profile carries a copy of `butler-tasks` skill. Remove it later:

```sh
sudo setfacl -R -x u:ubuntu,d:u:ubuntu /var/lib/butler
```

`81-butler-dashboard.sh` links `/var/lib/butler/wiki` to the wiki root; `hermes` keeps normal write access to the wiki (librarian); Butler's protection is application-level only: notes adapter opens files `O_RDONLY` via a single function, never follows symlinks, hides dot paths (`.git`/`.data-git`), never runs git; notes API is GET/HEAD only; tests enforce it (`TestNoWriteAPIs`, `TestScanIsReadOnly`, `TestNotesMethods`). No ACLs, no systemd mount sandbox for the wiki.
