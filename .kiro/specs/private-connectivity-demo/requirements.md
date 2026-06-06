# Requirements Document

## Introduction

This feature extends the Terraform foundation into a fully-runnable **Private Connectivity Baseline** demo using **AWS Interconnect – multicloud (Free Tier)**. The goal is to prove end-to-end private IP reachability between an EC2 instance in a private AWS subnet and a GCE VM in a private GCP subnetwork, with no public internet routing and no colocation cross-connect required.

Terraform provisions the supporting network and compute on both clouds. The multicloud Interconnect link itself is created through the AWS console and `gcloud beta` (documented in README.md), because `aws_interconnect_connection` is not yet available in the stable `hashicorp/aws` provider.

## Glossary

- **AWS Interconnect multicloud**: Managed Layer 3 connection between an AWS region and a GCP region. Free Tier provides one 500 Mbps connection per AWS region per CSP at no AWS charge.
- **DX Gateway**: The `aws_dx_gateway` resource — the AWS-side attach point when creating the multicloud Interconnect in the AWS console.
- **VGW**: AWS Virtual Private Gateway — attached to the AWS VPC and associated with the DX Gateway via `aws_dx_gateway_association`.
- **Transport**: GCP-side Partner Cross-Cloud Interconnect resource created with `gcloud beta network-connectivity transports create`. Contains a `peeringNetwork` that workload VPCs peer against.
- **VPC Peering**: GCP network peering between the workload VPC and the transport's `peeringNetwork`, with `--import-custom-routes` and `--export-custom-routes` enabled.
- **SSM Session Manager**: AWS Systems Manager feature allowing shell access to EC2 instances without a public IP, bastion host, or open SSH port, via VPC interface endpoints.
- **IAP Tunnel**: GCP Identity-Aware Proxy tunnel allowing SSH to GCE instances without an external IP, using the reserved range `35.235.240.0/20`.
- **AMI Data Source**: `data.aws_ami` — queries AWS for the latest Amazon Linux 2023 AMI at plan time.
- **Debian Image Data Source**: `data.google_compute_image` — queries GCP for the latest Debian 12 image at plan time.
- **CIDR**: Classless Inter-Domain Routing notation, validated by pattern `^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$`.

---

## Requirements

### Requirement 1 — Variable Definitions

**User Story:** As a platform engineer, I want a clean set of input variables for both clouds, so that I can configure regions, CIDRs, ASNs, and access keys without modifying resource files.

#### Acceptance Criteria

1. THE Terraform configuration SHALL declare `aws_region` (string), `gcp_region` (string), `gcp_project_id` (string, validated against `^[a-z][a-z0-9\-]{4,28}[a-z0-9]$`), and `gcp_transport_name` (string, default `"demo-interconnect-transport"`) as general variables.
2. THE Terraform configuration SHALL declare `aws_vpc_cidr` (string, CIDR validation), `aws_subnet_cidr` (string, CIDR validation), and `aws_dx_gateway_asn` (number) as AWS network variables.
3. THE Terraform configuration SHALL declare `gcp_vpc_cidr` (string, CIDR validation) as the only GCP network variable. SSH access to the GCE VM SHALL use a Terraform-generated `tls_private_key` resource instead of a user-supplied variable.
4. THE Terraform configuration SHALL NOT declare `connection_bandwidth`, `vlan_id`, `bgp_asn`, `bgp_auth_key`, `interconnect_type`, `vlan_tag`, `gcp_bgp_asn`, `advertised_route_priority`, `instance_key_name`, or `gcp_ssh_public_key` — these variables belong to the legacy Direct Connect VIF model or have been replaced by auto-generated resources.
5. WHEN `aws_vpc_cidr`, `aws_subnet_cidr`, or `gcp_vpc_cidr` receives a value not matching the CIDR pattern, THEN THE Terraform configuration SHALL emit a validation error and refuse to apply.

---

### Requirement 2 — AWS Interconnect Layer (`aws-interconnect.tf`)

**User Story:** As a network engineer, I want a minimal AWS interconnect file that provisions only the DX Gateway, so that the file clearly represents the Terraform-managed attach point without including resources that belong to the manual console workflow.

#### Acceptance Criteria

