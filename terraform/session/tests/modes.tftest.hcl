# Renders the session's cloud-init per --mode without touching Hetzner.
# Mocks only fill in *computed* attributes, and id / ip_address are optional
# inputs on these data sources — so they're overridden explicitly (numeric ids
# because main.tf tonumber()s them).
mock_provider "hcloud" {}

override_data {
  target = data.hcloud_primary_ip.ipv4
  values = { id = "1", ip_address = "192.0.2.1" }
}

override_data {
  target = data.hcloud_firewall.cs2
  values = { id = "2" }
}

override_data {
  target = data.hcloud_volume.data
  values = { id = "3" }
}

override_resource {
  target = hcloud_server.cs2
  values = { id = "4" }
}

variables {
  hcloud_token      = "test"
  gslt              = "test"
  sv_password       = "test"
  rcon_password     = "test"
  tailscale_authkey = "test"
}

run "prophunt_runs_mod_free_on_the_workshop_map" {
  command = plan

  variables {
    mode         = "prophunt"
    workshop_map = "3615968422"
  }

  assert {
    condition     = strcontains(hcloud_server.cs2.user_data, "CS2_MODS=0\n")
    error_message = "prophunt must run without Metamod/CounterStrikeSharp"
  }
  assert {
    condition     = strcontains(hcloud_server.cs2.user_data, "CS2_HOST_WORKSHOP_MAP=3615968422\n")
    error_message = "prophunt must start on the requested workshop map"
  }
  assert {
    condition     = strcontains(hcloud_server.cs2.user_data, "CS2_HOST_WORKSHOP_COLLECTION=3692550841\n")
    error_message = "prophunt must load the Prophunt Maps collection for in-session map switching"
  }
}

run "matchzy_leaves_the_workshop_keys_empty" {
  command = plan

  variables {
    mode = "matchzy"
  }

  assert {
    condition     = strcontains(hcloud_server.cs2.user_data, "CS2_MODS=1\n")
    error_message = "matchzy needs the mod stack"
  }
  assert {
    condition     = strcontains(hcloud_server.cs2.user_data, "CS2_HOST_WORKSHOP_MAP=\n")
    error_message = "a non-empty workshop map would override matchzy's start map"
  }
  assert {
    condition     = strcontains(hcloud_server.cs2.user_data, "CS2_HOST_WORKSHOP_COLLECTION=\n")
    error_message = "a non-empty workshop collection would override matchzy's map group"
  }
}

run "prophunt_requires_a_workshop_map" {
  command = plan

  variables {
    mode = "prophunt"
  }

  expect_failures = [var.workshop_map]
}

run "workshop_map_must_be_numeric" {
  command = plan

  variables {
    mode         = "prophunt"
    workshop_map = "mirage"
  }

  expect_failures = [var.workshop_map]
}
