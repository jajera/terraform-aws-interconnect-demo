# Design Document — Private Connectivity Demo (Scenario 1)

## Overview

This document describes the architecture and implementation of the **Private Connectivity Baseline** demo using **AWS Interconnect – multicloud (Free Tier)**. Two compute instances — an EC2 (Amazon Linux 2023) in a private AWS subnet and a GCE VM (Debian 12) in a private GCP subnetwork — reach each other over ICMP and SSH exclusively through the managed Interconnect path with no public internet routing.

**Key design decisions:**

- **AWS Interconnect multicloud, not legacy Direct Connect VIF.** The new product (GA May 2026) provides a managed Layer 3 connection between AWS and GCP regions with a Free Tier (500 Mbps, one per AWS region per CSP). No colocation cross-connect is required. The Terraform provider does not yet have `aws_interconnect_connection`; the link is created manually via AWS console + `gcloud beta`.
- **`gcp-interconnect.tf` removed.** The GCP-side BGP primitives (`google_compute_router`, `google_compute_interconnect_attachment`, `google_compute_router_peer`) belong to the classic DEDICATED model. The multicloud pattern uses a GCP transport and VPC peering instead — both created outside Terraform.
- **SSM Session Manager instead of EC2 key pair.** The EC2 instance has no public IP and no `key_name`. Access uses VPC interface endpoints for `ssm`, `ssmmessages`, `ec2messages` and an IAM instance profile with `AmazonSSMManagedInstanceCore`.
- **IAP tunnel for GCE SSH.** The GCE VM has no external IP. Access uses `gcloud compute ssh --tunnel-through-iap`; a dedicated firewall rule allows TCP/22 from `35.235.240.0/20`.
- **`allowed_prefixes` carries the AWS VPC CIDR** (not the GCP CIDR). In the multicloud model, the DX Gateway association's `allowed_prefixes` advertises the AWS side's routes toward GCP.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ AWS (e.g. us-east-1)                    GCP (e.g. us-east4)                 │
│                                                                              │
│  EC2 t3.micro (AL2023)                  GCE e2-micro (Debian 12)            │
│  private subnet (10.0.1.0/24)           private subnet (10.1.0.0/16)        │
│       │                                      │                              │
│  VPC route: GCP CIDR → VGW              VPC peering to transport            │
│       │                                 (--import/export-custom-routes)     │
│  Virtual Private Gateway (VGW)               │                              │
│       │                                 Transport managed VPC               │
│  DX Gateway Association                      │                              │
│  allowed_prefixes = [aws_vpc_cidr]      gcloud beta transports create       │
│       │                                 --activation-key=<from console>      │
│  Direct Connect Gateway ◄──── AWS Interconnect multicloud ──────────────►  │
│  (Terraform)              (AWS console, Step 3)              (gcloud, Step 4)│
└─────────────────────────────────────────────────────────────────────────────┘

Traffic path (AWS → GCP):
  EC2 → VGW → DX Gateway → Interconnect → Transport → VPC peering → GCE VM
