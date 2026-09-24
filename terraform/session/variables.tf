variable "hcloud_token" {
  description = "Hetzner Cloud API token. Same project as bootstrap."
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "Must match the bootstrap name_prefix — resources are looked up by name."
  type        = string
  default     = "cs2"
}

variable "location" {
  description = "Must match the bootstrap location / datacenter."
  type        = string
  default     = "fsn1"
}

variable "server_type" {
  description = "Hetzner server type. ccx13 = 2 dedicated vCPU (recommended). cx32 = shared, cheaper, casual only."
  type        = string
  default     = "ccx13"
}

variable "image" {
  description = "Base OS image. cloud-init installs Docker on top."
  type        = string
  default     = "debian-12"
}

# ---- per-session knobs, set by `gameday up --format / --map / --mode` ----

variable "format" {
  description = "Team format, NvN, from 1v1 to 8v8. Drives maxplayers."
  type        = string
  default     = "5v5"

  validation {
    condition     = can(regex("^[1-8]v[1-8]$", var.format))
    error_message = "format must look like 5v5, with each side between 1 and 8."
  }
}

variable "map" {
  description = "Map the server starts on."
  type        = string
  default     = "de_anubis"
}

variable "mode" {
  description = "Which mod stack to run: matchzy (competitive, knife rounds etc) | prophunt | vanilla (no mods). Mutually exclusive — switching modes prunes the other stack's plugins from the persistent volume."
  type        = string
  default     = "matchzy"

  validation {
    condition     = contains(["matchzy", "prophunt", "vanilla"], var.mode)
    error_message = "mode must be one of: matchzy, prophunt, vanilla."
  }
}

variable "hostname" {
  description = "Server name shown in the client."
  type        = string
  default     = "friends only"
}

variable "tv_delay" {
  description = "GOTV broadcast delay in seconds."
  type        = number
  default     = 90
}

# ---- secrets ----

variable "gslt" {
  description = "Game Server Login Token for App 730 (steamcommunity.com/dev/managegameservers)."
  type        = string
  sensitive   = true
}

variable "sv_password" {
  description = "Join password handed to friends."
  type        = string
  sensitive   = true
}

variable "rcon_password" {
  description = "RCON password. 24+ random chars. Never exposed to the public internet."
  type        = string
  sensitive   = true
}

variable "tailscale_authkey" {
  description = "Reusable + ephemeral Tailscale auth key. Joins the session server to the tailnet so admin SSH/RCON never needs a public port."
  type        = string
  sensitive   = true
}
