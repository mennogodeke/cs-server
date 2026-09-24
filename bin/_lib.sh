#!/usr/bin/env bash
# Shared helpers for bin/gameday. Sourced by the CLI and by test/*.bats.

cs2_die()  { printf 'gameday: %s\n' "$*" >&2; exit 1; }
cs2_log()  { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
cs2_need() { command -v "$1" >/dev/null 2>&1 || cs2_die "missing dependency: $1"; }

# cs2_tailscale_ip HOSTNAME
#   Prints the Tailscale IP of the peer with this hostname that's actually
#   reachable, or dies.
#
#   Ephemeral nodes aren't deregistered instantly on an abrupt VM destroy, so a
#   freshly recreated server can briefly coexist with a stale node of the same
#   name (MagicDNS would resolve to whichever registered first — not
#   necessarily the live one). Tailscale's own `Online` flag isn't reliable
#   enough to resolve this alone either — observed live, a destroyed node can
#   still report Online:true for a while after it's genuinely unreachable — so
#   this tries the Online-flagged candidate(s) first (usually right, and
#   avoids an unnecessary timeout), then falls back to every other candidate,
#   verifying actual TCP reachability on port 22 rather than trusting the flag.
cs2_tailscale_ip() {
  local hostname="$1"
  cs2_need tailscale
  cs2_need jq
  local candidates
  candidates="$(tailscale status --json | jq -r --arg h "$hostname" '
    [.Peer[] | select(.HostName == $h)] | sort_by(.Online) | reverse | .[].TailscaleIPs[0]
  ')"
  [[ -n "$candidates" ]] || cs2_die "no tailnet peer named '$hostname' — is the session up, and is this machine on the tailnet?"
  local ip
  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    # TODO(review): `timeout` is GNU coreutils — not on stock macOS, so every probe
    # fails and `gameday rcon` always dies below. Use `nc -z -w 3` or a portable
    # background-and-kill fallback.
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${ip}/22" 2>/dev/null; then
      echo "$ip"
      return 0
    fi
  done <<< "$candidates"
  cs2_die "found tailnet peer(s) named '$hostname' but none are actually reachable on port 22"
}

# cs2_parse_format NvN
#   Prints the CS2 maxplayers value for a team format and returns 0,
#   or prints an error and returns 1 for anything that isn't 1v1..8v8.
#   maxplayers = larger side * 2 + 3 spectator/caster slots.
cs2_parse_format() {
  local fmt="${1:-}"
  if [[ ! "$fmt" =~ ^([1-8])v([1-8])$ ]]; then
    echo "invalid format: '${fmt}' (want NvN with each side 1-8, e.g. 5v5)" >&2
    return 1
  fi
  local a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}"
  local per_side=$(( a > b ? a : b ))
  echo $(( per_side * 2 + 3 ))
}
