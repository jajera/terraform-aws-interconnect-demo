# Implementation Plan: Private Connectivity Demo (Scenario 1)

## Overview

Provisions the AWS and GCP workload infrastructure for a private connectivity demo using
**AWS Interconnect – multicloud (Free Tier)**. Terraform manages the network and compute layers;
the Interconnect link itself (Steps 3–5 in the README) is created manually outside Terraform.

## Tasks

- [x] 1. Rewrite `variables.tf` for the multicloud Interconnect pattern
  - Remove legacy variables: `connection_bandwidth`, `vlan_id`, `bgp_asn`, `bgp_auth_key`, `interconnect_type`, `vlan_tag`, `gcp_bgp_asn`, `advertised_route_priority`, `instance_key_name`, `gcp_ssh_public_key`
  - Add general variables: `aws_region`, `gcp_region`, `gcp_project_id` (with regex validation), `gcp_transport_name` (with default)
  - Add AWS network variables: `aws_vpc_cidr` (CIDR validation), `aws_subnet_cidr` (CIDR validation), `aws_dx_gateway_asn`
  - Add GCP network variable: `gcp_vpc_cidr` (CIDR validation) — SSH key is auto-generated via `tls_private_key`
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [x] 2. Rewrite `aws-interconnect.tf` — DX Gateway only
  - Remove `aws_dx_connection.this` and `aws_dx_private_virtual_interface.this`
  - Keep `aws_dx_gateway.this` with `amazon_side_asn = var.aws_dx_gateway_asn`
  - Add comment block explaining the console/CLI workflow for the Interconnect itself
  - _Requirements: 2.1, 2.2_

- [x] 3. Delete `gcp-interconnect.tf`
  - Remove `google_compute_router.this`, `google_compute_interconnect_attachment.this`, `google_compute_router_peer.this`
  - These belong to the legacy DEDICATED model — the multicloud pattern uses a transport + VPC peering created outside Terraform
  - _Requirements: 5.1_

- [x] 4. Rewrite `aws-network.tf` — VPC, VGW, DX association, route table, security groups, SSM endpoints, IAM, EC2
  - Declare `aws_vpc.this` with `cidr_block = var.aws_vpc_cidr`, `enable_dns_hostnames = true`
  - Declare `aws_subnet.private` with `map_public_ip_on_launch = false`
  - Declare `aws_vpn_gateway.this` attached to VPC
  - Declare `aws_dx_gateway_association.this` with `allowed_prefixes = [var.aws_vpc_cidr]` (AWS VPC CIDR advertised toward GCP)
  - Declare `aws_route_table.private` with route `gcp_vpc_cidr → VGW`
  - Declare `aws_security_group.ec2` (ICMP + SSH from `gcp_vpc_cidr`)
  - Declare `aws_security_group.vpc_endpoints` (HTTPS from `aws_vpc_cidr`)
  - Declare VPC interface endpoints: `ssm`, `ssmmessages`, `ec2messages`
  - Declare IAM role, policy attachment (`AmazonSSMManagedInstanceCore`), instance profile
  - Declare `data.aws_ami.amazon_linux_2023` and `aws_instance.this` (t3.micro, SSM profile, no key_name)
  - Apply tags to all taggable resources
  - _Requirements: 3.1–3.11_

- [x] 5. Rewrite `gcp-network.tf` — VPC, subnet, firewalls, TLS key, GCE VM
  - Declare `google_compute_network.this` with `auto_create_subnetworks = false`
  - Declare `google_compute_subnetwork.private` with `ip_cidr_range = var.gcp_vpc_cidr`
  - Declare `google_compute_firewall.allow_aws` (ICMP + SSH from `aws_vpc_cidr`)
  - Declare `google_compute_firewall.allow_iap_ssh` (TCP/22 from `35.235.240.0/20`)
  - Declare `tls_private_key.gce` (ED25519) for auto-generated SSH key pair
  - Declare `data.google_compute_image.debian` (debian-12, debian-cloud)
  - Declare `google_compute_instance.this` (e2-micro, no external IP, ssh-keys from `tls_private_key.gce.public_key_openssh`, enable-oslogin FALSE, labels)
  - _Requirements: 4.1–4.8_

- [x] 6. Rewrite `outputs.tf` — walkthrough and connectivity test outputs
  - Walkthrough outputs: `aws_dx_gateway_id`, `aws_allowed_prefix_for_gcp`, `gcp_advertised_routes_for_transport`, `gcp_vpc_network_name`, `gcp_transport_name`, `aws_region`, `gcp_region`, `gcp_project_id`
  - Connectivity test outputs: `aws_instance_id`, `aws_instance_private_ip`, `gce_instance_name`, `gce_instance_zone`, `gce_instance_private_ip`, `gce_ssh_private_key` (sensitive), `gce_ssh_public_key`, `aws_vpc_id`, `gcp_network_self_link`
  - _Requirements: 6.1–6.9_

- [x] 7. Rewrite `terraform.tfvars` with new variable placeholders
  - Add all 8 variables with `# REPLACE` annotations (no `gcp_ssh_public_key` — key is auto-generated)
  - Group by: region pairing, AWS network, GCP network
  - Include comments explaining region pairing and advertised routes
  - _Requirements: 7.5_

- [x] 8. Final validation
  - Run `terraform validate` — must pass
  - Run `terraform fmt -check` — must pass
  - Confirm no `modules/` directory, no `gcp-interconnect.tf`
  - Confirm `aws-interconnect.tf` contains only `aws_dx_gateway.this`
  - Confirm `versions.tf` declares `hashicorp/tls ~> 4.0` in addition to `hashicorp/aws` and `hashicorp/google`
  - Confirm `.gitignore` includes `demo-gce-key` and `demo-gce-key.pub`
  - _Requirements: 7.1–7.7_

## Notes

- All tasks are marked complete — the implementation was done outside Kiro and then the spec was retroactively aligned.
- The Interconnect link (Steps 3–5 in README) is created manually via AWS console and `gcloud beta`. When `aws_interconnect_connection` lands in the Terraform AWS provider ([issue #47458](https://github.com/hashicorp/terraform-provider-aws/issues/47458)), tasks can be added to bring those steps into Terraform.
- `allowed_prefixes` carries `aws_vpc_cidr` (not `gcp_vpc_cidr`). This is the correct direction for multicloud Interconnect — the DX Gateway association advertises what AWS has toward GCP.
- The `.kiro/steering/interconnect-context.md` file was updated outside this spec to reflect the multicloud model.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1", "3"] },
    { "id": 1, "tasks": ["2", "4", "5"] },
    { "id": 2, "tasks": ["6", "7"] },
    { "id": 3, "tasks": ["8"] }
  ]
}
```
