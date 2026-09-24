#!/usr/bin/env bash
# joedwards32/cs2's entry.sh `source`s this file (mounted read-only at
# /home/steam/cs2-dedicated/pre.sh) right before it launches CS2 — cwd is
# ${STEAMAPPDIR}/game/. Installs Metamod + CounterStrikeSharp (always, shared
# foundation) plus exactly one gameplay stack selected by CS2_GAMEMODE:
# "matchzy" (MatchZy) or "prophunt" (MultiAddonManager + CS2MenuManager +
# PropHunt) — mutually exclusive, from ../versions.lock, idempotently. Also
# registers Metamod in csgo/gameinfo.gi. (MultiAddonManager registers itself
# via its own addons/metamod/multiaddonmanager.vdf — no gameinfo.gi edit
# needed for it.)
#
# IMPORTANT: this file is *sourced*, not executed as a subprocess — a `set -e`
# or a bare `exit` here would abort entry.sh itself and the CS2 launch with
# it. Every risky command below is guarded explicitly instead; a failed addon
# install logs a warning and leaves the previous install (or none) in place
# rather than taking the server down. CS2_MODS=0 skips all of this — the
# vanilla fallback for when a CS2 patch breaks Metamod/CSSharp until they
# ship a rebuild.

GAMEINFO="csgo/gameinfo.gi"
VERSIONS_LOCK="../versions.lock"
MARKER="csgo/addons/.gameday_versions"
GAMEMODE="${CS2_GAMEMODE:-matchzy}"

_pre_log() { echo "[pre.sh] $*"; }

# _verify_sha256 FILE EXPECTED_SHA256
#   Fails (non-zero) on a mismatch. An empty EXPECTED_SHA256 (unpinned in
#   versions.lock) is a warning, not a failure, so bumping a version without
#   its checksum yet doesn't hard-block the server.
_verify_sha256() {
  local file="$1" expected="$2" actual
  if [[ -z "$expected" ]]; then
    _pre_log "WARNING: no checksum pinned for $file, skipping verification"
    return 0
  fi
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    _pre_log "WARNING: checksum mismatch for $file (expected $expected, got $actual)"
    return 1
  fi
}

_metamod_registered() {
  grep -qF 'csgo/addons/metamod' "$GAMEINFO" 2>/dev/null
}

_register_metamod() {
  _metamod_registered && return 0
  if [[ ! -f "$GAMEINFO" ]]; then
    _pre_log "WARNING: $GAMEINFO not found, can't register Metamod"
    return 1
  fi
  # Insert as the first entry in SearchPaths { ... }, right before the
  # existing `Game csgo` line (matched exactly, so `Game csgo_imported`
  # a couple of lines below isn't touched).
  if sed -i '0,/^[[:space:]]*Game[[:space:]]\+csgo[[:space:]]*$/{s##\t\t\tGame\tcsgo/addons/metamod\n&#}' "$GAMEINFO"; then
    _pre_log "registered Metamod in gameinfo.gi"
  else
    _pre_log "WARNING: failed to register Metamod in gameinfo.gi"
  fi
}

_unregister_metamod() {
  _metamod_registered || return 0
  if grep -vF 'csgo/addons/metamod' "$GAMEINFO" > "${GAMEINFO}.tmp"; then
    mv "${GAMEINFO}.tmp" "$GAMEINFO"
    _pre_log "removed Metamod from gameinfo.gi (vanilla mode)"
  else
    rm -f "${GAMEINFO}.tmp"
    _pre_log "WARNING: failed to remove Metamod from gameinfo.gi"
  fi
}

# Admin config source files are mounted flat at STEAMAPPDIR root (../) rather
# than at their nested destination, to dodge a Docker gotcha: a missing
# bind-mount parent dir gets auto-created as root:root, but this container
# runs as uid 1000 — a root-owned csgo/cfg/MatchZy/ would block MatchZy
# (running as uid 1000) from writing its own files there. Copying lets us
# `mkdir -p` as the right user instead. Cheap enough to just re-copy every
# boot rather than version-track like the addon downloads above.
_deploy_admin_configs() {
  if [[ "$GAMEMODE" == "matchzy" && -f ../matchzy-admins.json ]]; then
    mkdir -p csgo/cfg/MatchZy
    if cp ../matchzy-admins.json csgo/cfg/MatchZy/admins.json; then
      _pre_log "deployed MatchZy admins.json"
    else
      _pre_log "WARNING: failed to deploy MatchZy admins.json"
    fi
  fi
  if [[ -f ../cssharp-admins.json ]]; then
    mkdir -p csgo/addons/counterstrikesharp/configs
    if cp ../cssharp-admins.json csgo/addons/counterstrikesharp/configs/admins.json; then
      _pre_log "deployed CounterStrikeSharp admins.json"
    else
      _pre_log "WARNING: failed to deploy CounterStrikeSharp admins.json"
    fi
  fi
}

