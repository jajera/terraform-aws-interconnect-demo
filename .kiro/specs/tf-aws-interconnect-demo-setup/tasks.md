# Implementation Plan: terraform-aws-interconnect-demo-setup

## Overview

This plan implements the flat Terraform project layout and Kiro IDE configuration for the AWS–GCP interconnect demo. All `.tf` files are created directly at the repository root with no subdirectory hierarchy. Kiro configuration (MCP servers, steering files, hooks, and skills) is created under `.kiro/`. Each task builds on the previous ones and ends with all components wired together.

## Tasks

- [x] 1. Create Terraform version and provider foundation files
  - [x] 1.1 Create `versions.tf` with required Terraform and provider version constraints
    - Declare `required_version = ">= 1.5.0"`
    - Declare `required_providers` for `hashicorp/aws ~> 5.0` and `hashicorp/google ~> 5.0`
    - _Requirements: 1.5_
  - [x] 1.2 Create `main.tf` with AWS and GCP provider configuration blocks
    - Configure `provider "aws"` with `region = var.aws_region`
    - Configure `provider "google"` with `project = var.gcp_project_id` and `region = var.gcp_region`
    - _Requirements: 1.2_

- [x] 2. Create `variables.tf` with all input variables and validation blocks
  - [x] 2.1 Declare AWS Direct Connect input variables with validation
    - Declare `aws_region` (string, no constraint)
    - Declare `connection_bandwidth` (string) with `validation` block enforcing one of `1Gbps`, `10Gbps`, `100Gbps`; error message must list the three valid options
    - Declare `vlan_id` (number) with `validation` block enforcing range 1–4094
    - Declare `bgp_asn` (number, no constraint)
    - Declare `bgp_auth_key` (string, `sensitive = true`)
    - _Requirements: 2.2, 2.4, 2.5_
  - [x] 2.2 Declare GCP Cloud Interconnect input variables with validation
    - Declare `gcp_project_id` (string) with `validation` block enforcing regex `^[a-z][a-z0-9\-]{4,28}[a-z0-9]$`; error message must state the format requirement
    - Declare `gcp_region` (string, no constraint)
    - Declare `interconnect_type` (string) with `validation` block enforcing one of `PARTNER`, `DEDICATED`
    - Declare `vlan_tag` (number) with `validation` block enforcing range 1–4094
    - Declare `gcp_bgp_asn` (number) with `validation` block enforcing range 1–4294967295
    - Declare `advertised_route_priority` (number) with `validation` block enforcing range 0–65535
    - _Requirements: 3.2, 3.4, 3.5_

- [x] 3. Create `aws-interconnect.tf` with Direct Connect resources
  - [x] 3.1 Declare `aws_dx_connection` resource
    - Use resource label `this`
    - Reference `var.connection_bandwidth` for bandwidth and `var.aws_region` (via provider) for location
    - _Requirements: 2.1_
  - [x] 3.2 Declare `aws_dx_gateway` resource
    - Use resource label `this`
    - _Requirements: 2.1_
  - [x] 3.3 Declare `aws_dx_private_virtual_interface` resource
    - Use resource label `this`
    - Reference `var.vlan_id`, `var.bgp_asn`, `var.bgp_auth_key`
    - Reference `aws_dx_gateway.this.id` and `aws_dx_connection.this.id`
    - _Requirements: 2.1_

- [x] 4. Create `gcp-interconnect.tf` with Cloud Interconnect resources
  - [x] 4.1 Declare `google_compute_router` resource
    - Use resource label `this`
    - Reference `var.gcp_region` and `var.gcp_project_id` (via provider)
    - _Requirements: 3.1_
  - [x] 4.2 Declare `google_compute_interconnect_attachment` resource
    - Use resource label `this`
    - Reference `var.interconnect_type`, `var.vlan_tag`, and `google_compute_router.this.name`
    - _Requirements: 3.1_
  - [x] 4.3 Declare `google_compute_router_peer` resource
    - Use resource label `this`
    - Reference `var.gcp_bgp_asn`, `var.advertised_route_priority`, and `google_compute_interconnect_attachment.this`
    - _Requirements: 3.1_

- [x] 5. Create `outputs.tf` with all output values
  - [x] 5.1 Declare AWS Direct Connect output values
    - `connection_id` = `aws_dx_connection.this.id`
    - `virtual_interface_id` = `aws_dx_private_virtual_interface.this.id`
    - `gateway_id` = `aws_dx_gateway.this.id`
    - _Requirements: 2.3_
  - [x] 5.2 Declare GCP Cloud Interconnect output values
    - `vlan_attachment_name` = `google_compute_interconnect_attachment.this.name`
    - `cloud_router_id` = `google_compute_router.this.self_link`
    - `bgp_peer_ip` = `google_compute_router_peer.this.peer_ip_address`
    - _Requirements: 3.3_

