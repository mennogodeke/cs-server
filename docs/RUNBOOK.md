# CS2 server — build runbook

Phased plan from empty repo to a competitive-ready on-demand server. Each phase has a
**goal**, **steps**, **verify**, and **if it breaks** notes. Phases 0–3 are the critical
path to "friends can play"; phase 7 is the critical path to "MatchZy 5v5".

| Phase | Outcome | Effort | Depends on |
|-------|---------|--------|-----------|
| 0 | Accounts, tokens, tools, location chosen | ~30 min | — |
| 1 | Long-lived infra exists (IP, firewall, volume) | ~15 min | 0 |
| 2 | First session boots, you + a friend connect | ~1–2 h (iterative) | 1 |
| 3 | Second boot is fast; format/map/mode knobs work | ~30 min | 2 |
| 4 | Reaper running in CI | ~20 min | 2 |
| 5 | Admin plane hardened (SSH/RCON) | ~30 min | 3 |
| 6 | Secrets in 1Password, tfvars deleted | ~20 min | 3 |
| 7 | Metamod + CounterStrikeSharp + MatchZy | ~½–1 day | 3 |
| 8 | Demos retained off the server | ~20 min | 7 |
| 9 | Remote state, phone trigger, pre-commit, tflint | ~half day | 4 |
| 10 | Documented, operating, cost-reviewed | ongoing | all |

---

## Phase 0 — Prerequisites

**Goal:** everything you need before touching Terraform.

- [ ] **Hetzner Cloud**: create an account → new **Project** `cs2` → Security → API Tokens → generate a **read/write** token. Keep it in 1Password now.
- [ ] **Steam GSLT**: use a **dedicated Steam account** for the server (a VAC ban on *any* game on the account revokes the token). On that account: <https://steamcommunity.com/dev/managegameservers> → create token for **App ID 730** → note the token.
- [ ] **Local tools**: `sudo pacman -S shellcheck bats` (terraform, hcloud, docker, op already present).
- [ ] **SSH key**: confirm `~/.ssh/id_ed25519.pub` exists (`ssh-keygen -t ed25519` if not).
- [ ] **Choose location** — latency test from your connection:
  ```sh
  for h in fsn1-speed.hetzner.com nbg1-speed.hetzner.com hel1-speed.hetzner.com; do
    echo "== $h =="; ping -c 20 -q "$h" | tail -2
  done
  ```
  Pick the lowest median. `fsn1` and `nbg1` are usually within a few ms for NL/DE border.
<!-- TODO(review): admin_cidr no longer exists (SSH moved to Tailscale in phase 5).
     Replace with "join this machine to your tailnet + create a tagged auth key". -->
- [ ] **Admin IP**: `curl -s https://ipv4.icanhazip.com` → use as `admin_cidr = "<ip>/32"`.
      If your home IP is dynamic, expect to re-run bootstrap when it changes, or plan for
      Tailscale in phase 5.
- [ ] Run the tests once: `bats test` → all green.

**Verify:** `hcloud context create cs2` (paste token) then `hcloud server list` returns an empty list without error.

---

## Phase 1 — Bootstrap the long-lived infra

**Goal:** the reserved IP, firewall and data volume that persist between sessions.

```sh
cd terraform/bootstrap
cp secrets.auto.tfvars.example secrets.auto.tfvars
$EDITOR secrets.auto.tfvars        # hcloud_token + admin_cidr  <!-- TODO(review): admin_cidr is gone -->
$EDITOR variables.tf               # only if you chose nbg1: change location default
cd -
./bin/gameday bootstrap            # review plan — 4 resources — then approve
```

**Verify:**
```sh
hcloud primary-ip list             # cs2-ipv4, not assigned
hcloud firewall list               # cs2-fw
hcloud volume list                 # cs2-data, 80 GB, not attached  <!-- TODO(review): 180 GB now, here + phase 2 + cost checkpoint -->
terraform -chdir=terraform/bootstrap output primary_ipv4
```
- [ ] Record the IP. Optionally add a DNS `A` record (`cs.yourdomain.nl → <ip>`) so the connect string is memorable.
- [ ] Commit the changes: `git add -A && git commit` (secrets are git-ignored — double-check `git status` shows no `*.auto.tfvars`).

