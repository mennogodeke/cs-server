terraform {
  required_version = ">= 1.9"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  # Phase 1: local state (git-ignored). Bootstrap state changes rarely.
  # Phase 2: move to a remote backend so CI can read these outputs.
}

provider "hcloud" {
  token = var.hcloud_token
}