- [x] 6. Create supporting project files
  - [x] 6.1 Create `terraform.tfvars` with placeholder values annotated with `# REPLACE`
    - Every variable declared in `variables.tf` must have a value entry
    - Every placeholder value must have an inline `# REPLACE` comment
    - _Requirements: 1.6_
  - [x] 6.2 Create `.gitignore` with required exclusion entries
    - Must include: `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `*.tfvars.local`, `*.auto.tfvars`
    - _Requirements: 1.8_
  - [x] 6.3 Create `.terraform.lock.hcl` as a valid empty HCL placeholder
    - File must be syntactically valid HCL (can be a comment-only file)
    - _Requirements: 1.9_

- [x] 7. Checkpoint — Verify Terraform configuration is structurally valid
  - Ensure all required root files exist: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `terraform.tfvars`, `aws-interconnect.tf`, `gcp-interconnect.tf`, `.gitignore`, `.terraform.lock.hcl`
  - Ensure no `backend.tf`, no `modules/` directory, no `environments/` directory exist
  - Run `terraform fmt -check` across all `.tf` files and fix any formatting issues
  - Run `terraform validate` if credentials are available; otherwise confirm HCL syntax is correct by review
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Create Kiro MCP server configuration
  - [x] 8.1 Create `.kiro/settings/mcp.json` with at least two MCP server entries
    - Top-level key must be `mcpServers`
    - Include a `terraform-docs` entry using `command: "npx"` and `args: ["-y", "@hashicorp/terraform-mcp-server"]`
    - Include an `aws-documentation` entry using `command: "npx"` and `args: ["-y", "@aws/aws-mcp-server"]`
    - Each entry must have a non-empty `command` or `url` field
    - _Requirements: 4.1, 4.3_

- [x] 9. Create Kiro steering files
  - [x] 9.1 Create `.kiro/steering/terraform-conventions.md` with Terraform coding conventions
    - Include YAML front matter with `inclusion: auto`
    - Include imperative directives for: snake_case naming, resource tagging (`Project`, `Environment`, `ManagedBy = Terraform`), no hardcoded credentials, no `modules/` or `environments/` directories
    - _Requirements: 5.1, 5.3, 5.4_
  - [x] 9.2 Create `.kiro/steering/interconnect-context.md` with AWS–GCP interconnect domain context
    - Include YAML front matter with `inclusion: manual`
    - Include content covering BGP configuration guidance, VLAN allocation rules, MTU considerations, Direct Connect gateway behaviour, and GCP Cloud Router BGP peer IP assignment
    - Include at least one imperative directive (e.g., "Never use VLAN 1 for interconnect attachments")
    - _Requirements: 5.2, 5.3, 5.4_

- [x] 10. Create Kiro hook definitions
  - [x] 10.1 Create `.kiro/hooks/tf-fmt-check.json` for Terraform format check
    - `name`: `"Terraform Format Check"`, `version`: `"1.0"`
    - `when.type`: `"fileEdited"`, `when.filePatterns`: `["**/*.tf"]`
    - `then.type`: `"runCommand"`, `then.command`: `"terraform fmt -check"`
    - _Requirements: 6.1, 6.3, 6.4_
  - [x] 10.2 Create `.kiro/hooks/tf-naming-review.json` for naming convention review
    - `name`: `"Terraform Naming Convention Review"`, `version`: `"1.0"`
    - `when.type`: `"fileEdited"`, `when.filePatterns`: `["**/*.tf"]`
    - `then.type`: `"askAgent"`, `then.prompt`: instruct agent to review the file against `.kiro/steering/terraform-conventions.md` and list each violation with resource address and convention broken
    - _Requirements: 6.2, 6.3, 6.4_

- [x] 11. Create Kiro skill definitions
  - [x] 11.1 Create `.kiro/skills/resource-scaffold.md` for new resource file scaffolding
    - YAML front matter must include `name: resource-scaffold` and `description` fields
    - Skill body must describe: accepting a resource-file name argument, creating a `.tf` file at the repository root with a `# ---` section header comment and at least one placeholder `resource` block
    - Include stop-on-error behaviour: halt all subsequent steps and surface the error message and failed step name on any non-zero exit code
    - _Requirements: 7.1, 7.3, 7.4_
  - [x] 11.2 Create `.kiro/skills/plan-summary.md` for Terraform plan output summarisation
    - YAML front matter must include `name: plan-summary` and `description` fields
    - Skill body must describe: accepting `terraform plan` output as input, returning resource counts (add/change/destroy), a bullet list of resource addresses grouped by action, and a one-sentence risk assessment on destructive changes
    - Include same stop-on-error behaviour as `resource-scaffold`
    - _Requirements: 7.2, 7.3, 7.4_

- [x] 12. Final checkpoint — Ensure all tests pass
  - Validate all `.kiro/hooks/*.json` files are valid JSON containing `name`, `version`, `when.type`, and `then.type` plus either `prompt` or `command`
  - Validate `.kiro/settings/mcp.json` is valid JSON with `mcpServers` top-level key and at least one domain-relevant entry
  - Validate each `.kiro/skills/*.md` and `.kiro/steering/*.md` has correct YAML front matter
  - Confirm `terraform.tfvars` has a `# REPLACE` annotation on every placeholder
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP. No tasks in this plan are marked optional because all components are required by the requirements document.
- No property-based tests are included: the design explicitly states PBT does not apply to this feature (all components are declarative HCL and IDE configuration files with no pure function logic).
- Integration tests requiring live AWS/GCP credentials (task 7 checkpoint) are manual or CI-only steps.
- Each task references specific requirements for traceability.
- Checkpoints (tasks 7 and 12) ensure incremental validation before moving to the next phase.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "2.2"] },
    { "id": 2, "tasks": ["3.1", "3.2", "4.1"] },
    { "id": 3, "tasks": ["3.3", "4.2", "5.1"] },
    { "id": 4, "tasks": ["4.3", "5.2", "6.1", "6.2", "6.3"] },
    { "id": 5, "tasks": ["8.1", "9.1", "9.2", "10.1", "10.2", "11.1", "11.2"] }
  ]
}
```
