# =============================================================================
# Region pairing — must be a supported AWS ↔ GCP Interconnect pair.
# Supported pairs: https://docs.aws.amazon.com/interconnect/latest/userguide/region-availability.html
# Default: AWS ap-southeast-1 ↔ GCP asia-southeast1 (Singapore).
# Note: ap-southeast-2 (Sydney) is NOT a supported Interconnect pair — use ap-southeast-1.
# List GCP remote profiles: gcloud beta network-connectivity transports remote-profiles list --region=<gcp-region>
# =============================================================================

aws_region = "ap-southeast-1"  # REPLACE
gcp_region = "asia-southeast1" # REPLACE — paired GCP region for aws_region

gcp_project_id     = "prj-core-465010" # REPLACE
gcp_transport_name = "demo-interconnect-transport"

# =============================================================================
# AWS network — aws_vpc_cidr is advertised to GCP; gcp_vpc_cidr is allowed on the DX Gateway association
# =============================================================================

aws_vpc_cidr       = "10.0.0.0/16" # REPLACE
aws_subnet_cidr    = "10.0.1.0/24" # REPLACE
aws_dx_gateway_asn = 64512         # REPLACE — private ASN for the Direct Connect Gateway

# =============================================================================
# GCP network
# =============================================================================

gcp_vpc_cidr = "10.1.0.0/16" # REPLACE — pass to transport --advertised-routes
