---
inclusion: manual
---

# AWS Interconnect Multicloud + GCP Domain Context

This steering file applies when working on **AWS Interconnect – multicloud** (Free Tier or paid) with **Google Cloud Partner Cross-Cloud Interconnect**. It replaces the older colocation-based Direct Connect + GCP Dedicated Cloud Interconnect model.

---

## Product model

- **AWS Interconnect – multicloud** is a managed Layer 3 connection between an AWS region and a partner CSP region. It lives under **Direct Connect** in the AWS console.
- **Free Tier:** one **500 Mbps** local interconnect per AWS region per CSP at no AWS charge ([pricing](https://aws.amazon.com/interconnect/multicloud/pricing/)).
- **GCP side:** Partner Cross-Cloud Interconnect implemented as a **`google_network_connectivity_transport`** (created via `gcloud beta`, not classic `google_compute_interconnect_attachment` DEDICATED).
- **No colocation cross-connect** is required — AWS and GCP maintain the underlying link.

---

## Architecture primitives

| Side | Component | Purpose |
|---|---|---|
| AWS | Direct Connect Gateway | Interconnect attach point; created in Terraform |
| AWS | Virtual Private Gateway (VGW) | VPC-side gateway; associated with DX Gateway |
| AWS | `allowed_prefixes` on DX association | **AWS VPC CIDR** advertised toward GCP |
| GCP | Workload VPC + subnet | Hosts demo GCE VM (Terraform) |
| GCP | Transport | Cross-cloud link; created with AWS **activation key** |
| GCP | VPC peering | Peers workload VPC to transport `peeringNetwork` |

**Never** model this demo with `aws_dx_connection` + private VIF to a colo port unless explicitly building the legacy pattern.

---

## Region pairing

Interconnect is region-to-region. Supported pairs: [AWS regional availability](https://docs.aws.amazon.com/interconnect/latest/userguide/region-availability.html).

Example pairs:

- `ap-southeast-1` ↔ `asia-southeast1` (APAC — **not** `ap-southeast-2` Sydney)
- `us-east-1` ↔ `us-east4`
- `eu-central-1` ↔ `europe-west3`

List GCP remote profiles before choosing regions:

```bash
gcloud beta network-connectivity transports remote-profiles list --region=<gcp-region>
```

---

## Terraform scope in this repository

**In Terraform:** AWS VPC, VGW, DX Gateway, association, EC2; GCP VPC, subnet, firewall, GCE.

**Outside Terraform (documented in README):**

1. AWS console — create multicloud Interconnect (Free Tier 500 Mbps)
2. `gcloud beta` — create transport with activation key
3. `gcloud` — VPC peering with `--import-custom-routes` and `--export-custom-routes`

`aws_interconnect_connection` is tracked in [terraform-provider-aws#47458](https://github.com/hashicorp/terraform-provider-aws/issues/47458) but not yet available in the stable provider.

---

## Imperative directives

- **Never use `aws_dx_connection` or `aws_dx_private_virtual_interface` for this multicloud demo** — those resources target physical Direct Connect ports, not Interconnect multicloud.
- **Never use `google_compute_interconnect_attachment` with `type = "DEDICATED"`** unless provisioning a physical Google Cloud Interconnect at a colo facility.
- **Always advertise `aws_vpc_cidr` in `allowed_prefixes`** on the DX Gateway association (AWS → GCP direction).
- **Always pass `gcp_vpc_cidr` to transport `--advertised-routes`** (GCP → AWS direction).
- **Always enable custom route import/export** on GCP VPC peering to the transport network.
- **Never use VLAN 1** if you encounter VLAN settings in partner documentation; use 2–4094.

---

## Access patterns for private instances

- **AWS EC2:** no public IP — use **SSM Session Manager** (VPC endpoints for `ssm`, `ssmmessages`, `ec2messages` in this repo).
- **GCE:** no external IP — use **`gcloud compute ssh --tunnel-through-iap`** with firewall allowing `35.235.240.0/20` on TCP/22.

---

## Teardown order

1. Delete GCP VPC peering  
2. Delete GCP transport  
3. Delete AWS multicloud Interconnect (console)  
4. `terraform destroy`

Deleting Terraform resources first leaves orphaned interconnect billing and broken associations.
