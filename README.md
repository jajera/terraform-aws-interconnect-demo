# terraform-aws-interconnect-demo

A hands-on demo for **private IP connectivity between AWS and Google Cloud** using [**AWS Interconnect – multicloud**](https://aws.amazon.com/interconnect/multicloud/) to Google Cloud Partner Cross-Cloud Interconnect.

Step 3 uses **AWS Interconnect – multicloud** (paid, **1 Gbps**) in this walkthrough — the default for accounts that have already consumed the [Free Tier](https://aws.amazon.com/about-aws/whats-new/2026/05/aws-interconnect-multicloud-offers-free-500-mbps-tier/) (one free 500 Mbps interconnect per AWS Region per CSP). Free Tier remains an option if your account still has quota; see [Cost estimate](#cost-estimate).

Terraform provisions the **supporting network and compute** on both clouds. The **multicloud Interconnect link itself** is created through the **AWS console** and **gcloud** — AWS provider support for `aws_interconnect_connection` is still in progress ([terraform-provider-aws#47458](https://github.com/hashicorp/terraform-provider-aws/issues/47458)).

---

## What this demo proves

After completing every step, an EC2 instance in a **private** AWS subnet and a GCE VM in a **private** GCP subnetwork can reach each other over **ICMP and SSH** entirely through the managed Interconnect path — no public internet, no colocation cross-connect, no VPN.

---

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ AWS (e.g. ap-southeast-1)               GCP (e.g. asia-southeast1)               │
│                                                                              │
│  EC2 (private subnet)                   GCE VM (private subnet)              │
│       │                                      │                               │
│  VPC route: GCP CIDR → VGW              VPC peering (Step 5)                 │
│       │                                      │                               │
│  Virtual Private Gateway                Workload VPC (Terraform)             │
│       │                                      │                               │
│  DX Gateway Association                 Transport managed VPC                │
│  (advertises AWS CIDR)                       │                               │
│       │                                      │                               │
│  Direct Connect Gateway ◄──── AWS Interconnect multicloud ────► Transport   │
│  (Terraform)              (console, Step 3)              (gcloud, Step 4)    │
└──────────────────────────────────────────────────────────────────────────────┘

Traffic path (AWS → GCP):
  EC2 → VGW → DX Gateway → Interconnect → GCP Transport → VPC peering → GCE VM
```

### Managed by Terraform

| Resource | Purpose |
|---|---|
| `aws_dx_gateway` | Attach point for the multicloud Interconnect (console Step 3) |
| `aws_vpc`, subnet, VGW, route table | AWS workload network |
| `aws_dx_gateway_association` | Links VGW to DX Gateway; advertises `aws_vpc_cidr` toward GCP |
| `aws_instance` + SSM | Demo EC2 in a private subnet (reachable via Session Manager) |
| VPC interface endpoints | SSM connectivity without a bastion or NAT |
| `google_compute_network`, subnet, firewall | GCP workload network |
| `google_compute_instance` | Demo GCE VM (reachable via IAP tunnel SSH) |

### Created manually (documented below)

| Step | Tool | Resource |
|---|---|---|
| 3 | AWS console | **AWS Interconnect – multicloud** (1 Gbps) → activation key |
| 4 | `gcloud beta` | **Partner Cross-Cloud Interconnect transport** |
| 5 | `gcloud` | **VPC network peering** (workload VPC ↔ transport peering network) |

---

## Prerequisites

### Accounts and permissions

- **AWS account** with permissions for Direct Connect, EC2, VPC, IAM, and **AWS Interconnect – multicloud**
- **GCP project** with billing enabled and these APIs enabled:
  - Compute Engine API
  - **Network Connectivity API** (`networkconnectivity.googleapis.com`)

```bash
gcloud services enable compute.googleapis.com networkconnectivity.googleapis.com \
  --project=YOUR_GCP_PROJECT_ID
```

### Tools

| Tool | Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5.0 | Base infrastructure |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2 **≥ 2.34.43** | SSM sessions; **`aws interconnect`** status checks (older builds lack this namespace) |
| [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) | latest | Transport + peering (beta commands) |
| [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | latest | SSH-less EC2 access |

### Authentication

```bash
# AWS
aws sts get-caller-identity

# GCP — Terraform uses Application Default Credentials (ADC)
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
gcloud auth application-default set-quota-project YOUR_GCP_PROJECT_ID
```

Terraform and the Google provider read credentials from ADC, not from `gcloud config`. After `gcloud config set project`, align the ADC **quota project** to the same GCP project — otherwise you may see a mismatch warning and hit unexpected quota/billing issues:

```text
WARNING: Your active project does not match the quota project in your local Application Default Credentials file.
```

Run `set-quota-project` whenever you switch GCP projects for this demo.

### Cost estimate

Costs depend on how far you take the demo and whether you use **Free Tier** or **paid** multicloud on AWS. GCP bills its Partner Cross-Cloud transport independently on both paths ([AWS pricing](https://aws.amazon.com/interconnect/multicloud/pricing/), [GCP interconnect pricing](https://cloud.google.com/network-connectivity/docs/interconnect/pricing/)).

> **This walkthrough assumes paid multicloud (1 Gbps)** — typical when the Free Tier quota is already used in your Region/CSP pair (`ap-southeast-1` → GCP).

#### Terraform only (`terraform apply`, no Steps 3–5)

| Resource | Approx. monthly (24/7) | Approx. 4 hours |
|---|---|---|
| 3 VPC interface endpoints (SSM, one AZ) | ~$22 | ~$0.12 |
| EC2 `t3.micro` | ~$7.60 | ~$0.04 |
| GCE `e2-micro` in `asia-southeast1` | ~$6 | ~$0.04 |
| VPC, DX Gateway, VGW, routes, firewall, IAM | $0 | $0 |
| **Total** | **~$30–40/month** | **~$0.20–0.50** |

VPC endpoints are the main AWS cost — they enable SSM from a private subnet without a NAT gateway.

#### Full demo — paid multicloud (Terraform + Steps 3–7, 1 Gbps, Tier 1)

| Resource | Approx. monthly (24/7) | Approx. 4 hours |
|---|---|---|
| Terraform base (above) | ~$30–40 | ~$0.25 |
| AWS Interconnect — multicloud (1 Gbps, Tier 1, APAC) | ~$1,000 | ~$5.50 |
| GCP Partner Cross-Cloud transport (APAC, 1 Gbps) | ~$3,650 | ~$20 |
| Data transfer over the transport | $0 (GCP transport) | $0 |
| **Total** | **~$4,680+/month** | **~$26–30** |

#### Full demo — Free Tier (500 Mbps, if quota available)

| Resource | Approx. monthly (24/7) | Approx. 4 hours |
|---|---|---|
| Terraform base (above) | ~$30–40 | ~$0.25 |
| AWS Interconnect — Free Tier (500 Mbps, Tier 1) | $0 | $0 |
| GCP Partner Cross-Cloud transport (APAC) | ~$3,650 | ~$20 |
| **Total** | **~$3,680+/month** | **~$20–21** |

> **Important:** GCP transport pricing is hourly (~$5.00/hr for the lowest listed APAC tier). AWS paid interconnect adds ~$1.37/hr at Tier 1 / 1 Gbps. Tear down interconnect resources **before** `terraform destroy` (see [Teardown](#teardown-order-matters)).

#### Keeping costs low

1. **Infra exploration only** — run `terraform apply` and skip Steps 3–5; destroy when done.
2. **Full connectivity test (paid)** — budget ~$26–30 for a ~4-hour session; delete peering, transport, and AWS interconnect promptly.
3. **Do not leave the interconnect or GCP transport running overnight** — GCP transport dominates; paid AWS adds ~$33/day at 1 Gbps.
4. **Free Tier** — one free 500 Mbps interconnect per AWS Region per CSP; if already used, select **AWS Interconnect – multicloud** (paid) instead ([terms](https://aws.amazon.com/interconnect/multicloud/pricing/)).

### Region pairing

Interconnect is **region-to-region**. Pick a supported pair before editing `terraform.tfvars`. Authoritative list: [AWS Interconnect regional availability](https://docs.aws.amazon.com/interconnect/latest/userguide/region-availability.html) (GCP mirror: [paired locations](https://cloud.google.com/network-connectivity/docs/interconnect/how-to/partner-cci-for-aws/paired-locations)).

> **Note:** `ap-southeast-2` (Sydney) is **not** a supported Interconnect pair. The nearest APAC option is **`ap-southeast-1` ↔ `asia-southeast1`** (Singapore).

| AWS region | GCP region (paired) |
|---|---|
| `ap-southeast-1` | `asia-southeast1` |
| `us-east-1` | `us-east4` |
| `us-west-2` | `us-west1` |
| `us-west-1` | `us-west2` |
| `eu-west-2` | `europe-west2` |
| `eu-central-1` | `europe-west3` |

List available GCP remote profiles for your target GCP region:

```bash
gcloud beta network-connectivity transports remote-profiles list \
  --region=asia-southeast1
```

---

## Repository layout

```text
terraform-aws-interconnect-demo/
├── versions.tf           # Provider constraints
├── main.tf               # AWS + GCP providers
├── variables.tf          # Input variables
├── outputs.tf            # Values needed for Steps 3–7
├── terraform.tfvars      # Edit before apply
├── aws-interconnect.tf   # Direct Connect Gateway only
├── aws-network.tf        # VPC, VGW, DX association, EC2, SSM endpoints
├── gcp-network.tf        # VPC, subnet, firewall, GCE
├── README.md             # This walkthrough
├── .gitignore            # Ignores state, local tfvars, demo-gce-key*
└── .terraform.lock.hcl
```

Step 7 writes `demo-gce-key` and `demo-gce-key.pub` locally — both are gitignored and must be removed at teardown.

---

## Walkthrough checklist

Track progress. Steps **3–5 are not in Terraform** — they must be **removed manually before `terraform destroy`** or hourly interconnect charges continue.

| Step | What | Tool | In Terraform? | Billable when left running? |
|---|---|---|---|---|
| 1 | Configure `terraform.tfvars` | edit file | — | — |
| 2 | Base infra (VPC, EC2, GCE, DXGW, …) | `terraform apply` | Yes | Yes (~$30–40/mo) |
| 2b | GCP API + service agent (one-time prep) | `gcloud` — see [Step 4 prep](#step-4--create-the-gcp-transport-gcloud) | No | No |
| 2c | Pre-flight: reach each VM locally | SSM (AWS), IAP SSH (GCP) | — | — |
| 3 | AWS Interconnect multicloud (paid **1 Gbps**) | AWS console | No | Yes (~$1.37/hr AWS) |
| 4 | GCP Partner Cross-Cloud **transport** | `gcloud beta` | No | Yes (~$5/hr GCP) |
| 5 | VPC peering (workload ↔ transport network) | `gcloud` | No | No |
| 6 | Verify routing + poll until AWS **Available** | `aws interconnect` / `gcloud` | — | — |
| 7 | Ping EC2 ↔ GCE over interconnect | SSM + IAP | — | — |
| **Teardown** | Delete peering → transport → AWS interconnect → **wait for AWS delete** → **`terraform destroy`** | `gcloud` + CLI/console | Steps 3–5 only | **Stop billing** |

---

## Step 1 — Configure variables

Copy and edit `terraform.tfvars`. Replace every `# REPLACE` value:

```hcl
aws_region = "ap-southeast-1"
gcp_region = "asia-southeast1"

gcp_project_id     = "your-gcp-project-id"
gcp_transport_name = "demo-interconnect-transport"

aws_vpc_cidr       = "10.0.0.0/16"   # advertised toward GCP
aws_subnet_cidr    = "10.0.1.0/24"
aws_dx_gateway_asn = 64512           # private ASN for the DX Gateway

gcp_vpc_cidr = "10.1.0.0/16" # advertised toward AWS
```

Terraform generates an ED25519 SSH key pair for the GCE `debian` user automatically. Retrieve the private key after apply (see Step 7).

**CIDR rules:**

- `aws_vpc_cidr` and `gcp_vpc_cidr` must not overlap.
- `aws_subnet_cidr` must fit inside `aws_vpc_cidr`.
- These CIDRs are exchanged across the Interconnect — keep them stable before Step 3.

---

## Step 2 — Apply Terraform (base infrastructure)

```bash
terraform init
terraform plan
terraform apply
```

Expect roughly **20 resources** (AWS VPC/network/compute/endpoints + GCP network/compute + DX Gateway).

Save the outputs — you will reference them in later steps:

```bash
terraform output
```

Key values:

| Output | Used in |
|---|---|
| `aws_dx_gateway_id` | AWS console Step 3 — select Direct Connect Gateway |
| `aws_allowed_prefix_for_gcp` | Informational — AWS CIDR advertised to GCP |
| `gcp_advertised_routes_for_transport` | gcloud Step 4 — `--advertised-routes` |
| `gcp_vpc_network_name` | gcloud Steps 4–5 — `--network` |
| `gcp_transport_name` | gcloud Steps 4–5 — transport name |
| `aws_instance_private_ip` / `gce_instance_private_ip` | Step 7 — ping targets |

> **Note:** `aws_dx_gateway_association` may show **pending** until Steps 4–5 complete. It can reach **associated** while the interconnect is still **pending** — that is normal and a good sign.

---

## Step 3 — Create the multicloud Interconnect (AWS console)

1. Open the [AWS Interconnect console](https://us-east-1.console.aws.amazon.com/directconnect/v2/home?region=ap-southeast-1#/aws-interconnect) — set `region=` in the URL to your `aws_region` (e.g. `terraform output -raw aws_region`).

2. On the **Connection types** page, select **AWS Interconnect – multicloud** (paid), then **Get started**.

   > Use **AWS Interconnect – multicloud – Free Tier** instead if you still have quota (one free 500 Mbps interconnect per AWS Region per CSP). If Free Tier fails with a billing or “free trial” error, the quota may be exhausted or eligibility checks may block it — **paid multicloud** is the usual fallback.

   > **Cost note:** Paid AWS interconnect is ~**$1.37/hr** at Tier 1 / 1 Gbps (APAC local pair). GCP transport is separate (~**$5/hr**) — see [Cost estimate](#cost-estimate).

3. **Select a provider** — choose **Google Cloud**, then **Next**.

4. **Select regions** — pick your paired regions, then **Next**:

   | Field | Value |
   |---|---|
   | AWS Region | Your `aws_region` (e.g. `ap-southeast-1`) |
   | Google Cloud Region | Your paired `gcp_region` (e.g. `asia-southeast1`) |

5. **Configure options**, then **Next**:

   | Field | Value |
   |---|---|
   | Description | e.g. `demo-interconnect` (lowercase, numbers, hyphens; max 100 chars) |
   | Bandwidth | **1 Gbps** (paid) — or **500 Mbps** on Free Tier |
   | Direct Connect gateway | Select `demo-dx-gateway` — or paste `terraform output -raw aws_dx_gateway_id` if the name differs |
   | Google Cloud project ID | Your `gcp_project_id` (e.g. `prj-core-123456`) |
   | Tags | Optional |

6. **Review** the summary, then **Finish**.

   > **Free Tier only:** If you see `InterconnectValidationException: Unable to create free trial connection`, see [Billing verification failed](#billing-verification-failed-free-tier-only) — or switch to **paid multicloud** (step 2 above).

7. Copy the **activation key** displayed when the request completes — you need it in Step 4.

The Interconnect status stays **Pending** until the GCP transport (Step 4) and peering (Step 5) complete.

---

## Step 4 — Create the GCP transport (gcloud)

Run from Cloud Shell or a machine with `gcloud` authenticated to your GCP project.

### GCP prep (before first `transports create`)

Terraform creates `demo-vpc-network` but **not** the Network Connectivity service agent. Do this once per GCP project:

```bash
export GCP_PROJECT="$(terraform output -raw gcp_project_id)"

gcloud services enable networkconnectivity.googleapis.com --project="$GCP_PROJECT"

# Confirm API is enabled
gcloud services list --enabled --project="$GCP_PROJECT" \
  --filter="name:networkconnectivity.googleapis.com"

# Required if create fails with gcp-sa-networkconnectivity ... Not found
gcloud beta services identity create \
  --service=networkconnectivity.googleapis.com \
  --project="$GCP_PROJECT"
```

Wait 2–5 minutes after `services identity create`, then run the transport create below.

### Create transport

```bash
export GCP_PROJECT="$(terraform output -raw gcp_project_id)"
export GCP_REGION="$(terraform output -raw gcp_region)"
export GCP_NETWORK="$(terraform output -raw gcp_vpc_network_name)"
export TRANSPORT_NAME="$(terraform output -raw gcp_transport_name)"
export ADVERTISED_ROUTES="$(terraform output -raw gcp_advertised_routes_for_transport)"
export ACTIVATION_KEY="paste-activation-key-from-step-3"

gcloud config set project "$GCP_PROJECT"

gcloud beta network-connectivity transports create "$TRANSPORT_NAME" \
  --region="$GCP_REGION" \
  --network="$GCP_NETWORK" \
  --advertised-routes="$ADVERTISED_ROUTES" \
  --activation-key="$ACTIVATION_KEY"
```

When using `--activation-key`, bandwidth is embedded in the key — do not pass `--bandwidth` separately.

The command blocks while the long-running operation completes (`Waiting for operation ...`). That is normal — do not interrupt unless you intend to cancel the create.

Check status:

```bash
gcloud beta network-connectivity transports describe "$TRANSPORT_NAME" \
  --region="$GCP_REGION"
```

Wait until the create operation completes. Typical transport states:

| State | Meaning |
|---|---|
| `CREATING` | Long-running create in progress — wait |
| `PENDING_CONFIG` | Create finished — proceed to Step 5 immediately |
| `ACTIVE` | May appear after AWS interconnect is **Available** (not required before Step 5) |

`state: PENDING_CONFIG` with a populated `peeringNetwork` field means Step 4 succeeded. Proceed to Step 5. Full cross-cloud readiness is confirmed when AWS interconnect is **Available** and incoming peering routes appear (Step 6). The [AWS Interconnect GA walkthrough](https://aws.amazon.com/blogs/aws/aws-interconnect-is-now-generally-available-with-a-new-option-to-simplify-last-mile-connectivity/) also shows `PENDING_CONFIG` at this stage before VPC peering.

---

## Step 5 — VPC network peering (GCP)

The transport creates a **managed peering network**. Peer your workload VPC to it so routes flow to your GCE VM.

```bash
export PEERING_NETWORK="$(gcloud beta network-connectivity transports describe "$TRANSPORT_NAME" \
  --region="$GCP_REGION" \
  --format='value(peeringNetwork)')"
export PEERING_NAME="demo-aws-peering"

gcloud compute networks peerings create "$PEERING_NAME" \
  --network="$GCP_NETWORK" \
  --peer-network="$PEERING_NETWORK" \
  --stack-type=IPV4_ONLY \
  --import-custom-routes \
  --export-custom-routes
```

Verify peering is active:

```bash
gcloud compute networks peerings list --network="$GCP_NETWORK"
```

You should see `STATE: ACTIVE` and `STATE_DETAILS: Connected`.

**MTU warning (expected):** The create command may warn that your VPC MTU (1460 B) does not match the transport peer MTU (8896 B). This is normal for Partner Cross-Cloud Interconnect. ICMP ping (Step 7) works with the default MTU; large TCP transfers may need MTU tuning in production ([GCP docs](https://cloud.google.com/network-connectivity/docs/interconnect/how-to/partner-cci-for-aws/create-vpc-peering-aws-to-gcp)).

After Step 5, GCP configuration is complete. The interconnect stays **Pending** on AWS until backend provisioning finishes — often **5–30 minutes**. Poll in Step 6; do not recreate transport or peering while waiting.

---

## Step 6 — Verify routing and wait for AWS

After Step 5, **you are waiting on AWS** (`pending` → `available`). GCP peering **ACTIVE** with transport **PENDING_CONFIG** and **0 incoming routes** is a healthy in-progress state — not an error.

### Expected states (healthy in-progress)

| Check | Healthy while waiting | Problem |
|---|---|---|
| AWS interconnect `state` | **pending** | **failed** |
| DXGW association | **associated** (can happen before Available) | stuck **pending** / **disassociated** |
| GCP peering | **ACTIVE** / Connected | INACTIVE or error in `STATE_DETAILS` |
| GCP transport | **PENDING_CONFIG**, `adminEnabled: true` | stuck **CREATING** for hours |
| GCP incoming routes | **0 items** | still 0 **after** AWS **available** (10+ min) |

Verify the interconnect attach point matches Terraform:

```bash
# DXGW from Terraform should match attachPoint.directConnectGateway in list-connections output
terraform output -raw aws_dx_gateway_id
aws interconnect list-connections --region "$(terraform output -raw aws_region)" --output json
```

Connection IDs use the form `mcc-xxxxxxxx` once provisioning progresses.

### Combined health check

Run this after Step 5 to confirm both sides. Re-run every 5–10 minutes until AWS shows **available**:

```bash
export AWS_REGION="$(terraform output -raw aws_region)"
export GCP_PROJECT="$(terraform output -raw gcp_project_id)"
export GCP_REGION="$(terraform output -raw gcp_region)"
export GCP_NETWORK="$(terraform output -raw gcp_vpc_network_name)"
export TRANSPORT_NAME="$(terraform output -raw gcp_transport_name)"

# 1. AWS interconnect state
aws interconnect list-connections --region "$AWS_REGION" --output json

# 2. DX Gateway association
aws directconnect describe-direct-connect-gateway-associations \
  --direct-connect-gateway-id "$(terraform output -raw aws_dx_gateway_id)" \
  --output json

# 3. GCP transport
gcloud beta network-connectivity transports describe "$TRANSPORT_NAME" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='yaml(state,adminEnabled,updateTime)'

# 4. GCP peering
gcloud compute networks peerings list --network="$GCP_NETWORK" --project="$GCP_PROJECT"

# 5. GCP incoming routes (empty until AWS is available — not an error yet)
gcloud compute networks peerings list-routes demo-aws-peering \
  --direction=INCOMING --network="$GCP_NETWORK" \
  --region="$GCP_REGION" --project="$GCP_PROJECT"
```

Poll AWS until **available** (replace `mcc-xxxxxxxx` with your connection `id` from step 1):

```bash
aws interconnect get-connection \
  --identifier mcc-xxxxxxxx \
  --region "$AWS_REGION" \
  --query 'connection.{state:state,id:id,attachPoint:attachPoint}' \
  --output table
```

**Timeline:** 0–15 min **pending** is normal · 15–30 min still **pending** — keep polling · **> 30 min** or **failed** — see [Checking for errors](#checking-for-errors).

### AWS — Interconnect status

Check the multicloud connection first — this is the main gate for route exchange.

**Console (recommended):** [AWS Interconnect](https://us-east-1.console.aws.amazon.com/directconnect/v2/home?region=ap-southeast-1#/aws-interconnect) — set `region=` to your `aws_region`. Status should move **Pending → Available**.

**CLI (optional):** Requires AWS CLI **2.34.43+** with the `interconnect` service namespace. Older builds return `Found invalid choice 'interconnect'` — use the console or upgrade:

```bash
aws --version   # must show 2.34.43 or newer for interconnect commands

# Upgrade (pick one):
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
  && unzip -qo /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install --update

aws interconnect list-connections \
  --region "$(terraform output -raw aws_region)" \
  --query 'connections[*].{id:id,state:state,description:description}' \
  --output table
```

> **Note:** `aws directconnect describe-interconnects` is the **legacy physical Direct Connect** API — not AWS Interconnect multicloud. Do not use it for this demo.

### AWS — DX Gateway association

```bash
aws directconnect describe-direct-connect-gateway-associations \
  --direct-connect-gateway-id "$(terraform output -raw aws_dx_gateway_id)" \
  --query 'directConnectGatewayAssociations[*].{state:associationState,allowed:allowedPrefixesToDirectConnectGateway}' \
  --output table
```

The association can reach **associated** while the interconnect is still **pending** — that is normal. Allowed prefixes should include your `aws_vpc_cidr` (e.g. `10.0.0.0/16`).

### AWS — VGW route propagation

In the AWS console: **VPC → Route tables → demo-private-rt**

You should see:

- `10.1.0.0/16` (or your `gcp_vpc_cidr`) → **Virtual Private Gateway** (static route from Terraform)
- GCP-learned routes may appear once BGP over the Interconnect is up

Check the DX Gateway association: **Direct Connect → Direct Connect gateways → demo-dx-gateway → Associations**

- State should move toward **associated**
- Allowed prefixes should include your `aws_vpc_cidr`

### GCP — peering routes (incoming from AWS)

After AWS shows **Available**, AWS routes should appear on the peering:

```bash
gcloud compute networks peerings list-routes demo-aws-peering \
  --direction=INCOMING \
  --network="$GCP_NETWORK" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT"
```

Target: `10.0.0.0/16` (your `aws_vpc_cidr`) with status **accepted**. **Listed 0 items** before AWS is **Available** is expected.

Outgoing (GCP → AWS) may show `10.1.0.0/16` earlier:

```bash
gcloud compute networks peerings list-routes demo-aws-peering \
  --direction=OUTGOING \
  --network="$GCP_NETWORK" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT"
```

### GCP — custom routes

```bash
gcloud compute routes list --filter="network:$GCP_NETWORK" --project="$GCP_PROJECT"
```

You should see routes toward your AWS VPC CIDR learned via the peering/transport path once BGP is up.

---

## Step 7 — End-to-end connectivity test

Allow a few minutes after the Interconnect shows **Available** for BGP and routes to converge.

**Resolve ping targets on your workstation first.** `terraform output` is not available inside EC2 (SSM) or GCE (SSH) shells — note the IPs before you connect:

```bash
export GCP_PROJECT="$(terraform output -raw gcp_project_id)"
export GCE_IP="$(terraform output -raw gce_instance_private_ip)"
export AWS_IP="$(terraform output -raw aws_instance_private_ip)"
echo "GCP project: ${GCP_PROJECT}"
echo "GCE target: ${GCE_IP}"
echo "AWS target: ${AWS_IP}"
```

If you prefer not to use env vars, pass `--project="$(terraform output -raw gcp_project_id)"` directly in `gcloud` commands below.

### EC2 → GCE (SSM Session Manager)

The instance has **no public IP**. From your workstation:

```bash
aws ssm start-session \
  --target "$(terraform output -raw aws_instance_id)" \
  --region "$(terraform output -raw aws_region)"
```

From the **EC2 shell**, ping using the GCE IP you printed above (not `terraform output`):

```bash
ping -c 5 10.1.0.2   # replace with your gce_instance_private_ip
```

### GCE → EC2 (IAP tunnel)

From your workstation, save the **Terraform-generated key pair** (same keys installed on the VM via metadata) and connect:

```bash
terraform output -raw gce_ssh_private_key > demo-gce-key
terraform output -raw gce_ssh_public_key > demo-gce-key.pub
chmod 600 demo-gce-key demo-gce-key.pub
```

> **New output?** If `gce_ssh_public_key` is not found, run `terraform apply` once (no infrastructure changes — only registers the output). Or derive the matching public key from the private key you already saved: `ssh-keygen -y -f demo-gce-key > demo-gce-key.pub && chmod 600 demo-gce-key.pub` (same key pair, not a new key).

```bash
gcloud compute ssh "$(terraform output -raw gce_instance_name)" \
  --zone="$(terraform output -raw gce_instance_zone)" \
  --project="$(terraform output -raw gcp_project_id)" \
  --tunnel-through-iap \
  --ssh-key-file=demo-gce-key
```

`gcloud compute ssh --ssh-key-file` requires both private and `.pub` files. Do **not** answer `y` if gcloud offers to overwrite broken keys — that would replace the Terraform key with a new one the VM does not trust.

These files contain secrets. They are listed in `.gitignore` (`demo-gce-key`, `demo-gce-key.pub`) — **do not commit them**. Remove them during [teardown](#6-local-cleanup--remove-ssh-keys) when the demo is finished.

From the **GCE shell**, ping using the AWS IP you printed above:

```bash
ping -c 5 10.0.1.10   # replace with your aws_instance_private_ip
```

Successful round-trip ping confirms traffic is flowing over the **Interconnect multicloud** path.

Optional traceroute from either side — hops should **not** traverse public internet addresses.

---

## Teardown (order matters)

> **Critical:** `terraform destroy` does **not** delete the AWS interconnect, GCP transport, or VPC peering. Skipping manual teardown leaves **~$6+/hr** combined (paid AWS + GCP transport) billing until you remove them.

Delete interconnect resources **in this order**, then destroy Terraform:

| Order | Remove | Stops billing |
|---|---|---|
| 1 | GCP VPC peering | — |
| 2 | GCP transport | ~$5/hr GCP |
| 3 | AWS multicloud Interconnect | ~$1.37/hr AWS (after delete completes) |
| 4 | Wait — AWS `list-connections` empty | — |
| 5 | `terraform destroy` | ~$30–40/mo base infra |
| 6 | Remove `demo-gce-key*` (gitignored secrets) | — |

Run from your **workstation in the repo directory** (needs `terraform output` and cloud credentials):

```bash
export GCP_PROJECT="$(terraform output -raw gcp_project_id)"
export GCP_REGION="$(terraform output -raw gcp_region)"
export GCP_NETWORK="$(terraform output -raw gcp_vpc_network_name)"
export TRANSPORT_NAME="$(terraform output -raw gcp_transport_name)"
export AWS_REGION="$(terraform output -raw aws_region)"
```

Optional — confirm nothing is still in use before deleting:

```bash
aws interconnect list-connections --region "$AWS_REGION" \
  --query 'connections[*].{id:id,state:state,description:description}' \
  --output table

gcloud beta network-connectivity transports describe "$TRANSPORT_NAME" \
  --region="$GCP_REGION" --project="$GCP_PROJECT" \
  --format='value(state)'
```

### 1. GCP — delete VPC peering

Delete peering **before** the transport ([GCP teardown order](https://cloud.google.com/network-connectivity/docs/interconnect/how-to/cci/deleting-interconnects)).

```bash
gcloud compute networks peerings delete demo-aws-peering \
  --network="$GCP_NETWORK" \
  --project="$GCP_PROJECT" \
  --quiet
```

### 2. GCP — delete transport

```bash
gcloud beta network-connectivity transports delete "$TRANSPORT_NAME" \
  --region="$GCP_REGION" \
  --project="$GCP_PROJECT" \
  --quiet
```

### 3. AWS — delete multicloud Interconnect

**Console:** [AWS Interconnect](https://us-east-1.console.aws.amazon.com/directconnect/v2/home?region=ap-southeast-1#/aws-interconnect) — set `region=` to your `aws_region`. Delete `demo-interconnect`.

**CLI** (AWS CLI ≥ 2.34.43):

```bash
CONN_ID="$(aws interconnect list-connections --region "$AWS_REGION" \
  --query 'connections[?description==`demo-interconnect`].id | [0]' --output text)"

aws interconnect delete-connection \
  --identifier "$CONN_ID" \
  --region "$AWS_REGION"
```

The API returns `"state": "deleting"` immediately — **that is not finished yet**. Deleting the AWS connection also notifies GCP to tear down the partner side (GCP transport should already be gone from Step 2).

### 4. Wait for AWS delete to finish — then verify

**Do not run `terraform destroy` while AWS still shows `deleting`.** GCP Steps 1–2 can show empty lists right away; AWS teardown often takes **1–5 minutes** (sometimes longer).

Poll until the interconnect list is **empty**:

```bash
aws interconnect list-connections --region "$AWS_REGION" \
  --query 'connections[*].{id:id,state:state,description:description}' \
  --output table
```

| `list-connections` result | Safe for `terraform destroy`? |
|---|---|
| Empty table | **Yes** |
| `state: deleting` | **No** — wait and poll again |
| `state: available` | **No** — Step 3 delete not started or failed |

Confirm GCP is clean (expect **Listed 0 items** for both after Steps 1–2):

```bash
gcloud beta network-connectivity transports list \
  --region="$GCP_REGION" --project="$GCP_PROJECT"

gcloud compute networks peerings list \
  --network="$GCP_NETWORK" --project="$GCP_PROJECT"
```

Example mid-teardown (GCP done, AWS still deleting — **wait before destroy**):

```text
# AWS — still deleting
|  demo-interconnect |  mcc-zrisgbmk  |  deleting |

# GCP — already clean
Listed 0 items.   # transports
Listed 0 items.   # peerings
```

### 5. Terraform — destroy base infrastructure

Only after AWS `list-connections` is **empty**:

```bash
terraform destroy
```

### 6. Local cleanup — remove SSH keys

Remove the GCE key files saved in Step 7. They are **gitignored** (see `.gitignore`) but will remain on disk until you delete them:

```bash
rm -f demo-gce-key demo-gce-key.pub
```

If you skip this step, the private key stays in the repo directory. `.gitignore` prevents accidental `git add`, but delete the files anyway — especially on shared machines.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Interconnect stuck **Pending** | GCP transport or peering not created; AWS still provisioning | Complete Steps 4–5; check [AWS Interconnect console](#step-6--verify-routing-and-wait-for-aws); wait 15–30 min |
| `aws interconnect` invalid choice | AWS CLI too old (< 2.34.43) | Use console for status, or upgrade CLI (see Step 6) |
| GCP `list-routes` shows 0 incoming | AWS interconnect not **Available** yet | Wait for AWS **Available**; then re-check incoming routes |
| Transport `PENDING_CONFIG` after peering | Normal until AWS backend completes | Check AWS interconnect status; peering **ACTIVE** is the GCP-side success signal |
| `aws_dx_gateway_association` pending | Interconnect not active yet | Wait for Available; check activation key |
| EC2 SSM session fails | VPC endpoints not ready or IAM | Wait 2–3 min after apply; confirm SSM agent on AL2023 |
| GCE SSH via IAP fails | Missing IAP firewall rule | Rule `demo-allow-iap-ssh` allows `35.235.240.0/20`; enable IAP API |
| Ping fails both ways | Route or peering issue | Re-check `--import-custom-routes` / `--export-custom-routes`; verify CIDRs |
| Wrong region pair | Unsupported Interconnect path | Run `remote-profiles list`; align `aws_region` + `gcp_region` |
| Free Tier unavailable / billing “free trial” error | Free Tier quota used or eligibility check failed | Use **AWS Interconnect – multicloud** (paid, 1 Gbps) — see Step 3 |
| MTU warning at peering create (1460 vs 8896) | Default GCP VPC MTU vs transport jumbo MTU | Expected — safe for ICMP ping; tune MTU only if large TCP transfers fail |
| Interconnect **failed** (no error message) | Org SCP blocking `interconnect:*` or GCP VPC Service Controls | See [Checking for errors](#checking-for-errors) |

### Checking for errors

**Pending is not an error** — it means AWS is still provisioning after GCP Steps 4–5 complete. Worry when state becomes **failed**, or **pending** exceeds ~30 minutes with no progress.

#### Decision tree

```text
pending + peering ACTIVE + transport PENDING_CONFIG + DXGW associated
  → Normal. Poll every 5–10 min (Step 6 health check).

state = failed
  → Check SCPs (interconnect:*), CloudTrail, account/DXGW alignment. Delete, fix, recreate.

state = available but 0 incoming routes after 10 min
  → Re-check DXGW association and BGP propagation (Step 6).

state = available + routes OK but ping fails
  → Security groups / firewall / wrong IPs (Step 7).
```

#### AWS — CloudTrail (interconnect events)

Console: [CloudTrail Event history](https://console.aws.amazon.com/cloudtrail/home#/events) → filter **Event source** = `interconnect.amazonaws.com`.

CLI:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=interconnect.amazonaws.com \
  --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-results 10 \
  --query 'Events[*].{Time:EventTime,Name:EventName}' \
  --output table
```

A `"state": "pending"` API response does **not** guarantee backend provisioning succeeds. Failures during provisioning may not surface as explicit errors ([re:Post guide](https://repost.aws/articles/ARU_FMBmrUQYG2hIPezn-XRQ/aws-multicloud-interconnect-failures-aws-to-gcp)).

#### AWS — Organization SCPs

If you use AWS Organizations / Control Tower, ensure SCPs allow **`interconnect:*`** — a separate namespace from `directconnect:*`. SCP denials often produce a silent **failed** state with no CloudTrail denial log.

Confirm interconnect and DXGW are in the same account as Terraform:

```bash
aws sts get-caller-identity
terraform output -raw aws_dx_gateway_id
```

#### GCP — transport or peering failures

Transport stuck in **CREATING** (not **PENDING_CONFIG**) for hours — check **VPC Service Controls**: allow `networkconnectivity-transportmanager-clh@system.gserviceaccount.com` through the perimeter.

Recent transport operations:

```bash
gcloud beta network-connectivity operations list \
  --region="$GCP_REGION" --project="$GCP_PROJECT" --limit=5
```

### Billing verification failed (Free Tier only)

Applies only when using **AWS Interconnect – multicloud – Free Tier**. **Paid multicloud** does not use the “free trial connection” path — if Free Tier fails, switch to paid (Step 3).

Console error:

```text
InterconnectValidationException: Unable to create free trial connection.
Your account's billing information could not be verified. Please try again later.
```

The Free Tier is $0 on AWS for bandwidth, but AWS still checks that the **account paying for the account** (the **management / payer account** in Organizations, or the standalone root account) has a valid, **verified** card on file. Being signed in as root does not bypass this — the **payment method** must pass verification.

**Fix (management / root account):**

1. Sign in to the **AWS account that owns billing** (management account payer, not necessarily the member account where Terraform ran).
2. Open [Payment methods](https://console.aws.amazon.com/billing/home#/paymentmethods) (**Billing and Cost Management → Payment preferences**).
3. Confirm a default payment method exists and shows **Verified** (not *Pending* or *Failed*).
4. If unverified:
   - Update billing address to match your bank exactly ([AWS guidance](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/manage-cc-verification.html)).
   - Remove and re-add the card; complete any **3-D Secure / bank redirect** prompt.
   - Ask your bank to allow small AWS authorization charges (often ~USD 1; cancelled immediately).
   - Ensure **international / online** transactions are enabled on the card.
5. Wait up to **24 hours** after adding or fixing a card, then retry Step 3 **Finish**.
6. If it still fails, open a **billing support case** (free): [AWS Support → Create case](https://console.aws.amazon.com/support/home#/case/create) → **Account and billing** → explain the Interconnect Free Tier verification error and that payment method verification is failing.

**Organizations note:** If Terraform and the DX Gateway are in a **member account**, billing verification still runs against the **organization management (payer) account**. Fix payment methods there, not only in the member account.

**Payment already shows Verified but error persists?**

The console **Verified** badge is not always the same check Interconnect uses for Free Tier eligibility. If you are on the **root / payer account** and payment methods look correct, work through:

1. **Confirm account ID** — note the 12-digit account in the console header when you click **Finish**. Interconnect is created in *that* account; in Organizations, ensure the **payer** account is the one with verified billing (not only a member account you switched into).
2. **Account fully active** — Billing → [Account](https://console.aws.amazon.com/billing/home#/account): no incomplete signup, no past-due invoices, no pending identity verification.
3. **Billing history** — some new accounts show a verified card but fail product-specific “free trial” checks until at least one successful charge/settlement has posted (similar to other services). If the account is new, wait 24–72 hours and retry.
4. **Card type** — prepaid, virtual, or corporate cards with restricted authorizations can fail backend checks even when the UI shows Verified. Try a standard credit card as default payment method.
5. **Free Tier already used** — one free 500 Mbps interconnect per AWS Region per CSP; a prior attempt may have consumed the quota even if the connection failed or was deleted.
6. **Organizations SCPs** — ensure SCPs allow `interconnect:*` (separate from `directconnect:*`). SCP blocks usually cause silent **failed** state, but worth checking if billing looks fine ([re:Post guide](https://repost.aws/articles/ARU_FMBmrUQYG2hIPezn-XRQ/aws-multicloud-interconnect-failures-aws-to-gcp)).
7. **Open a billing support case** (free) — this is the practical fix when billing looks correct. Include the exact error, account ID, region (`ap-southeast-1`), and that payment methods show **Verified**. Ask them to enable Free Tier interconnect / resolve the backend billing verification flag.

**Same error on the management (payer) account?** That usually means the console **Verified** status is fine but Interconnect’s internal free-trial eligibility check is still failing — common with new accounts, invoice/PO billing, or prepaid cards. Only AWS Support can clear the backend flag; self-service steps above rarely help at that point.

**Account alignment:** Create the interconnect in the **same AWS account** where Terraform created the Direct Connect gateway (`terraform output -raw aws_dx_gateway_id`). Switching to the management account for billing does not help if the DXGW and VPC live in a member account — re-run `terraform apply` in the target account first, or create the interconnect in that member account (with payer billing already verified).

---

## What is intentionally not in Terraform

| Resource | Reason |
|---|---|
| `aws_interconnect_connection` | Not yet in `hashicorp/aws` provider ([issue #47458](https://github.com/hashicorp/terraform-provider-aws/issues/47458)); use console/CLI |
| `google_network_connectivity_transport` | Beta API; activation-key flow is console-driven today |
| VPC peering to transport network | Depends on runtime `peeringNetwork` from transport describe |

When provider support lands, these steps can move into Terraform. Until then, this README is the source of truth for the interconnect layer.

---

## Variable reference

| Variable | Description |
|---|---|
| `aws_region` | AWS region (Interconnect source) |
| `gcp_region` | Paired GCP region (Interconnect destination) |
| `gcp_project_id` | GCP project ID |
| `gcp_transport_name` | Name for the gcloud transport resource |
| `aws_vpc_cidr` | AWS VPC CIDR — advertised to GCP |
| `aws_subnet_cidr` | AWS private subnet for EC2 |
| `aws_dx_gateway_asn` | Private ASN for the Direct Connect Gateway |
| `gcp_vpc_cidr` | GCP subnet CIDR — advertised to AWS |

SSH to GCE uses a key pair generated by Terraform (`tls_private_key`); no variable required.

---

## Output reference

| Output | Description |
|---|---|
| `aws_dx_gateway_id` | DX Gateway for Interconnect creation |
| `aws_allowed_prefix_for_gcp` | AWS CIDR sent toward GCP |
| `gcp_advertised_routes_for_transport` | GCP CIDR for `--advertised-routes` |
| `gcp_vpc_network_name` | GCP network name for gcloud |
| `gcp_transport_name` | Transport resource name |
| `aws_instance_id` | EC2 ID for SSM |
| `aws_instance_private_ip` | EC2 private IP (ping target from GCP) |
| `gce_instance_name` / `gce_instance_zone` | GCE SSH via IAP |
| `gce_instance_private_ip` | GCE private IP (ping target from AWS) |
| `gce_ssh_private_key` | Generated SSH private key for GCE (sensitive) — save as `demo-gce-key` |
| `gce_ssh_public_key` | Matching public key on the VM — save as `demo-gce-key.pub` for `gcloud compute ssh` |

---

## References

- [AWS Interconnect – multicloud regional availability](https://docs.aws.amazon.com/interconnect/latest/userguide/region-availability.html)
- [AWS Interconnect – multicloud Free Tier announcement](https://aws.amazon.com/about-aws/whats-new/2026/05/aws-interconnect-multicloud-offers-free-500-mbps-tier/)
- [AWS Interconnect – multicloud pricing](https://aws.amazon.com/interconnect/multicloud/pricing/)
- [AWS Interconnect GA blog post](https://aws.amazon.com/blogs/aws/aws-interconnect-is-now-generally-available-with-a-new-option-to-simplify-last-mile-connectivity/)
- [GCP Partner Cross-Cloud Interconnect for AWS](https://cloud.google.com/network-connectivity/docs/interconnect/concepts/partner-cross-cloud-interconnect-aws)
- [GCP — VPC peering for AWS-initiated interconnect](https://cloud.google.com/network-connectivity/docs/interconnect/how-to/partner-cci-for-aws/create-vpc-peering-aws-to-gcp)
- [AWS re:Post — multicloud interconnect silent failures (SCP / VPC-SC)](https://repost.aws/articles/ARU_FMBmrUQYG2hIPezn-XRQ/aws-multicloud-interconnect-failures-aws-to-gcp)
- [Terraform AWS provider — Interconnect tracking issue](https://github.com/hashicorp/terraform-provider-aws/issues/47458)

---

## License

[MIT](LICENSE)
