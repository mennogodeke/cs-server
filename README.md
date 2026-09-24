# cs-server — on-demand private Counter-Strike 2 server

One CS2 instance on Hetzner Cloud that you **create before a session and destroy
after**, so you only ever pay for the hours you actually play. An hourly GitHub
Actions **reaper** force-deletes anything left running by accident. Admin access
(SSH, RCON) exists only over a **Tailscale**-only admin plane — there's no public
SSH port at all — and every credential lives in **1Password**, pulled at boot,
never committed. The mod stack (Metamod, CounterStrikeSharp, MatchZy/Prop Hunt)
is version-**pinned** in [`addons/versions.lock`](addons/versions.lock) rather
than tracking `latest`.

Configurable 1v1–8v8. The game install and demos live on a persistent volume; a
reserved IP keeps the `connect` string stable. Full rationale:
[`docs/playbook.html`](docs/playbook.html).

> For the full phased build plan (setup, verify steps, known issues), see
> [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

```
terraform/bootstrap/   applied once   — reserved IPv4, firewall, data volume, SSH key
terraform/session/     per game night — the CCX13 server + volume attachment + cloud-init
compose/               docker-compose.yml deployed to the server by cloud-init
cfg/                   server.cfg, mode.cfg, matchzy/ (admin configs — see scripts/pre.sh)
scripts/pre.sh         installs Metamod/CounterStrikeSharp/MatchZy per addons/versions.lock
addons/versions.lock   pinned mod versions (not necessarily "latest" — see the file's own notes)
bin/gameday            the CLI: bootstrap | up | down | status | connect | rcon
bin/gameday-rcon-client.py  standalone RCON prompt (works around an in-game client quirk)
secrets.op.env.example the op:// refs template for 1Password-backed secrets
test/                  bats tests for the gameday logic
.github/workflows/     lint (terraform fmt/validate, shellcheck, bats) + the reaper
docs/                  RUNBOOK and the playbook design doc
```

## Prerequisites

| Tool | Minimum version | Notes |
|------|------------------|-------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.9+ | |
| [hcloud CLI](https://github.com/hetznercloud/cli#installation) | any recent | Hetzner Cloud CLI |
| [Docker](https://docs.docker.com/engine/install/) | any recent | only needed for local compose testing |
| [bats](https://bats-core.readthedocs.io/en/stable/installation.html) | any recent | to run `test/` |
| [op (1Password CLI)](https://developer.1password.com/docs/cli/get-started/) | any recent | **recommended default** — see below |
| [Tailscale](https://tailscale.com/download) | any recent | for admin SSH/RCON — there's no public SSH port |

You also need:

- A **Hetzner Cloud project** and an API token (Console → Security → API Tokens, read/write).
- A **GSLT** for App 730 — <https://steamcommunity.com/dev/managegameservers>.
- An SSH keypair; `bootstrap` uploads `~/.ssh/id_ed25519.pub` by default.
- A **Tailscale account**, with this machine joined (`sudo tailscale up`) — admin access
  (SSH, RCON) only exists over the tailnet, there is no public SSH port at all.

## One-time setup

Secrets live in 1Password by default — copy `secrets.op.env.example` to
`secrets.op.env` and point it at your own vault (see below). `secrets.auto.tfvars.example`
in each `terraform/` dir documents the git-ignored-tfvars fallback if you'd
rather not use `op`.

```sh
CS2_SECRET_SOURCE=op ./bin/gameday bootstrap          # review the plan, approve
```

This creates the reserved IPv4 (~€0.50/mo), the firewall, and the 180 GB data
volume (~€8/mo). These are the only things that cost money while you're not playing.

## A game night

```sh
CS2_SECRET_SOURCE=op ./bin/gameday up --format 6v6 --map de_nuke --mode matchzy
#   ==> 6v6 -> 15 slots | map de_nuke | mode matchzy
#   ... ~3–4 min: server boots, joins the tailnet, mounts the volume, starts CS2 ...
#   ==> connect 203.0.113.7:27015; password join-password

./bin/gameday status      # show current session outputs
./bin/gameday connect     # reprint the connect string
./bin/gameday rcon        # tunnel RCON over the tailnet (see Admin access below)

./bin/gameday down        # destroy the server. IP + volume stay.
```

`--format` accepts `1v1`–`8v8`; slots = larger side × 2 + 3. `--mode` picks
which mod stack runs — mutually exclusive, switching prunes the other stack
from the persistent volume:

| `--mode` | What runs |
|----------|-----------|
| `matchzy` (default) | Metamod, CounterStrikeSharp, MatchZy — knife round, `!ready`, admin commands (`.map`, `.rcon`, etc.) |
| `prophunt` | Metamod, CounterStrikeSharp, MultiAddonManager, CS2MenuManager, Prop Hunt |
| `vanilla` | No mods at all — plain CS2, the safety valve for when a CS2 patch breaks the mod stack |

Add `-y` to skip the Terraform prompt. `export CS2_SECRET_SOURCE=op` in your
shell profile to stop typing it every time.

### Secrets in 1Password

`load_secrets` in `bin/gameday` reads `secrets.op.env` (git-ignored) — a plain
list of `TF_VAR_<name>=op://<vault>/<item>/<field>` references, one per line.
Copy the template and point each ref at your own vault/item layout:

```sh
cp secrets.op.env.example secrets.op.env
$EDITOR secrets.op.env
```

```sh
TF_VAR_hcloud_token=op://<vault>/<item>/password
TF_VAR_gslt=op://<vault>/<item>/password
TF_VAR_sv_password=op://<vault>/<item>/password
TF_VAR_rcon_password=op://<vault>/<item>/password
TF_VAR_tailscale_authkey=op://<vault>/<item>/notesPlain
```

An `op://` reference can't contain a colon, even percent-encoded — if an
item's title has one, reference it by item ID instead
(`op item get "<title>" --vault <vault> --format json | jq -r .id`).

### Admin access (SSH / RCON)

There is no public SSH port — `terraform/bootstrap` only opens the game/GOTV UDP
ports and ICMP. Every session server joins your tailnet as `cs2-session` (cloud-init
runs `tailscale up` with the authkey above), so:

```sh
ssh root@cs2-session          # direct admin shell, once your own machine is on the tailnet
./bin/gameday rcon            # tunnels RCON (loopback-only on the host) over the same path
```

`gameday rcon` prints the RCON password and the in-game `rcon_address`/`rcon_password`
cvars to set — though in practice `bin/gameday-rcon-client.py` (a small standalone
client) is the more reliable path; the in-game `rcon` console command has a client-side
timing quirk over a tunneled connection.

## The reaper

`.github/workflows/reaper.yml` runs hourly and deletes any `project=cs2,role=session`
server older than `CS2_MAX_SESSION_HOURS` (default 6). It's the safety net for a
forgotten `gameday down`. Set it up once:

```sh
gh secret set HCLOUD_TOKEN
gh variable set CS2_MAX_SESSION_HOURS --body 12
```

Because `session/` only *reads* the IP/firewall/volume (they're data sources), a
reaper kill doesn't corrupt state — the next `gameday up` recreates the server
cleanly, and `gameday down` after a kill is a no-op.

## Cost (typical: ~48 h/month)

| | On-demand CCX13 | On-demand CX32 |
|--|--|--|
| Compute | ~€3.20 | ~€0.55 |
| Reserved IPv4 | €0.50 | €0.50 |
| Data volume (180 GB) | ~€8.00 | ~€8.00 |
| **Total** | **~€11.70/mo** | **~€9.05/mo** |

Switching the volume for a phase-2 Packer snapshot drops ~€3/mo. Worst case if the
reaper ever fails: CCX13 caps at ~€15 for a full month, not €43.

## Roadmap

The full phased plan — goals, commands, verify steps, known issues — is in
[`docs/RUNBOOK.md`](docs/RUNBOOK.md). Short version:

| Phase | Outcome |
|-------|---------|
| 0–1 | ✅ Accounts + tools; bootstrap the IP/firewall/volume |
| 2–3 | ✅ First session boots, friends connect; fast reboot + format knobs |
| 4 | ✅ Reaper live in CI |
| 5–6 | ✅ Harden SSH/RCON (Tailscale, no public SSH port); secrets to 1Password |
| 7 | ✅ MatchZy and Prop Hunt as mutually exclusive `--mode` stacks, with a vanilla fallback (`retake` mode not wired up yet) |
| 8–10 | Demo retention; remote state + phone trigger; operate |