# Overrides PropHunt's shipped per-map prop-model lists (see cfg/prophunt/).
# The destination dir already exists (created by extracting PropHunt itself,
# owned correctly since that extraction runs as this same user) — no mkdir -p
# ownership dance needed here, unlike _deploy_admin_configs above.
_deploy_prophunt_configs() {
  local dest="csgo/addons/counterstrikesharp/plugins/PropHunt/maps"
  [[ -d "$dest" ]] || return 0
  for f in ../prophunt-*.txt; do
    [[ -f "$f" ]] || continue
    local mapname="${f##*/prophunt-}"
    if cp "$f" "$dest/$mapname"; then
      _pre_log "deployed PropHunt map config: $mapname"
    else
      _pre_log "WARNING: failed to deploy PropHunt map config: $mapname"
    fi
  done
}

# The data volume persists across sessions, so switching CS2_GAMEMODE has to
# actively remove the *other* stack's plugin folder — otherwise it just sits
# there forever (never re-downloaded since versions.lock hasn't changed, but
# also never deleted), and CounterStrikeSharp keeps loading it alongside
# whichever stack is actually selected. Cheap rm -rf, safe to run every boot
# regardless of the idempotency marker below.
_prune_other_gamemode_stack() {
  if [[ "$GAMEMODE" != "matchzy" ]]; then
    rm -rf csgo/addons/counterstrikesharp/plugins/MatchZy csgo/cfg/MatchZy
  fi
  if [[ "$GAMEMODE" != "prophunt" ]]; then
    rm -rf csgo/addons/counterstrikesharp/plugins/PropHunt \
      csgo/addons/counterstrikesharp/plugins/CS2MenuManager_MenuManager \
      csgo/addons/metamod/multiaddonmanager.vdf \
      csgo/addons/multiaddonmanager \
      csgo/cfg/multiaddonmanager
  fi
}

if [[ "${CS2_MODS:-1}" == "0" ]]; then
  _pre_log "CS2_MODS=0 — vanilla mode, skipping addon install"
  _unregister_metamod
elif [[ ! -f "$VERSIONS_LOCK" ]]; then
  _pre_log "no versions.lock mounted, skipping addon install"
