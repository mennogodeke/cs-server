# CS2 server — status / resume point

<!-- TODO(review): stale throughout (says nothing has run, mod stack is stubs,
     80 GB volume, admin_cidr) and mentions menno.codes. Delete this file —
     README + RUNBOOK already cover it — and remove the links to it. -->

**As of 2026-09-15.** Open this first, then work from [`RUNBOOK.md`](RUNBOOK.md).

> **One-liner:** the scaffold is complete and moved into its own repo
> (`mennogodeke/cs-server`, standalone from other infra). Nothing has been run
> against a real Hetzner account yet. Starting at RUNBOOK **Phase 0** now that the
> Hetzner account is funded.

---

## What's built

The full scaffold — a `gameday` CLI wrapping Terraform to create a CS2 server per
session and destroy it after.

Verified locally:

- `terraform validate` passes for `terraform/bootstrap/` and `terraform/session/`
  (hcloud provider 1.68; Primary IP uses `location`, not `datacenter`).
- `terraform fmt` clean.
- `gameday` logic works: `help`, bad-subcommand, bad-flag all behave;
  `cs2_parse_format` maps `5v5→13`, `8v8→19`, `5v4→13`, rejects `9v9` / `""` / non-`NvN`.
- `bash -n` clean on all scripts.
- The cloud-init volume-attach race (device wait-loop, `chown` after mount) is fixed.

Not yet run: `shellcheck`, `bats` (need `sudo pacman -S shellcheck bats` — CI installs them).

## What's NOT done

- [ ] **Never run against Hetzner.** No account/token/GSLT wired yet — that's Phase 0–2,
      starting now that the account has funds.
- [ ] **Mod stack is stubs** — `addons/versions.lock` is all `TODO`, `scripts/pre.sh`
      is a no-op. That's Phase 7.
- [ ] Local Terraform state only — no remote backend, so no CI-driven `gameday down`.

## Decisions locked (don't re-litigate)

| Decision | Choice | Why |
|----------|--------|-----|
| Lifecycle | On-demand **create/destroy** per session | A stopped Hetzner server still bills; only delete stops it |
| Host | Hetzner **CCX13** (2 dedicated vCPU), `fsn1` or `nbg1` | Hourly billing makes dedicated cores affordable; ~15–25 ms from NL/DE |
| Game persistence (v1) | 80 GB **volume** (~€3.50/mo) | Works with terraform+hcloud only; Packer snapshot is a later swap |
| Config per session | `gameday up --format 3v3..8v8 --map --mode` | One instance, parametrised |
| Secrets (v1 → target) | git-ignored `secrets.auto.tfvars` → **1Password** (`op`) | `op` installed; GH Actions secret for the reaper |
| CLI | Bash `bin/gameday` + `bats` tests | Matches your stack; tmux-friendly |
| Safety net | Hourly GitHub Actions **reaper** force-deletes stale servers | Forgotten `down` can't bill for days |
| Repo | Standalone `mennogodeke/cs-server`, not a subdir of `infra` | Keeps this project independent of unrelated infra (e.g. menno.codes) |

## Start here today

1. **RUNBOOK Phase 0** — the prerequisites checklist:
   - Hetzner project + read/write API token → into 1Password.
   - Dedicated Steam account + GSLT for App 730.
   - `sudo pacman -S shellcheck bats` then `bats test` (expect green).
   - Latency test `fsn1` vs `nbg1` (command is in the RUNBOOK) — pick the winner. If
     it's `nbg1`, change the `location` default in `terraform/bootstrap/variables.tf`.
   - `curl -s https://ipv4.icanhazip.com` → your `admin_cidr`.
2. **RUNBOOK Phase 1** — `gameday bootstrap`.
3. **RUNBOOK Phase 2** — first `gameday up`; expect to iterate on cloud-init (though
   the known volume-race bug is already fixed, so this should go smoother than the
   RUNBOOK's "known issues" list implies).

## File map

| Path | What |
|------|------|
| `docs/RUNBOOK.md` | the phased plan (0 → 10) with commands + verify steps |
| `docs/playbook.html` | the "why": host comparison, cost, security |
| `terraform/bootstrap/` | reserved IP, firewall, volume — `gameday bootstrap` |
| `terraform/session/` | the ephemeral server — `gameday up` / `down` |
| `terraform/session/cloud-init.yaml.tftpl` | server boot config; volume-race fix already applied |
| `bin/gameday`, `bin/_lib.sh` | the CLI |
| `compose/docker-compose.yml`, `cfg/server.cfg` | deployed to the server by cloud-init |
| `addons/`, `scripts/pre.sh` | Phase 7 mod-stack stubs |
| `.github/workflows/` | `lint.yml`, `reaper.yml` |