1. THE `aws-interconnect.tf` file SHALL declare exactly one resource: `aws_dx_gateway.this` with `amazon_side_asn = var.aws_dx_gateway_asn`.
2. THE `aws-interconnect.tf` file SHALL NOT declare `aws_dx_connection`, `aws_dx_private_virtual_interface`, or any other resource — the physical connection is created outside Terraform.

---

### Requirement 3 — AWS Network Infrastructure (`aws-network.tf`)

**User Story:** As a network engineer, I want all AWS VPC, routing, security, SSM, and compute resources in one file, so that the AWS workload layer is fully self-contained.

#### Acceptance Criteria

1. THE `aws-network.tf` file SHALL declare `aws_vpc.this` with `cidr_block = var.aws_vpc_cidr` and `enable_dns_hostnames = true`.
2. THE `aws-network.tf` file SHALL declare `aws_subnet.private` with `cidr_block = var.aws_subnet_cidr` and `map_public_ip_on_launch = false`.
3. THE `aws-network.tf` file SHALL declare `aws_vpn_gateway.this` attached to the VPC.
4. THE `aws-network.tf` file SHALL declare `aws_dx_gateway_association.this` linking `aws_dx_gateway.this` to the VGW, with `allowed_prefixes = [var.aws_vpc_cidr]` — the AWS VPC CIDR is what is advertised toward GCP.
5. THE `aws-network.tf` file SHALL declare `aws_route_table.private` with a route for `var.gcp_vpc_cidr` via the VGW, and `aws_route_table_association.private` binding it to the private subnet.
6. THE `aws-network.tf` file SHALL declare `aws_security_group.ec2` allowing ingress ICMP and TCP/22 from `var.gcp_vpc_cidr`, and `aws_security_group.vpc_endpoints` allowing HTTPS (TCP/443) from `var.aws_vpc_cidr` for SSM endpoint traffic.
7. THE `aws-network.tf` file SHALL declare three VPC interface endpoints — `aws_vpc_endpoint.ssm`, `aws_vpc_endpoint.ssmmessages`, `aws_vpc_endpoint.ec2messages` — enabling SSM Session Manager access from the private subnet without a NAT gateway or public IP.
8. THE `aws-network.tf` file SHALL declare `data.aws_iam_policy_document.ec2_assume_role`, `aws_iam_role.ec2_ssm`, `aws_iam_role_policy_attachment.ec2_ssm` (attaching `AmazonSSMManagedInstanceCore`), and `aws_iam_instance_profile.ec2_ssm` to allow the EC2 instance to register with SSM.
9. THE `aws-network.tf` file SHALL declare `data "aws_ami" "amazon_linux_2023"` selecting the most recent Amazon Linux 2023 AMI (`al2023-ami-*-x86_64`) owned by Amazon.
10. THE `aws-network.tf` file SHALL declare `aws_instance.this` of type `t3.micro` in the private subnet, using `iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name` and WITHOUT a `key_name` attribute — access is via SSM only.
11. WHEN any taggable resource in `aws-network.tf` is created, THE Terraform configuration SHALL apply `tags` containing `Project`, `Environment`, and `ManagedBy = "Terraform"`.

---

### Requirement 4 — GCP Network Infrastructure (`gcp-network.tf`)

**User Story:** As a network engineer, I want all GCP VPC, firewall, and compute resources in one file, so that the GCP workload layer is fully self-contained.

#### Acceptance Criteria

1. THE `gcp-network.tf` file SHALL declare `google_compute_network.this` with `auto_create_subnetworks = false`.
2. THE `gcp-network.tf` file SHALL declare `google_compute_subnetwork.private` with `ip_cidr_range = var.gcp_vpc_cidr` in `var.gcp_region`.
3. THE `gcp-network.tf` file SHALL declare `google_compute_firewall.allow_aws` allowing ingress ICMP and TCP/22 from `var.aws_vpc_cidr`, targeting instances with tag `demo-instance`.
4. THE `gcp-network.tf` file SHALL declare `google_compute_firewall.allow_iap_ssh` allowing ingress TCP/22 from `35.235.240.0/20` (Google IAP range), targeting instances with tag `demo-instance`, so the GCE VM is reachable via `gcloud compute ssh --tunnel-through-iap`.
5. THE `gcp-network.tf` file SHALL declare a `tls_private_key.gce` resource (algorithm `ED25519`) to auto-generate an SSH key pair for the GCE instance, eliminating the need for a user-supplied `gcp_ssh_public_key` variable.
6. THE `gcp-network.tf` file SHALL declare `data "google_compute_image" "debian"` selecting the `debian-12` family from `debian-cloud`.
7. THE `gcp-network.tf` file SHALL declare `google_compute_instance.this` of machine type `e2-micro` in zone `"${var.gcp_region}-b"`, with no external IP, SSH metadata using `tls_private_key.gce.public_key_openssh`, `enable-oslogin = "FALSE"`, and network tag `demo-instance`.
8. WHEN `google_compute_instance.this` is created, THE Terraform configuration SHALL apply `labels` containing `project`, `environment`, and `managed_by = "terraform"`.

