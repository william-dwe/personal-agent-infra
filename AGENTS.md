# AGENTS.md: personal-agent-infra

Shared VPS infrastructure for William's personal agent team: the Hermes Agent dashboard, the
9router LLM router, and the Headroom compression sidecar. Butler (the orchestrator) will deploy from
here too once it exists (planned). This repo holds infra only: no wiki notes, no
Butler application code.

## Ownership and boundaries

| Path | Owner | Who writes it |
|---|---|---|
| `/home/ubuntu/services/personal-agent-infra` (this repo) | `ubuntu` | `ubuntu` only. Agents running as `hermes` deliver changes as a `git apply` patch for William to run as `ubuntu`. |
| `/home/hermes/services/second-brain-wiki` | `hermes` | Only the librarian agent, after William approves. Never put vault content here. |
| `/home/ubuntu/services/second-brain-service` | `ubuntu` | Legacy checkout. Retire it after migration; don't add features to it. |

- Before editing any `services/...` path, check its absolute path and owner. Similar-looking copies have been edited by mistake before.
- Remote `origin` is the PUBLIC repo github.com/william-dwe/personal-agent-infra. Push only with William's approval, and never commit `.env`, `data/`, real IPs, or tokens.
- Don't change global Git config. Set the commit identity per command, e.g. `git -c user.name=Ubuntu -c user.email=ubuntu@localhost.localdomain commit`.

## What runs here

| Component | Defined in | Runs as | Reach it at |
|---|---|---|---|
| Hermes dashboard (web + TUI) | `systemd/hermes-dashboard@.service` | `hermes-dashboard@<user>` (`hermes` or `ubuntu`, stored in `.dashboard-user`) | `http://<tailscale-ip>:9119` |
| 9router (LLM router) | `docker-compose.yml` | container `9router` | `http://<tailscale-ip>:20128` |
| Headroom (prompt compression) | `docker-compose.yml` | container `headroom` | `http://headroom:8787`, Docker network only |

- Only one user can run the dashboard, because only one process can listen on `:9119`. `scripts/deploy.sh <user>` links the unit, stops the others, and restarts the dashboard, which drops open browser and agent sessions.
- 9router calls Headroom's `/v1/compress` without a token. For that reason Headroom must not publish a host port or a Tailscale Serve rule. `scripts/check-headroom.sh` checks this.
- The network is locked down by UFW (`scripts/install/40-firewall.sh`): incoming traffic is denied by default, except `tailscale0` and port 22. The dashboard runs with `--insecure` on `0.0.0.0` and depends on this firewall.
- 9router is published only on the Tailscale IP (`TAILSCALE_IP` in `.env`; get it with `tailscale ip -4`). Never publish on `0.0.0.0`, because Docker-published ports bypass UFW.

## Layout

```text
docker-compose.yml             9router + headroom
systemd/                       hermes-dashboard@.service template (EnvironmentFile = this repo's .env)
scripts/init.sh                runs scripts/install/NN-*.sh in order; finished steps print "skipping"
scripts/install/NN-*.sh        idempotent bootstrap steps: system, docker, tailscale, zsh, firewall,
                               hermes user, hermes agent, headroom
scripts/deploy.sh [user]       link unit + switch the dashboard user
scripts/menu.sh                whiptail control panel (status, deploy, logs, install, hermes sudo)
scripts/hermes-sudo.sh         sudo ./scripts/hermes-sudo.sh on|off|status
scripts/check-headroom.sh      read-only smoke test for 9router -> headroom
```


Not tracked (see `.gitignore`), and never committed: `.env` (secrets, mode 600), `.dashboard-user`, `data/` (9router DB), `.archive/`.

## Security-sensitive knobs

- `scripts/hermes-sudo.sh on` writes `/etc/sudoers.d/90-hermes-agent`, which gives `hermes` passwordless root. `off` removes only that file.
- Membership in the `docker` group is also root-equivalent, so `hermes` in `docker` means `hermes` is effectively root.
- Mention either one whenever a change touches `hermes` permissions.

## Working here

- Before proposing a change, run `bash -n scripts/*.sh scripts/install/*.sh`, `docker compose config -q`, and `systemd-analyze verify systemd/*.service`.
- Install steps must stay idempotent. Print `==> <Name>: already installed, skipping` when there's nothing to do; `init.sh` detects skipped steps from that line.
- Keep scripts short and use Bash and core utilities only. Mark deliberate shortcuts with a `# ponytail:` comment that names the limit.
- If `docker` shows "unknown" or permission denied right after `usermod -aG docker`, the session has stale groups, often from a shared SSH ControlMaster connection. Run `exec sudo -iu ubuntu` rather than reconnecting.
- The following restart live services, so ask William before running them: `deploy.sh`, `systemctl restart`, `docker compose up/down`.
