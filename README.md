# personal-agent-infra

VPS infrastructure for Hermes Agent dashboard, Butler dashboard and API, 9router LLM router, and Headroom prompt-compression sidecar.

![personal-agent-infra architecture](docs/architecture.svg)

Interactive version with summary cards: [docs/architecture.html](docs/architecture.html). Ownership and agent rules live in [AGENTS.md](AGENTS.md).

## Components

| Component | Runs as / network | Reach it at |
|---|---|---|
| Hermes dashboard | `hermes-dashboard@<user>` systemd template | `http://<tailscale-ip>:9119` |
| 9router | Docker container; published host port | `http://<tailscale-ip>:20128` |
| Headroom | Docker `app-network` only | `http://headroom:8787` |
| Butler dashboard + API | Compose project `butler` from configured `BUTLER_DIR/compose.yml`; backend joins core Docker network only for 9router | Tailscale HTTPS `:8444` -> host loopback `:3100` |

## Quick start (new VPS)

> **Prerequisite:** Install Git and configure GitHub SSH access before cloning or deploying.
>
> ```bash
> sudo apt update && sudo apt install -y git openssh-client
> ssh-keygen -t ed25519 -C "you@example.com"
> cat ~/.ssh/id_ed25519.pub
> # Add output at https://github.com/settings/ssh/new, then verify:
> ssh -T git@github.com
> ```

Install Ansible and Git on the control node. Run locally from the new VPS, or target it over SSH from a laptop:

```bash
sudo apt-get install -y ansible git
```

Create the vault on the old VPS. `ansible/secret.txt` is one git-ignored line; store it in a password manager. `vault.yml` is ciphertext safe to commit.

```bash
cd ansible
(umask 077; openssl rand -base64 32 > secret.txt)
sudo cat /etc/dotenvx/personal-agent-infra.env.keys | python3 -c 'import json,sys; print("vault_dotenvx_private_key: " + json.dumps(sys.stdin.read()))' | ansible-vault encrypt --output group_vars/all/vault.yml
```

On the new VPS, clone this repo, write the same one-line `ansible/secret.txt` with mode `0600`, then run:

```bash
cd ansible
ansible-playbook playbooks/site.yml
```

From a laptop:

```bash
ansible-playbook -i '<host>,' -u ubuntu playbooks/site.yml
```

Add `-K` when sudo needs a password. The playbook pauses for interactive Tailscale login. Use `--tags <name>` to run one bootstrap area.

`ansible/inventory.yml` holds environment-specific non-secret values (`admin_user`, `agent_user`, dashboard user, checkout path, repo URL, runtime env path). Override them in another inventory for a different VPS. `playbooks/site.yml` orders roles by dependency: `common`, `tailscale`, `hermes`, `devtools`, `dotenvx`, `headroom`, `9router`, then `butler`. `common` owns shared OS setup and splits packages, Docker, shell, firewall, and repository tasks; `devtools` installs pinned Node.js and Go plus Python pip, TypeScript, Herdr, and OMP for `admin_user`; other roles own platform components or applications. `backup.yml` and `restore.yml` own migration orchestration. Each role uses the standard `defaults/main.yml`, `vars/main.yml`, `tasks/main.yml`, and `handlers/main.yml` layout.

`site.yml` does not clone Butler or the wiki, or start Butler. After it finishes, run:

```bash
sudo bash scripts/install/75-services.sh
sudo bash scripts/install/81-butler-dashboard.sh
```

Then enable `butler-review-queue.timer` manually, and choose a dashboard user:

```bash
./scripts/deploy.sh [user]
```

## Scripts

