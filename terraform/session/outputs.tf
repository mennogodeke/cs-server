output "ip" {
  description = "Public IPv4 of the running server."
  value       = data.hcloud_primary_ip.ipv4.ip_address
}

output "maxplayers" {
  value = local.maxplayers
}

output "format" {
  value = var.format
}

output "connect" {
  description = "Paste this into the CS2 console."
  value       = "connect ${data.hcloud_primary_ip.ipv4.ip_address}:27015; password ${var.sv_password}"
  sensitive   = true
}

output "rcon_password" {
  description = "RCON password. Only usable over the SSH tunnel `gameday rcon` opens."
  value       = var.rcon_password
  sensitive   = true
}
