output "primary_ipv4" {
  description = "The reserved public IPv4. This is the address friends connect to."
  value       = hcloud_primary_ip.ipv4.ip_address
}

output "firewall_id" {
  value = hcloud_firewall.cs2.id
}

output "volume_id" {
  value = hcloud_volume.data.id
}

output "ssh_key_name" {
  value = hcloud_ssh_key.admin.name
}

output "location" {
  value = var.location
}
