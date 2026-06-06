# =============================================================================
# Interconnect attach point (needed for console / gcloud steps)
# =============================================================================

output "aws_region" {
  description = "AWS region for CLI commands (SSM, console navigation)."
  value       = var.aws_region
}

output "aws_dx_gateway_id" {
  description = "Direct Connect Gateway ID — select this when creating the multicloud Interconnect in the AWS console (Step 3)."
  value       = aws_dx_gateway.this.id
}

output "aws_allowed_prefix_for_gcp" {
  description = "AWS VPC CIDR to advertise toward GCP when creating the transport (Step 4 --advertised-routes)."
  value       = var.aws_vpc_cidr
}

output "gcp_advertised_routes_for_transport" {
  description = "GCP subnetwork CIDR to pass to --advertised-routes when creating the transport (Step 4)."
  value       = var.gcp_vpc_cidr
}

output "gcp_vpc_network_name" {
  description = "GCP VPC network name — pass to gcloud transport and peering commands (Steps 4–5)."
  value       = google_compute_network.this.name
}

output "gcp_transport_name" {
  description = "Transport resource name used in gcloud commands (Steps 4–5)."
  value       = var.gcp_transport_name
}

output "gcp_region" {
  description = "GCP region for gcloud transport commands."
  value       = var.gcp_region
}

output "gcp_project_id" {
  description = "GCP project ID for gcloud commands."
  value       = var.gcp_project_id
}

# =============================================================================
# Connectivity test targets
# =============================================================================

output "aws_instance_id" {
  description = "EC2 instance ID — use with aws ssm start-session for connectivity tests (Step 7)."
  value       = aws_instance.this.id
}

output "aws_instance_private_ip" {
  description = "Private IP of the demo EC2 instance (GCP-side ping/SSH target)."
  value       = aws_instance.this.private_ip
}

output "gce_instance_name" {
  description = "GCE instance name — use with gcloud compute ssh --tunnel-through-iap (Step 7)."
  value       = google_compute_instance.this.name
}

output "gce_instance_zone" {
  description = "GCE instance zone for gcloud SSH commands."
  value       = google_compute_instance.this.zone
}

output "gce_instance_private_ip" {
  description = "Private IP of the demo GCE VM (AWS-side ping target)."
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "gce_ssh_private_key" {
  description = "Generated ED25519 private key for SSH to the GCE debian user (Step 7). Pair with gce_ssh_public_key for gcloud compute ssh --ssh-key-file."
  value       = tls_private_key.gce.private_key_openssh
  sensitive   = true
}

output "gce_ssh_public_key" {
  description = "Public half of the GCE SSH key pair — same key installed on the VM via metadata ssh-keys (Step 7). Save as demo-gce-key.pub alongside gce_ssh_private_key."
  value       = tls_private_key.gce.public_key_openssh
}

output "aws_vpc_id" {
  description = "AWS VPC ID."
  value       = aws_vpc.this.id
}

output "gcp_network_self_link" {
  description = "GCP VPC network self-link."
  value       = google_compute_network.this.self_link
}