else
  # shellcheck disable=SC1090
  source "$VERSIONS_LOCK"
  mkdir -p csgo/addons
  _prune_other_gamemode_stack

  want="gamemode:${GAMEMODE} metamod:${METAMOD_BUILD:-} cssharp:${COUNTERSTRIKESHARP:-} matchzy:${MATCHZY:-} mam:${MULTIADDONMANAGER:-} menumgr:${CS2MENUMANAGER:-} prophunt:${PROPHUNT:-}"
  have=""
  [[ -f "$MARKER" ]] && have="$(cat "$MARKER" 2>/dev/null)"

  if [[ -n "$have" && "$have" == "$want" ]]; then
    _pre_log "addons already at pinned versions, skipping download"
  else
    all_ok=1

    if [[ -n "${METAMOD_BUILD:-}" ]]; then
      _pre_log "installing Metamod build ${METAMOD_BUILD}"
      if curl -fsSL "https://github.com/alliedmodders/metamod-source/releases/download/2.0.0.${METAMOD_BUILD}/mmsource-2.0.0-git${METAMOD_BUILD}-linux.tar.gz" -o /tmp/metamod.tar.gz \
        && _verify_sha256 /tmp/metamod.tar.gz "${METAMOD_SHA256:-}" \
        && tar xzf /tmp/metamod.tar.gz -C csgo; then
        rm -f /tmp/metamod.tar.gz
      else
        _pre_log "WARNING: Metamod download/verify/extract failed — leaving existing install (if any) untouched"
        all_ok=0
      fi
    fi

    if [[ -n "${COUNTERSTRIKESHARP:-}" ]]; then
      _pre_log "installing CounterStrikeSharp ${COUNTERSTRIKESHARP}"
      cssharp_ver="${COUNTERSTRIKESHARP#v}"
      if curl -fsSL "https://github.com/roflmuffin/CounterStrikeSharp/releases/download/${COUNTERSTRIKESHARP}/counterstrikesharp-with-runtime-linux-${cssharp_ver}.zip" -o /tmp/cssharp.zip \
        && _verify_sha256 /tmp/cssharp.zip "${COUNTERSTRIKESHARP_SHA256:-}" \
        && unzip -oq /tmp/cssharp.zip -d csgo; then
        rm -f /tmp/cssharp.zip
      else
        _pre_log "WARNING: CounterStrikeSharp download/verify/extract failed — leaving existing install (if any) untouched"
        all_ok=0
      fi
    fi

    if [[ "$GAMEMODE" == "matchzy" && -n "${MATCHZY:-}" ]]; then
      _pre_log "installing MatchZy ${MATCHZY}"
      if curl -fsSL "https://github.com/shobhit-pathak/MatchZy/releases/download/${MATCHZY}/MatchZy-${MATCHZY}.zip" -o /tmp/matchzy.zip \
        && _verify_sha256 /tmp/matchzy.zip "${MATCHZY_SHA256:-}" \
        && unzip -oq /tmp/matchzy.zip -d csgo; then
        rm -f /tmp/matchzy.zip
      else
        _pre_log "WARNING: MatchZy download/verify/extract failed — leaving existing install (if any) untouched"
        all_ok=0
      fi
    fi

    if [[ "$GAMEMODE" == "prophunt" && -n "${MULTIADDONMANAGER:-}" ]]; then
      _pre_log "installing MultiAddonManager ${MULTIADDONMANAGER}"
      if curl -fsSL "https://github.com/Source2ZE/MultiAddonManager/releases/download/${MULTIADDONMANAGER}/MultiAddonManager-${MULTIADDONMANAGER}-steamrt3.tar.gz" -o /tmp/mam.tar.gz \
        && _verify_sha256 /tmp/mam.tar.gz "${MULTIADDONMANAGER_SHA256:-}" \
        && tar xzf /tmp/mam.tar.gz -C csgo; then
        rm -f /tmp/mam.tar.gz
      else
        _pre_log "WARNING: MultiAddonManager download/verify/extract failed — leaving existing install (if any) untouched"
        all_ok=0
      fi
    fi

    # CS2MenuManager and PropHunt are CSSharp plugins whose archives are rooted
    # at addons/counterstrikesharp/ already (unlike the four above, which are
    # rooted at csgo/) — extract one directory deeper.
    if [[ "$GAMEMODE" == "prophunt" && -n "${CS2MENUMANAGER:-}" ]]; then
      _pre_log "installing CS2MenuManager ${CS2MENUMANAGER}"
      menumgr_num="${CS2MENUMANAGER#v1.0.}"
      mkdir -p csgo/addons/counterstrikesharp
      if curl -fsSL "https://github.com/schwarper/CS2MenuManager/releases/download/${CS2MENUMANAGER}/CS2MenuManager-v${menumgr_num}.zip" -o /tmp/menumgr.zip \
        && _verify_sha256 /tmp/menumgr.zip "${CS2MENUMANAGER_SHA256:-}" \
        && unzip -oq /tmp/menumgr.zip -d csgo/addons/counterstrikesharp; then
        rm -f /tmp/menumgr.zip
      else
        _pre_log "WARNING: CS2MenuManager download/verify/extract failed — leaving existing install (if any) untouched"
        all_ok=0
      fi
    fi

    if [[ "$GAMEMODE" == "prophunt" && -n "${PROPHUNT:-}" ]]; then
      _pre_log "installing PropHunt ${PROPHUNT}"
      mkdir -p csgo/addons/counterstrikesharp
      if curl -fsSL "https://github.com/exkludera-cssharp/PropHunt/releases/download/${PROPHUNT}/PropHunt_${PROPHUNT}.zip" -o /tmp/prophunt.zip \
        && _verify_sha256 /tmp/prophunt.zip "${PROPHUNT_SHA256:-}" \
        && unzip -oq /tmp/prophunt.zip -d csgo/addons/counterstrikesharp; then
        rm -f /tmp/prophunt.zip
      else
        _pre_log "WARNING: PropHunt download/verify/extract failed — leaving existing install (if any) untouched"
        all_ok=0
      fi
    fi

    if [[ "$all_ok" == "1" ]]; then
      echo "$want" > "$MARKER"
      _pre_log "addons installed at pinned versions"
    else
      _pre_log "WARNING: one or more addon installs failed — server may run with a partial or stale addon set"
    fi
  fi

  _register_metamod
  _deploy_admin_configs
  [[ "$GAMEMODE" == "prophunt" ]] && _deploy_prophunt_configs
fi