**Cost checkpoint:** from here you pay ~**€4/mo** (IP + volume) even with no server running. That's the floor.

**If it breaks:**
- `assignee_type`/`datacenter` errors → provider version skew; this repo targets hcloud `~> 1.49` and was validated on 1.68.
- `file(pathexpand(...))` can't read the key → fix `ssh_public_key_path`.

---

## Phase 2 — First session shakeout

**Goal:** `gameday up` produces a server you can actually connect to. **Expect to iterate on `cloud-init.yaml.tftpl` here** — this is where the scaffold meets reality.

```sh
cd terraform/session
cat > secrets.auto.tfvars <<'EOF'
hcloud_token  = "…"
gslt          = "…"
sv_password   = "friday"
rcon_password = "…32+ random chars…"
EOF
# TODO(review): missing tailscale_authkey — this example no longer applies as-is.
cd -
./bin/gameday up --format 5v5 --map de_dust2
```

Watch it come up (separate terminal):
```sh
hcloud server list
ssh root@<ip> 'cloud-init status --wait; tail -n +1 -f /var/log/cloud-init-output.log'
# once compose is up:
ssh root@<ip> 'cd /opt/cs2 && docker compose logs -f cs2'
```
First boot downloads CS2 (~60 GB, 20–40 min). Subsequent boots reuse the volume.

**Verify:**
- [ ] `df -h /opt/cs2/data` on the server shows the **80 GB volume** mounted (not the root disk).
- [ ] `docker compose logs cs2` ends with the server registering with Steam (GSLT accepted, no `PreMinidumpCallback` crash loop).
- [ ] From your client console: `connect <ip>:27015; password friday` → you spawn on de_dust2.
- [ ] Server console `status` shows your SteamID and a sane `ping`.
- [ ] **A friend connects** — this is the real GSLT + firewall test from a third party.
- [ ] `./bin/gameday down` → `hcloud server list` empty; IP + volume remain.
- [ ] Hetzner Console → Usage shows only the hours the server existed.

**Known issues to fix in this phase (in likelihood order):**

1. ~~**Volume-attach race.**~~ **Already fixed.** `cloud-init.yaml.tftpl` wraps the
   device lookup in a wait loop before mounting, so this shouldn't bite on first boot.
2. **Primary IP binding.** `public_net { ipv4 = data.hcloud_primary_ip.ipv4.id }` — if apply rejects the type, the data-source `.id` may need `tonumber()`, or switch to referencing by `assignee_id` from the bootstrap side.
3. ~~**Container write perms.**~~ **Already fixed.** `chown -R 1000:1000 /opt/cs2/data`
   already runs after the mount, not before.
4. **Firewall / UDP.** If nobody can connect but the server is up, confirm the `cs2-fw` rules attached (`hcloud server describe <id>`) and that you're giving friends the **public** IP.
5. **`docker compose` v2 plugin** not present on the base image → the `get.docker.com` script installs it; if not, add `docker-compose-plugin` explicitly.

Iterate until `up → playable` is reliable and unattended, then move on.

---

## Phase 3 — Fast reboot + the knobs

**Goal:** confirm persistence and per-session config.

- [ ] `./bin/gameday up` again → CS2 does **not** re-download; server ready in 2–4 min. If it re-downloads, phase 2 issue #1 isn't actually fixed.
- [ ] `./bin/gameday up --format 3v3` → server console `sv_visiblemaxplayers` / `status` reflects ~9 slots.
- [ ] `--format 8v8 --map de_nuke --mode prophunt` → map + mode propagate.
- [ ] `./bin/gameday status` and `./bin/gameday connect` behave.
- [ ] `./bin/gameday down`.

