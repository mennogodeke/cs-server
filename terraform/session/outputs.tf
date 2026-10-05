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

# coalesce: `terraform test` can't mock ip_address (an optional input, not a
# computed attribute), and a null in a string template is a hard error.
output "connect" {
  description = "Paste this into the CS2 console."
  value       = "connect ${coalesce(data.hcloud_primary_ip.ipv4.ip_address, "unknown")}:27015; password ${var.sv_password}"
  sensitive   = true
}

output "rcon_password" {
  description = "RCON password. Only usable over the SSH tunnel `gameday rcon` opens."
  value       = var.rcon_password
  sensitive   = true
}
