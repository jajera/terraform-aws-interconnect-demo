# =============================================================================
# General
# =============================================================================

variable "aws_region" {
  type        = string
  description = "AWS region for the demo VPC and Interconnect source region (e.g., ap-southeast-1)."
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project ID. Must match pattern ^[a-z][a-z0-9\\-]{4,28}[a-z0-9]$."

  validation {
    condition     = can(regex("^[a-z][a-z0-9\\-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "gcp_project_id must match pattern ^[a-z][a-z0-9\\-]{4,28}[a-z0-9]$."
  }
}

variable "gcp_region" {
  type        = string
  description = "GCP region paired with aws_region for Interconnect multicloud (e.g., asia-southeast1 for ap-southeast-1)."
}

variable "gcp_transport_name" {
  type        = string
  description = "Name for the Partner Cross-Cloud Interconnect transport created in Step 4 (gcloud)."
  default     = "demo-interconnect-transport"
}

# =============================================================================
# AWS Network
# =============================================================================

variable "aws_vpc_cidr" {
  type        = string
  description = "CIDR block for the AWS VPC. Advertised to GCP via the Interconnect transport."

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.aws_vpc_cidr))
    error_message = "aws_vpc_cidr must be valid CIDR notation (e.g., 10.0.0.0/16)."
  }
}

variable "aws_subnet_cidr" {
  type        = string
  description = "CIDR block for the AWS private subnet hosting the demo EC2 instance."

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.aws_subnet_cidr))
    error_message = "aws_subnet_cidr must be valid CIDR notation (e.g., 10.0.1.0/24)."
  }
}

variable "aws_dx_gateway_asn" {
  type        = number
  description = "Amazon-side BGP ASN for the Direct Connect Gateway (private ASN: 64512–65534 or 4200000000–4294967294)."
}

# =============================================================================
# GCP Network
# =============================================================================

variable "gcp_vpc_cidr" {
  type        = string
  description = "CIDR block for the GCP subnetwork. Advertised to AWS via allowed_prefixes on the DX Gateway association."

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.gcp_vpc_cidr))
    error_message = "gcp_vpc_cidr must be valid CIDR notation (e.g., 10.1.0.0/16)."
  }
}
