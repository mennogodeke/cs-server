terraform {
  required_version = ">= 1.9"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  # Phase 1: local state (git-ignored), driven by `bin/gameday` on your machine.
  # Phase 2: remote backend so a scheduled CI job can run `destroy` too.
}

provider "hcloud" {
  token = var.hcloud_token
}