---

## Phase 4 — The reaper

**Goal:** a forgotten `down` can't bill for days.

```sh
# TODO(review): drop `--repo mennogodeke/cs-server` below — gh defaults to the current repo.
git push -u origin main                                          # if not already pushed
gh secret set HCLOUD_TOKEN --repo mennogodeke/cs-server           # paste the token
gh variable set CS2_MAX_SESSION_HOURS --body 6 --repo mennogodeke/cs-server
```

**Verify:**
- [ ] Start a server (`gameday up`), then `gh workflow run "cs2 reaper" -f force=false` → run log says "keeping" (server is young).
- [ ] `gh workflow run "cs2 reaper" -f force=true` → server deleted; `hcloud server list` empty.
- [ ] `./bin/gameday down` after a reaper kill is a clean no-op (state self-heals because the IP/firewall/volume are data sources).
- [ ] Actions tab shows the hourly schedule enabled and the `cs2 lint` workflow green.

**If it breaks:** the `hcloud` tarball extraction in the workflow — if the release asset name changed, pin a version instead of `latest`.

---

## Phase 5 — Harden the admin plane ✅ Done

**Goal:** SSH and RCON are not casually reachable.

- [x] **RCON:** loopback-only on the host (`127.0.0.1:27016:27016` in `docker-compose.yml`), never bound to a public interface. `terraform/bootstrap` never opens a rule for it either.
- [x] **SSH:** no public port-22 rule at all (removed from `cs2-fw` — the RCON check and `PasswordAuthentication`/`fail2ban` items became moot once nothing internet-facing can reach the port). Session server joins the tailnet as `cs2-session` via cloud-init (`tailscale up --authkey=...`); admin access — `ssh root@cs2-session` or `gameday rcon` — only works from a machine on the same tailnet.
- [x] rcon_password: regenerated, stored in 1Password (`Gameday: CS2 RCON Password`).

