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