```

---

## Component Breakdown

### 1. Variables (`variables.tf`)

| Variable | Type | Validated | Purpose |
|---|---|---|---|
| `aws_region` | string | — | AWS region |
| `gcp_region` | string | — | GCP region (paired with aws_region) |
| `gcp_project_id` | string | regex | GCP project ID |
| `gcp_transport_name` | string | — | Name for gcloud transport resource (default: `demo-interconnect-transport`) |
| `aws_vpc_cidr` | string | CIDR | AWS VPC CIDR; advertised toward GCP via DX association `allowed_prefixes` |
| `aws_subnet_cidr` | string | CIDR | AWS private subnet |
| `aws_dx_gateway_asn` | number | — | Amazon-side BGP ASN for the DX Gateway |
| `gcp_vpc_cidr` | string | CIDR | GCP subnet CIDR; passed to transport `--advertised-routes` |

**Auto-generated (not a variable):**
- `tls_private_key.gce` (ED25519) — Terraform generates an SSH key pair; public half injected into GCE metadata, private half exposed as a sensitive output for `gcloud compute ssh --ssh-key-file`.

**Removed from original design:** `connection_bandwidth`, `vlan_id`, `bgp_asn`, `bgp_auth_key`, `interconnect_type`, `vlan_tag`, `gcp_bgp_asn`, `advertised_route_priority`, `instance_key_name`, `gcp_ssh_public_key` — none apply to the multicloud pattern or have been replaced by auto-generated resources.

---

### 2. `aws-interconnect.tf` — DX Gateway only

```hcl
resource "aws_dx_gateway" "this" {
  name            = "demo-dx-gateway"
  amazon_side_asn = var.aws_dx_gateway_asn
}
```

This is the **only** resource in this file. The physical Interconnect connection and any VIF-level resources are outside Terraform scope for this demo.

---

### 3. `aws-network.tf` — AWS networking, SSM, and compute

```
aws_vpc.this                             cidr = var.aws_vpc_cidr, dns_hostnames = true
  aws_subnet.private                     cidr = var.aws_subnet_cidr, no public IP
  aws_vpn_gateway.this                   VPC attachment
    aws_dx_gateway_association.this      dx_gateway ↔ VGW; allowed_prefixes = [aws_vpc_cidr]
  aws_route_table.private                route gcp_vpc_cidr → VGW
    aws_route_table_association.private

  aws_security_group.ec2                 ingress ICMP + TCP/22 from gcp_vpc_cidr
  aws_security_group.vpc_endpoints       ingress TCP/443 from aws_vpc_cidr (SSM endpoints)

  aws_vpc_endpoint.ssm                   Interface endpoint for SSM
  aws_vpc_endpoint.ssmmessages           Interface endpoint for SSM messages
  aws_vpc_endpoint.ec2messages           Interface endpoint for EC2 messages

data.aws_iam_policy_document.ec2_assume_role
aws_iam_role.ec2_ssm                     ec2.amazonaws.com assume role
  aws_iam_role_policy_attachment.ec2_ssm AmazonSSMManagedInstanceCore
aws_iam_instance_profile.ec2_ssm

data.aws_ami.amazon_linux_2023           most_recent, owners = ["amazon"], al2023-ami-*-x86_64
aws_instance.this                        t3.micro, private subnet, SSM profile, no key_name
```

**Tags** applied to all taggable resources:
```hcl
tags = {
  Project     = "terraform-aws-interconnect-demo"
  Environment = "demo"
  ManagedBy   = "Terraform"
}
```

**Key difference from original design:** `aws_dx_gateway_association.allowed_prefixes` now carries `[var.aws_vpc_cidr]` (not `[var.gcp_vpc_cidr]`). In the multicloud model, the association advertises what AWS has (the AWS VPC CIDR) toward the GCP transport.

---

### 4. `gcp-network.tf` — GCP networking and compute

```
google_compute_network.this              auto_create_subnetworks = false
  google_compute_subnetwork.private      ip_cidr_range = gcp_vpc_cidr, region = gcp_region
  google_compute_firewall.allow_aws      INGRESS; source = aws_vpc_cidr; ICMP + TCP/22; tag demo-instance
  google_compute_firewall.allow_iap_ssh  INGRESS; source = 35.235.240.0/20; TCP/22; tag demo-instance

tls_private_key.gce                      algorithm = ED25519 (auto-generated SSH key pair)
data.google_compute_image.debian         family = debian-12, project = debian-cloud
google_compute_instance.this             e2-micro, zone = gcp_region-b, tag demo-instance
  network_interface                      subnetwork = google_compute_subnetwork.private (no accessConfig = no external IP)
  metadata                               ssh-keys = "debian:${tls_private_key.gce.public_key_openssh}", enable-oslogin = FALSE
  labels                                 project, environment, managed_by = terraform