**Known quirk:** ephemeral Tailscale nodes aren't deregistered instantly on an abrupt
VM destroy (`terraform destroy` / the reaper both just yank the VM, no graceful
`tailscale logout`). A server recreated soon after the last one can briefly coexist
with the old node under the same hostname — MagicDNS may resolve to the stale,
offline one. `gameday rcon` works around this (`cs2_tailscale_ip` in `bin/_lib.sh`
picks the peer that's actually `Online` from `tailscale status --json`); a bare
`ssh root@cs2-session` can hit the stale node right after a fast down/up cycle —
if it hangs, `tailscale status` will show two `cs2-session` entries, use the IP of
the online one directly.

---

## Phase 6 — Secrets to 1Password ✅ Done

**Goal:** no plaintext secrets on disk.

<!-- TODO(review): the item names below are your personal vault layout — generalise
     once the op:// refs approach lands. -->

- [x] One item per secret in the **`cs-server`** vault (not a single multi-field item
      — matches how the vault had already organically grown): `Gameday: Hetzner API
      Key`, `Steam GSLT`, `Gameday: CS2 Server Password`, `Gameday: CS2 RCON
      Password` (all Login items, `password` field), `tailgate cs-server ssh`
      (Secure Note, `notesPlain` — the Tailscale authkey).
- [x] `CS2_SECRET_SOURCE=op ./bin/gameday up --format 5v5` works — tested end to end
      for both `bootstrap` and `up`.
- [x] Deleted `terraform/*/secrets.auto.tfvars` (kept `.example`, added the one that
      was missing for `session/`).
- [ ] CI: the reaper only needs `HCLOUD_TOKEN` (already a `gh secret`). If you later add a CI `gameday` job, use a **1Password service account** token as a single `gh secret` and `op` in the workflow.
- [x] `README.md` documents `op` as the default, with the real vault/item table.

---

## Phase 7 — The mod stack ✅ Done (retake mode deferred)

**Goal:** Metamod → CounterStrikeSharp → MatchZy, with a vanilla fallback.

1. [x] **Pin versions** in `addons/versions.lock`. **Not the latest of each** —
   Metamod 1461+ bumped its SourceHook interface to 18, which CounterStrikeSharp
   v1.0.374 doesn't support yet (0 plugins load, "17 < 18" in the log — see
   [issue #1415](https://github.com/roflmuffin/CounterStrikeSharp/issues/1415)).
   Pinned at the community-confirmed-working combo: Metamod **1411**,
   CounterStrikeSharp **v1.0.374** (with-runtime), MatchZy **0.8.15**. Don't bump
   Metamod past 1461 until CSSharp ships a rebuild — check the versions.lock
   comment and that issue before touching this again.
2. [x] **`scripts/pre.sh`** — sourced by entry.sh (not executed — no `set -e`,
   every risky command is guarded so a failure logs a warning and falls back to
   the previous/no install rather than taking the server down). Installs
   Metamod → CounterStrikeSharp → MatchZy into `csgo/addons/`, registers
   Metamod in `csgo/gameinfo.gi`, idempotent via a version marker.
3. [x] **Mounted** in `compose/docker-compose.yml`. Two gotchas hit and fixed
   live, worth knowing if this ever needs touching again:
   - Every new bind-mount source needs a matching `write_files` entry in
     `cloud-init.yaml.tftpl` — a missing one makes Docker auto-create the
     source as an empty directory instead of erroring clearly, and mounting a
     file onto that later fails with a confusing "not a directory" error.
   - The two admin JSONs are mounted **flat** (`STEAMAPPDIR/*-admins.json`),
     not at their nested destination (`csgo/cfg/MatchZy/`,
     `csgo/addons/counterstrikesharp/configs/`) — those destination dirs don't
     exist until something creates them, and Docker auto-creates a missing
     bind-mount parent dir as **root:root**, which the container (running as
     uid 1000) can't write into. `pre.sh` copies them into place itself
     instead, so the `mkdir -p` runs as the right user.
4. [x] **Vanilla fallback** — folded into `--mode vanilla` (was a separate
   `--vanilla` flag / `CS2_MODS` var originally; see the mode restructure
   below). Tested: skips install, strips the Metamod line, boots clean with
   zero errors.
5. [x] **MatchZy config** — `cfg/matchzy/admins.json` (MatchZy's own admin
   list) and `cfg/matchzy/cssharp-admins.json` (CounterStrikeSharp's, `@css/root`
   — this is what gives an admin in-game console/chat commands like
   `changelevel`, no RCON tunnel needed). Shipped defaults already covered
   knife round and demo path, no override needed.
6. [x] **`--mode`** — originally wired as 5 MatchZy-only sub-behaviors
   (`competitive`/`match`/`practice`/`wingman`/`casual`), later **replaced**
   (not extended) with a simpler 3-way, mutually-exclusive stack selector:
   `matchzy | prophunt | vanilla`. Default `matchzy`. Switching modes prunes
   the other stack's plugin folders from the persistent volume in `pre.sh`
   (`CS2_GAMEMODE` env var, threaded the same way `CS2_MODS` already was) —
   without this, a stack installed in an earlier session would just sit there
   forever, never re-downloaded but also never removed, and
   CounterStrikeSharp would keep loading it alongside whichever stack is
   actually selected. `retake` still **not wired up** — needs a new addon
   (cs2-retakes) that hasn't been researched at all; not in the `--mode`
   validation list.
7. [x] **Prop Hunt** (added after the above, same either/or system) — three
   more components: MultiAddonManager, CS2MenuManager, PropHunt itself. Each
   has its own version constraint, cross-checked against the Metamod 1411 /
   CSSharp v1.0.374 pin from step 1 — see `addons/versions.lock` for the full
   reasoning (MultiAddonManager v1.6 needs Metamod 1459+, incompatible;
   v1.5.4 is pinned instead). `cfg/prophunt/de_dust2.txt` overrides the
   shipped map config, which only listed one prop model (so `.swap` had
   nothing to swap *to*) — expanded to 6 real prop paths pulled from the
   game's own `pak01_dir.vpk` (its path strings are plain ASCII, readable
   without a VPK tool).

**Verify:**
- [x] Server console: `meta list` shows Metamod (well — shows CounterStrikeSharp,
      loaded by Metamod — `meta list` doesn't list Metamod itself, that's expected),
      `css_plugins list` shows MatchZy loaded. Confirmed live via RCON.
- [ ] `.ready` / `!ready` in chat starts a MatchZy match; knife round happens.
      MatchZy loaded and warmup started correctly, but this specific flow
      wasn't manually clicked through in-game.
- [x] `gameday up --mode vanilla` starts with no addons and no errors. Confirmed live.
- [x] `gameday up --mode prophunt`: `css_plugins list` shows CS2MenuManager +
      PropHunt loaded, MatchZy genuinely absent (not just dormant). Confirmed
      live, including the prune when switching back and forth between modes
      on the same volume.
- [x] In-game: connected, became a prop automatically (hiders don't see their
      own transform in first-person — normal), `.swap` cycles between the 6
      real prop models. Confirmed by the user live.
      <!-- TODO(review): "confirmed by the user" reads like AI session notes — reword. -->

**Reality check:** budget ~1 h of maintenance after each **major** CS2 update — Metamod/CSSharp routinely need a rebuild. `--mode vanilla` is your safety valve. (This played out for real the same night — see the versions.lock note above.)

---

## Phase 8 — Demos & backups

**Goal:** match demos survive `gameday down`.

- Demos already land on the **persistent volume** (`/opt/cs2/data/.../demos`) so they survive `down` — the volume is the backup.
- [ ] Add `./bin/gameday demos pull` → rsync `/opt/cs2/data/**/demos/` to `~/cs2-demos/`.
- [ ] Add a prune step (keep last 30) so the volume doesn't fill.
- [ ] *Optional:* a Hetzner **Storage Box BX11** (~€3.80/mo, 1 TB) if you want off-project retention — `rsync` to it in `gameday down` before `terraform destroy`.

---

## Phase 9 — Platform polish

- [ ] **Remote Terraform state** — Terraform Cloud free workspace (or R2/B2 backend) for `session/`. Unlocks:
  - a `workflow_dispatch` "**start game night from my phone**" job (inputs: format, map) that posts the connect string to Discord
  - the reaper doing a clean `terraform destroy` instead of `hcloud server delete`
- [ ] **Pre-commit**: `terraform fmt`, `terraform validate`, `shellcheck`, `bats` as hooks.
- [ ] **CI**: add `tflint` + `trivy config` (or `tfsec`) to `lint.yml`.
- [ ] **`gameday` QoL**: `--dns` (Cloudflare API record update), Discord webhook on `up`, `gameday latency`.
- [ ] `.envrc` (direnv) exporting `CS2_SECRET_SOURCE=op` and `HCLOUD_TOKEN`.
- [ ] Evaluate **Packer golden snapshot** vs the volume — if you play less than weekly, the snapshot (~€0.75/mo) beats the always-allocated volume (~€3.50/mo). Build job: temp server → install → `hcloud image create` → destroy.

---

## Phase 10 — Operate

- [ ] Write a 3-line "how to start a game night" for the group (or a Discord slash command).
- [ ] Monthly: check the Hetzner invoice; confirm it tracks hours played.
- [ ] Keep `addons/versions.lock` current; test bumps on a throwaway session first.
- [ ] Revisit location choice after a few sessions if anyone reports lag.

---

## Critical paths

- **Vanilla, friends can play:** phases 0 → 1 → 2 → 3. About half a day, most of it waiting on the first CS2 download and iterating on cloud-init.
- **Competitive with MatchZy:** the above + phase 7. One to two days total.
- **Safe to leave unattended:** add phase 4 (reaper) as soon as phase 2 works.
