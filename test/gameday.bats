#!/usr/bin/env bats

setup() {
  load test_helper
}

@test "parse_format: 5v5 -> 13 slots" {
  run cs2_parse_format 5v5
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

@test "parse_format: 2v2 -> 7 slots" {
  run cs2_parse_format 2v2
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
}

@test "parse_format: 8v8 -> 19 slots" {
  run cs2_parse_format 8v8
  [ "$status" -eq 0 ]
  [ "$output" = "19" ]
}

@test "parse_format: uneven 5v4 sizes to the larger side" {
  run cs2_parse_format 5v4
  [ "$status" -eq 0 ]
  [ "$output" = "13" ]
}

@test "parse_format: rejects non-NvN input" {
  run cs2_parse_format competitive
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid format"* ]]
}

@test "parse_format: rejects sides above 8" {
  run cs2_parse_format 9v9
  [ "$status" -eq 1 ]
}

@test "parse_format: rejects empty input" {
  run cs2_parse_format ""
  [ "$status" -eq 1 ]
}

@test "gameday help exits 0 and lists subcommands" {
  run "$GAMEDAY" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"gameday up"* ]]
}

@test "gameday with no args prints usage" {
  run "$GAMEDAY"
  [[ "$output" == *"gameday bootstrap"* ]]
}

@test "gameday rejects an unknown subcommand" {
  run "$GAMEDAY" florp
  [ "$status" -ne 0 ]
}

@test "gameday up rejects an unknown flag before touching terraform" {
  run "$GAMEDAY" up --wat
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "gameday up rejects the removed --vanilla flag (use --mode vanilla)" {
  run "$GAMEDAY" up --vanilla
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "compose never bind-mounts into the steamcmd-managed game/ tree (except demos)" {
  # A bind mount over a file CS2 ships (e.g. server.cfg) makes steamcmd's
  # commit fail with "installed file locked", cancelling every update.
  run grep -E ':/home/steam/cs2-dedicated/game/' "$BATS_TEST_DIRNAME/../compose/docker-compose.yml"
  [ "$status" -eq 0 ]
  ! grep -v '/game/csgo/demos$' <<<"$output"
}

@test "default_format: rush defaults to 3v3" {
  run cs2_default_format rush
  [ "$status" -eq 0 ]
  [ "$output" = "3v3" ]
}

@test "default_format: other modes default to 5v5" {
  for mode in matchzy prophunt vanilla; do
    run cs2_default_format "$mode"
    [ "$output" = "5v5" ]
  done
}

@test "gameday up rejects an unknown --mode before touching terraform" {
  run "$GAMEDAY" up --mode florp
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
}

@test "pre.sh reads its stack from GAMEDAY_STACK, not CS2_GAMEMODE" {
  # The image's entry.sh treats CS2_GAMEMODE as the numeric game_mode
  # whenever CS2_GAMEALIAS is empty (rush), so it can't double as our stack name.
  run grep -nE '\$\{?CS2_GAMEMODE' "$BATS_TEST_DIRNAME/../scripts/pre.sh"
  [ "$status" -ne 0 ]
  grep -q 'GAMEDAY_STACK' "$BATS_TEST_DIRNAME/../scripts/pre.sh"
}

@test "prophunt_workshop_id: resolves each Prophunt map name" {
  local pair
  for pair in mirage=3615968422 inferno=3608612434 office=3644811896 \
              nuke=3711322683 dust2=3758986810; do
    run cs2_prophunt_workshop_id "${pair%%=*}"
    [ "$status" -eq 0 ]
    [ "$output" = "${pair#*=}" ]
  done
}

@test "prophunt_workshop_id: passes a raw numeric workshop ID through" {
  run cs2_prophunt_workshop_id 1234567890
  [ "$status" -eq 0 ]
  [ "$output" = "1234567890" ]
}

@test "prophunt_workshop_id: rejects official map names and lists the valid ones" {
  run cs2_prophunt_workshop_id de_dust2
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown prophunt map"* ]]
  [[ "$output" == *"mirage"* && "$output" == *"office"* ]]
}

@test "gameday up --mode prophunt rejects an unknown --map before touching terraform" {
  # Stub terraform so a regression here fails loudly instead of running a real apply.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "terraform was called" >&2\nexit 99\n' > "$BATS_TEST_TMPDIR/bin/terraform"
  chmod +x "$BATS_TEST_TMPDIR/bin/terraform"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$GAMEDAY" up --mode prophunt --map de_dust2
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown prophunt map"* ]]
  [[ "$output" != *"terraform was called"* ]]
}

@test "the PropHunt plugin stack is gone from compose and versions.lock" {
  run grep -n 'prophunt-' "$BATS_TEST_DIRNAME/../compose/docker-compose.yml"
  [ "$status" -eq 1 ]
  run grep -nE '^(PROPHUNT|MULTIADDONMANAGER|CS2MENUMANAGER)' "$BATS_TEST_DIRNAME/../addons/versions.lock"
  [ "$status" -eq 1 ]
}

@test "pre.sh prunes the old PropHunt stack from the volume, even with mods off" {
  # Left behind on the persistent volume, Metamod would load MultiAddonManager
  # v1.5.4's vdf in the next matchzy session — incompatible with Metamod 1473.
  local game="$BATS_TEST_TMPDIR/game"
  mkdir -p "$game/csgo/addons/metamod" "$game/csgo/addons/counterstrikesharp/plugins/PropHunt"
  touch "$game/csgo/addons/metamod/multiaddonmanager.vdf"
  run bash -c "cd '$game' && CS2_MODS=0 GAMEDAY_STACK=prophunt source '$BATS_TEST_DIRNAME/../scripts/pre.sh'"
  [ "$status" -eq 0 ]
  [ ! -e "$game/csgo/addons/metamod/multiaddonmanager.vdf" ]
  [ ! -e "$game/csgo/addons/counterstrikesharp/plugins/PropHunt" ]
}