| Script | Purpose |
|---|---|
| `scripts/deploy.sh [user]` | Link units and switch dashboard user. |
| `scripts/menu.sh` | Whiptail control panel for status, dashboard controls, and Hermes sudo. |
| `scripts/check-headroom.sh` | Read-only 9router-to-Headroom smoke test. |
| `scripts/hermes-sudo.sh on\|off\|status` | Manage Hermes passwordless sudo grant. |
| `scripts/butler.sh up\|restart\|down\|status\|logs` | Scoped Butler Compose control; `up` rebuilds images and exports host CLI. |
| `scripts/dotenv-env.sh render\|status` | Decrypt committed `.env` into `/etc/personal-agent-infra.env`, or report setup status without values. |
| `scripts/install/75-services.sh` | Clone private Butler over SSH (`hermes` needs Butler repo access) and public second-brain-wiki over HTTPS. Defaults to `/home/hermes/services/{butler,second-brain-wiki}`; override once with absolute `BUTLER_DIR` and `WIKI_DIR`, or the clone URLs with `BUTLER_REPO_URL`/`WIKI_REPO_URL`. Trusts `github.com`'s SSH host key by pinning GitHub's own published fingerprint, never by blind scan-on-connect. |
| `scripts/install/81-butler-dashboard.sh` | Link `/var/lib/butler/wiki`, persist Tailscale Serve `:8444`, and start Butler Compose. |

## Migration (existing VPS)

State migration stops Hermes, review timer, and all containers while archiving. Archives contain plaintext secrets from Hermes `.env`, librarian token, and 9router state; keep only in git-ignored `ansible/backups/`, then delete after migration.

```bash
# Old VPS
cd ansible && ansible-playbook playbooks/backup.yml

# New VPS, after site.yml
ansible-playbook playbooks/restore.yml -e backup_file=backups/<name>.tar.zst
```

## Secrets

`.env` at repo root IS committed to this public repo, and that is intentional: it holds [dotenvx](https://dotenvx.com)-encrypted values (`KEY=encrypted:...`), not plaintext. The only secret-bearing runtime file is private key `/etc/dotenvx/personal-agent-infra.env.keys`, root-owned mode `0600`, generated once on VPS; its only copy outside VPS is Ansible Vault ciphertext `ansible/group_vars/all/vault.yml`, decryptable only with git-ignored one-line `ansible/secret.txt`. The `dotenvx` Ansible role installs the dotenvx CLI and a global (machine-level) git clean filter (`dotenvx protect`) that blocks committing plaintext `.env*` on this machine as a safety net.

`scripts/dotenv-env.sh render` (root only) decrypts `.env` using the private key, drops its stale `TAILSCALE_IP`/`BUTLER_ORIGIN`/`BUTLER_WEB_ORIGIN` lines, injects current host-derived values for those three, and atomically installs root-owned `/etc/personal-agent-infra.env` mode `0600`. It never prints secret values. The `dotenvx` and `headroom` Ansible roles, and `81-butler-dashboard.sh`, call it automatically. `scripts/dotenv-env.sh status` reports CLI/key/render state without values.

### Restore key from old VPS

Transferring `/etc/dotenvx/personal-agent-infra.env.keys` from an old VPS to a new one is an administrator-only, guided console action; it requires a manual authorization step on the old VPS and is not automated by Ansible or any script in this repo.

To add or rotate a secret, an administrator with the encrypted `.env` checked out runs, on a trusted terminal, never in chat:

```bash
dotenvx set SOME_KEY 'the-value' -f .env
```

This re-encrypts in place using the public key already embedded in `.env`'s header; it does not require the private key and does not decrypt anything else in the file. Commit the updated ciphertext normally, then request an approved `scripts/dotenv-env.sh render` run on the VPS. Keep `TAILSCALE_IP`, `BUTLER_ORIGIN`, and `BUTLER_WEB_ORIGIN` out of manual edits; the renderer supplies them from live host state.

To inspect decrypted values locally (admin only, never for agents):

```bash
dotenvx decrypt -f .env -fk /etc/dotenvx/personal-agent-infra.env.keys --stdout
```

## Security

- UFW denies incoming traffic by default; it allows `tailscale0` and TCP `22`.
- Dashboard uses `--insecure` on `0.0.0.0`; safety relies on UFW.
- 9router is published only on `TAILSCALE_IP`; Docker-published ports bypass UFW, so never bind `0.0.0.0`.
- Headroom must not publish host port or Tailscale Serve rule; 9router calls `/v1/compress` without token.
- `scripts/hermes-sudo.sh` grant and `docker` group membership are root-equivalent.
- Butler runs only through configured `BUTLER_DIR/compose.yml`; host ports remain loopback. Backend joins `personal-agent-infra_app-network` only for 9router; frontend stays private.
- `/var/lib/butler` is shared through named ACLs by `hermes` and `ubuntu`. Butler container runs as root only for portable bind-mount ownership; do not add `hermes` to Docker group.