---

### Requirement 5 — `gcp-interconnect.tf` removed

**User Story:** As a maintainer, I want the repository to reflect the actual implementation, so that there are no stale files referencing resources that no longer exist.

#### Acceptance Criteria

1. THE repository SHALL NOT contain a `gcp-interconnect.tf` file — `google_compute_router`, `google_compute_interconnect_attachment`, and `google_compute_router_peer` are not provisioned by Terraform in the multicloud Interconnect pattern used by this demo.

---

### Requirement 6 — Output Values (`outputs.tf`)

**User Story:** As a demo operator, I want outputs that provide all values needed for the manual walkthrough steps (Steps 3–5) and connectivity tests (Step 7), so that I can copy-paste commands directly from `terraform output`.

#### Acceptance Criteria

1. THE `outputs.tf` file SHALL declare `aws_dx_gateway_id` (value: `aws_dx_gateway.this.id`) for use in the AWS console when creating the multicloud Interconnect.
2. THE `outputs.tf` file SHALL declare `aws_allowed_prefix_for_gcp` (value: `var.aws_vpc_cidr`) as the CIDR to advertise toward GCP.
3. THE `outputs.tf` file SHALL declare `gcp_advertised_routes_for_transport` (value: `var.gcp_vpc_cidr`) for use with `--advertised-routes` in the `gcloud` transport command.
4. THE `outputs.tf` file SHALL declare `gcp_vpc_network_name` (value: `google_compute_network.this.name`) for use in `gcloud` transport and peering commands.
5. THE `outputs.tf` file SHALL declare `gcp_transport_name` (value: `var.gcp_transport_name`) for use in `gcloud` commands.
6. THE `outputs.tf` file SHALL declare `aws_region`, `gcp_region`, `gcp_project_id` for use in CLI commands without needing to reference `terraform.tfvars` directly.
7. THE `outputs.tf` file SHALL declare `aws_instance_id` (for SSM `start-session`), `aws_instance_private_ip`, `gce_instance_name`, `gce_instance_zone`, and `gce_instance_private_ip` for connectivity test commands in Step 7.
8. THE `outputs.tf` file SHALL declare `gce_ssh_private_key` (sensitive, value: `tls_private_key.gce.private_key_openssh`) and `gce_ssh_public_key` (value: `tls_private_key.gce.public_key_openssh`) so the operator can save the key pair locally for `gcloud compute ssh --ssh-key-file`.
9. THE `outputs.tf` file SHALL declare `aws_vpc_id` and `gcp_network_self_link` as general network identifiers.

---

### Requirement 7 — Structural Consistency

**User Story:** As a maintainer, I want the repository layout to remain flat and convention-compliant, so that the codebase is uniform with the setup spec.

#### Acceptance Criteria

1. All Terraform files SHALL remain at the repository root — no `modules/` or `environments/` subdirectory SHALL exist.
2. `aws-interconnect.tf` SHALL contain only the `aws_dx_gateway` resource.
3. `aws-network.tf` SHALL contain all AWS VPC, routing, security groups, VPC endpoints, IAM, and compute resources.
4. `gcp-network.tf` SHALL contain all GCP network, firewall, and compute resources.
5. `terraform.tfvars` SHALL contain placeholder entries for all declared variables (excluding `gcp_transport_name` which has a default), each annotated with `# REPLACE`.
6. `versions.tf` SHALL declare `required_providers` for `hashicorp/aws ~> 5.0`, `hashicorp/google ~> 5.0`, and `hashicorp/tls ~> 4.0`.
7. `.gitignore` SHALL include entries for `demo-gce-key` and `demo-gce-key.pub` (Terraform-generated SSH keys saved locally during Step 7).
