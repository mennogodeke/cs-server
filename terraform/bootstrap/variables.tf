variable "hcloud_token" {
  description = "Hetzner Cloud API token (project-scoped). Set via TF_VAR_hcloud_token or secrets.auto.tfvars."
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  description = "Prefix for all named resources. The session config looks resources up by these names."
  type        = string
  default     = "cs2"
}

variable "location" {
  description = "Hetzner location for the reserved IP, volume and (later) the server. fsn1 / nbg1 are closest to NL."
  type        = string
  default     = "fsn1"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key that may log into the session server."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "volume_size" {
  description = "Size in GB of the persistent data volume that holds the CS2 install between sessions. CS2 itself is ~71GB, and joedwards32/CS2 documents needing 60GB free on top of that during install/updates, so this needs real headroom beyond CS2's raw size."
  type        = number
  default     = 180

  validation {
    condition     = var.volume_size >= 70
    error_message = "CS2 plus GOTV demos needs at least 70 GB."
  }
}