```

**`gcp-interconnect.tf` does not exist** — Cloud Router, VLAN attachment, and BGP peer are not provisioned in this demo.

**SSH key flow:** Terraform generates the key pair at plan/apply time. The public key is injected into GCE metadata. The private key is exposed as `gce_ssh_private_key` (sensitive output) — the operator saves it locally and passes it to `gcloud compute ssh --ssh-key-file=demo-gce-key`. Both key files are gitignored.

---

### 5. `outputs.tf` — walkthrough and test support

Outputs are grouped into two purposes:

**Walkthrough support (Steps 3–5):**
```hcl
output "aws_dx_gateway_id"                  # Select in AWS console Step 3
output "aws_allowed_prefix_for_gcp"         # Informational — aws_vpc_cidr
output "gcp_advertised_routes_for_transport" # Pass to --advertised-routes Step 4
output "gcp_vpc_network_name"               # Pass to --network Steps 4–5
output "gcp_transport_name"                 # Transport resource name Steps 4–5
output "aws_region"                         # For CLI commands
output "gcp_region"
output "gcp_project_id"
```

**Connectivity tests (Step 7):**
```hcl
output "aws_instance_id"           # aws ssm start-session --target
output "aws_instance_private_ip"   # GCP-side ping target
output "gce_instance_name"         # gcloud compute ssh name
output "gce_instance_zone"         # gcloud compute ssh --zone
output "gce_instance_private_ip"   # AWS-side ping target
output "gce_ssh_private_key"       # sensitive — save to demo-gce-key for --ssh-key-file
output "gce_ssh_public_key"        # save to demo-gce-key.pub (same key installed on VM)
output "aws_vpc_id"
output "gcp_network_self_link"
```

---

## Data Flow

1. `terraform apply` creates AWS VPC, VGW, DX Gateway, DX Gateway Association (pending), EC2; GCP VPC, subnet, firewall rules, GCE VM.
2. **AWS console (Step 3):** operator creates multicloud Interconnect using `aws_dx_gateway_id` output → receives activation key.
3. **gcloud (Step 4):** operator runs `gcloud beta network-connectivity transports create` with activation key and `gcp_advertised_routes_for_transport` → transport created, GCP routes toward AWS VPC CIDR installed.
4. **gcloud (Step 5):** operator peers workload VPC (`gcp_vpc_network_name`) to transport's `peeringNetwork` with `--import-custom-routes --export-custom-routes` → routes flow between workload VMs and AWS.
5. DX Gateway association transitions from PENDING to ASSOCIATED.
6. AWS route table static entry (`gcp_vpc_cidr → VGW`) + GCP peering routes = full private path.
7. Operator runs connectivity tests via SSM (EC2) and IAP tunnel (GCE).

---

## Error Handling and Edge Cases

| Scenario | Handling |
|---|---|
| Invalid CIDR | Terraform validation fails pre-plan |
| `aws_dx_gateway_association` stuck PENDING | Normal until Interconnect created (Steps 3–4); not a Terraform error |
| Wrong region pair | `remote-profiles list` returns empty; transport creation fails — check README region pairing table |
| SSM session fails | VPC endpoints may take 2–3 min to become available after apply; verify IAM role attachment |
| GCE IAP SSH fails | Check firewall `allow_iap_ssh` rule exists; verify IAP API enabled in GCP project; confirm `--ssh-key-file=demo-gce-key` uses the Terraform-generated key |
| GCE zone suffix | Defaulted to `${var.gcp_region}-b`; some regions use `-a` or `-c` — verify before deploying |

---

## Correctness Properties

**PBT does not apply.** This feature is entirely declarative HCL and IDE configuration. Correctness is verified through:

- `terraform validate` — schema validity
- `terraform fmt -check` — formatting
- `terraform plan` output assertions — resource presence, attribute values, tags/labels
- Manual Step 7 connectivity test — ICMP/SSH success confirms end-to-end path
