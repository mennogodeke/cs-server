# Long-lived resources for the CS2 server. Apply this once with `gameday bootstrap`.
# Nothing here is torn down between game nights — only the session server is.

resource "hcloud_ssh_key" "admin" {
  name       = "${var.name_prefix}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Reserved IPv4 so friends' `connect <ip>` string never changes across rebuilds.
# auto_delete = false keeps it allocated (~EUR 0.50/mo) when no server is attached.
# It is created in `location`; the session server must be created in the same place.
resource "hcloud_primary_ip" "ipv4" {
  name        = "${var.name_prefix}-ipv4"
  type        = "ipv4"
  location    = var.location
  auto_delete = false

  labels = {
    project = var.name_prefix
  }
}

resource "hcloud_firewall" "cs2" {
  name = "${var.name_prefix}-fw"

  # Game server + a little headroom for a second instance later.
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "27015-27017"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "CS2 game traffic"
  }

  # GOTV / SourceTV.
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "27020-27021"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "GOTV relay"
  }

  # ICMP so you can ping-test latency before a session.
  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ping"
  }

  # No public SSH rule: admin access is over Tailscale only (cloud-init joins the
  # session server to the tailnet as `cs2-session`). RCON stays loopback-only on
  # the host, reached the same way — see `gameday rcon`.
}

# Persistent data volume: the CS2 install and demos survive `gameday down` here.
# format = "ext4" means the volume comes pre-formatted; cloud-init just mounts it.
resource "hcloud_volume" "data" {
  name     = "${var.name_prefix}-data"
  size     = var.volume_size
  location = var.location
  format   = "ext4"

  labels = {
    project = var.name_prefix
  }
}
