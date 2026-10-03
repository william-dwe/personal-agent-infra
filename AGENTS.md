# AGENTS.md: personal-agent-infra

Shared VPS infrastructure for William's personal agent team: Hermes Agent dashboard,
Butler orchestrator, 9router LLM router, and Headroom compression sidecar. This repo holds infra only:
no wiki notes or Butler application code.

## Ownership and boundaries

| Path | Owner | Who writes it |
|---|---|---|
| This infra checkout | Script-derived root | `ubuntu` only. Agents running as `hermes` deliver changes as a `git apply` patch for William to run as `ubuntu`. |
| Butler and wiki checkouts | `BUTLER_DIR` and `WIKI_DIR` in `/etc/personal-agent-infra.paths` | `hermes`; wiki only librarian writes after William approves. |
| `/home/ubuntu/services/second-brain-service` | `ubuntu` | Legacy checkout. Retire it after migration; don't add features to it. |

- Before editing any `services/...` path, check its absolute path and owner. Similar-looking copies have been edited by mistake before.
- Remote `origin` is the PUBLIC repo github.com/william-dwe/personal-agent-infra. Push only with William's approval. `.env` IS committed (dotenvx-encrypted, see README Secrets); never commit `data/`, real IPs, tokens, or a plaintext `.env`/`.env.keys` (the global `dotenvx protect` git filter blocks this as a safety net).
- Don't change global Git config. Set the commit identity per command, e.g. `git -c user.name=Ubuntu -c user.email=ubuntu@localhost.localdomain commit`.

## What runs here

| Component | Defined in | Runs as | Reach it at |
|---|---|---|---|
| Hermes dashboard (web + TUI) | `systemd/hermes-dashboard@.service` | `hermes-dashboard@<user>` (`hermes` or `ubuntu`, stored in `.dashboard-user`) | `http://<tailscale-ip>:9119` |
| Butler dashboard + API | configured `BUTLER_DIR/compose.yml` project `butler` | containers; backend joins core network only for 9router | Tailscale HTTPS `:8444` -> host loopback `:3100` -> `127.0.0.1:8765` |
| 9router (LLM router) | `docker-compose.yml` | container `9router` | `http://<tailscale-ip>:20128` |
| Headroom (prompt compression) | `docker-compose.yml` | container `headroom` | `http://headroom:8787`, Docker network only |

- Only one user can run the dashboard, because only one process can listen on `:9119`. `scripts/deploy.sh <user>` links the unit, stops the others, and restarts the dashboard, which drops open browser and agent sessions.
- 9router calls Headroom's `/v1/compress` without a token. For that reason Headroom must not publish a host port or a Tailscale Serve rule. `scripts/check-headroom.sh` checks this.
- The network is locked down by UFW (`scripts/install/40-firewall.sh`): incoming traffic is denied by default, except `tailscale0` and port 22. The dashboard runs with `--insecure` on `0.0.0.0` and depends on this firewall.
- 9router is published only on the Tailscale IP (`TAILSCALE_IP` rendered into `/etc/personal-agent-infra.env`; get it with `tailscale ip -4`). Never publish on `0.0.0.0`, because Docker-published ports bypass UFW.

## Layout

```text
docker-compose.yml             9router + headroom core project
systemd/                       hermes-dashboard@.service template (EnvironmentFile = /etc/personal-agent-infra.env)
scripts/init.sh                runs scripts/install/NN-*.sh in order; finished steps print "skipping"
scripts/install/NN-*.sh        idempotent bootstrap steps: system, docker, tailscale, zsh, firewall,
                               hermes user, hermes agent, dotenvx CLI, headroom, Butler checkouts/data/dashboard activation
scripts/butler.sh              scoped Butler Compose up/restart/down/status/logs; reads `/etc/personal-agent-infra.paths`, exports `/usr/local/bin/butler`
scripts/deploy.sh [user]       link unit + switch dashboard user
scripts/menu.sh                whiptail control panel (status, deploy, logs, install, hermes sudo)
scripts/hermes-sudo.sh         sudo ./scripts/hermes-sudo.sh on|off|status
scripts/check-headroom.sh      read-only smoke test for 9router -> headroom
```


Not tracked (see `.gitignore`): `.env.keys` (dotenvx private key material, never generated here—lives root-only on the VPS), `.dashboard-user`, `data/` (9router DB), `.archive/`. `.env` itself IS tracked, dotenvx-encrypted.

`75-services.sh` writes root-owned `/etc/personal-agent-infra.paths` mode `0644`: exactly absolute `BUTLER_DIR` and `WIKI_DIR`. Set both only before its first run; changing live locations requires an approved Butler stop, path-file update, and start.

## Env secrets

- dotenvx-encrypted `.env` (committed to this repo) is source of runtime secrets. `/etc/dotenvx/personal-agent-infra.env.keys` is the one secret-bearing file: root-owned mode `0600`, lives only on the VPS, never read or copied by agents. `/etc/personal-agent-infra.env` is the root-owned rendered runtime config.
- Agents may run `scripts/dotenv-env.sh status` only. Agents never run `render`, `dotenvx decrypt`, `dotenvx encrypt` on the committed `.env`, or read `/etc/dotenvx/personal-agent-infra.env.keys`. Adding a new key via `dotenvx set KEY value -f .env` doesn't need the private key, but still ask William to run it himself—an agent-entered value can't be confirmed without ever appearing in chat.
- When changing secret keys or `.env.example`, report key names and ask William to update the encrypted `.env` manually; never ask for or print values in chat.
## Security-sensitive knobs

- `scripts/hermes-sudo.sh on` writes `/etc/sudoers.d/90-hermes-agent`, which gives `hermes` passwordless root. `off` removes only that file.
- Membership in the `docker` group is also root-equivalent, so `hermes` in `docker` means `hermes` is effectively root.
- Mention either one whenever a change touches `hermes` permissions.
- `/var/lib/butler` (`scripts/install/80-butler-data.sh`) is read-write for exactly `hermes` and `ubuntu` via ACLs, no one else. It holds William's task DB and attachments.
- Butler runs from Compose with a root backend only because host `hermes` UID is not portable into images. Backend has a read-write `/var/lib/butler` mount and read-only wiki mount; host CLI remains `hermes`. Do not add `hermes` to Docker group.

## Working here

- Before proposing a change, run `bash -n scripts/*.sh scripts/install/*.sh`, relevant Python tests, `scripts/dotenv-env.sh status`, and `systemd-analyze verify systemd/*.service`. Agents never run `dotenv-env.sh render`, `dotenvx decrypt`, `dotenvx encrypt` on the committed `.env`, or `docker compose` against live services.
- Install steps must stay idempotent. Print `==> <Name>: already installed, skipping` when there's nothing to do; `init.sh` detects skipped steps from that line.
- Keep scripts short and use Bash and core utilities only. Mark deliberate shortcuts with a `# ponytail:` comment that names the limit.
- If `docker` shows "unknown" or permission denied right after `usermod -aG docker`, the session has stale groups, often from a shared SSH ControlMaster connection. Run `exec sudo -iu ubuntu` rather than reconnecting.
- The following restart live services, so ask William before running them: `deploy.sh`, `systemctl restart`, `scripts/butler.sh up`, or `scripts/butler.sh down`.
