# =============================================================================
# AWS Direct Connect Gateway (attach point for Interconnect multicloud)
# =============================================================================
#
# The multicloud Interconnect connection itself is created outside Terraform
# (AWS console or CLI). See README.md — Step 3.
#
# This gateway is the AWS-side attach point referenced when you create the
# Interconnect and when you configure allowed prefixes for GCP route exchange.

resource "aws_dx_gateway" "this" {
  name            = "demo-dx-gateway"
  amazon_side_asn = var.aws_dx_gateway_asn
}
