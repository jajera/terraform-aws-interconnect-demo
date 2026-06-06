# Requirements Document

## Introduction

This feature establishes the foundational project structure for a Terraform-based demonstration repository that showcases **AWS Interconnect – multicloud (Free Tier)** connectivity with Google Cloud Platform (GCP). The setup covers two concerns: (1) a flat Terraform project layout where all `.tf` files reside directly at the repository root with no `modules/` or `environments/` subdirectories; and (2) Kiro IDE configuration including MCP server definitions, agent steering files, skills, hooks, and recommended Powers. Together these provide a reproducible, IDE-assisted infrastructure-as-code workflow for the AWS–GCP interconnect demo.

## Glossary

- **Repository**: The Git repository at `terraform-aws-interconnect-demo` that hosts all Terraform and Kiro configuration files.
- **Terraform_Project**: The collection of `.tf` files and supporting configuration at the repository root that define the AWS–GCP interconnect infrastructure.
- **Root_File**: A `.tf` or `.tfvars` file that lives directly at the repository root (not in any subdirectory).
- **MCP_Server**: A Model Context Protocol server definition stored in `.kiro/settings/mcp.json` that extends the Kiro agent with additional tool capabilities (e.g., Terraform documentation lookup, AWS/GCP API access).
- **Steering_File**: A Markdown file under `.kiro/steering/` that provides the Kiro agent with persistent context, coding conventions, or workflow guidance for the project.
- **Skill**: A reusable agent capability definition stored under `.kiro/skills/` that encapsulates a specific repeatable task the agent can perform.
- **Hook**: An event-driven automation rule stored in `.kiro/hooks/` that triggers agent actions in response to IDE events (e.g., file save, prompt submit).
- **Kiro_Power**: A Kiro IDE extension package that bundles documentation, MCP servers, and steering guides for a specific technology domain.
- **Variable_File**: A `.tfvars` file that supplies input variable values for a specific use case.

---

## Requirements

### Requirement 1: Flat Terraform Project Structure

**User Story:** As a developer, I want all Terraform files at the repository root with no subdirectory hierarchy, so that the project is simple to navigate and requires no module or environment path resolution.

#### Acceptance Criteria

1. THE Repository SHALL contain all Terraform Root_Files directly at the repository root; no `modules/` directory and no `environments/` directory SHALL exist in the repository.
2. THE Repository SHALL contain a `main.tf` Root_File at the repository root that declares the Terraform provider configurations for both `aws` and `google`.
3. THE Repository SHALL contain a `variables.tf` Root_File at the repository root that declares all input variables used across the Terraform_Project.
4. THE Repository SHALL contain an `outputs.tf` Root_File at the repository root that declares all output values produced by the Terraform_Project.
5. THE Repository SHALL contain a `versions.tf` Root_File at the repository root that declares a `required_version` constraint for Terraform (minimum `>= 1.5.0`) and `required_providers` version constraints for both `hashicorp/aws` (minimum `~> 5.0`) and `hashicorp/google` (minimum `~> 5.0`).
6. THE Repository SHALL contain a `terraform.tfvars` Root_File at the repository root where every required input variable has a value of the correct type, and each placeholder value SHALL be annotated with an inline comment containing the token `# REPLACE` to indicate it must be replaced before applying.
7. THE Repository SHALL NOT contain a `backend.tf` file; Terraform state SHALL be stored locally using the default local backend.
8. THE Repository SHALL contain a `.gitignore` file that excludes `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `*.tfvars.local`, and `*.auto.tfvars`.
9. THE Repository SHALL contain a `.terraform.lock.hcl` file or a `.gitignore` entry ensuring provider lock files are tracked in version control; if a `.terraform.lock.hcl` placeholder is committed, it SHALL be a valid HCL file (even if empty).

---

### Requirement 2: AWS Interconnect Attach Point at Root

**User Story:** As a network engineer, I want an AWS Direct Connect Gateway defined in a root-level Terraform file, so that it serves as the AWS-side attach point when creating an AWS Interconnect multicloud connection through the console.

#### Acceptance Criteria

1. THE Repository SHALL contain an `aws-interconnect.tf` Root_File at the repository root that defines a single resource: `aws_dx_gateway` with `amazon_side_asn = var.aws_dx_gateway_asn`.
2. THE `aws-interconnect.tf` file SHALL NOT declare `aws_dx_connection`, `aws_dx_private_virtual_interface`, or any other resource — the multicloud Interconnect connection is created outside Terraform (via AWS console and `gcloud beta`).
3. WHEN the Terraform_Project is applied, THE Terraform_Project SHALL output `aws_dx_gateway_id` (the DX Gateway ID) so the operator can select it when creating the Interconnect in the AWS console.

---

### Requirement 3: GCP Interconnect Layer Outside Terraform

**User Story:** As a network engineer, I want clarity that GCP interconnect resources are NOT provisioned by Terraform in this demo, so that I know they are created via `gcloud beta` following the README walkthrough.

#### Acceptance Criteria

1. THE Repository SHALL NOT contain a `gcp-interconnect.tf` file — `google_compute_router`, `google_compute_interconnect_attachment`, and `google_compute_router_peer` are not provisioned by Terraform in the AWS Interconnect multicloud pattern.
2. THE Repository's `gcp-network.tf` SHALL declare the GCP workload VPC, subnet, firewall rules, and compute — but SHALL NOT declare any interconnect-specific resources.
3. IF the Terraform_Project is applied with a `gcp_project_id` that does not match the pattern `^[a-z][a-z0-9\-]{4,28}[a-z0-9]$`, THEN THE Terraform_Project SHALL surface a Terraform `validation` block error.

---

### Requirement 4: Kiro MCP Server Configuration

**User Story:** As a developer, I want MCP server definitions configured in Kiro, so that the agent has access to relevant tooling for Terraform, AWS, and GCP documentation and API interactions.

#### Acceptance Criteria

1. THE Repository SHALL contain a `.kiro/settings/mcp.json` file that defines at least one MCP server entry where the entry key or `command` value contains one of the substrings `terraform`, `aws`, or `gcp` (case-insensitive), establishing relevance to the project domain.
2. WHEN the Kiro agent is initialized with the repository open, THE MCP_Server SHALL appear in the Kiro MCP Server panel without a red error indicator, confirming the definition was parsed and the server connected successfully.
3. THE `.kiro/settings/mcp.json` file SHALL be a valid JSON document where the top-level key is `mcpServers`, its value is a JSON object, and each child entry contains either a non-empty `command` string or a non-empty `url` string; the file SHALL NOT require a minimum number of server entries to pass structural validation.
4. IF the `.kiro/settings/mcp.json` file is absent or contains malformed JSON, THEN the Kiro agent SHALL log a warning or display an error indicator in the MCP Server panel and SHALL continue operating with any other valid configurations already loaded.

---

### Requirement 5: Kiro Agent Steering Files

**User Story:** As a developer, I want Kiro steering files that encode project conventions and domain context, so that the agent consistently applies Terraform best practices and AWS–GCP interconnect knowledge throughout the project.

#### Acceptance Criteria

1. THE Repository SHALL contain at least one Steering_File under `.kiro/steering/` with a filename indicating Terraform conventions (e.g., `terraform-conventions.md`) that covers naming conventions, tagging strategy, or resource interface patterns for this project.
2. THE Repository SHALL contain at least one Steering_File under `.kiro/steering/` with a filename indicating AWS–GCP interconnect domain context (e.g., `interconnect-context.md`) that covers topics such as BGP configuration guidance, VLAN allocation, or MTU considerations.
3. WHEN a Steering_File is created, THE Steering_File SHALL include a YAML front-matter block delimited by opening and closing `---` lines as the first content in the file, with an `inclusion` key whose value is either the string `auto` or the string `manual`.
4. THE Steering_File SHALL be written in Markdown and SHALL contain at least one imperative directive — a sentence that explicitly instructs the agent to perform or avoid a specific action (e.g., "Always use snake_case for resource names" or "Never hardcode AWS account IDs").
5. THE Repository MAY contain only domain-context Steering_Files without convention Steering_Files, or only convention Steering_Files without domain-context Steering_Files, and SHALL still be considered a valid Kiro configuration in either case.

---

### Requirement 6: Kiro Agent Hooks

**User Story:** As a developer, I want Kiro hooks configured for the project, so that repetitive validation and linting tasks are triggered automatically as I work on Terraform files.

#### Acceptance Criteria

1. WHEN a `.tf` file is edited and saved in the repository, THE Hook SHALL execute `terraform fmt -check` on the saved file and SHALL report the exit code or output to the developer without requiring any manual action.
2. WHEN a `.tf` file is edited and saved in the repository, THE Hook SHALL prompt the Kiro agent to review the changed file and produce a response identifying any violations of the project naming conventions defined in the Terraform conventions Steering_File.
3. WHEN a Hook is triggered by a file-edit event, THE Hook SHALL begin execution within the same IDE session in which the file was saved, without requiring the developer to manually invoke any command or click any UI element.
4. THE Hook definitions SHALL be stored as JSON files under `.kiro/hooks/` and each Hook file SHALL contain at minimum the fields `name` (string), `version` (string), `when` (object with a `type` field), and `then` (object with a `type` field and either a `prompt` or `command` field) to be considered schema-compatible.

---

### Requirement 7: Kiro Skills

**User Story:** As a developer, I want Kiro skill definitions for common Terraform tasks, so that the agent can perform repeatable actions like generating a new root-level resource file scaffold or running a plan summary on demand.

#### Acceptance Criteria

1. WHEN the resource-scaffold Skill is invoked with a resource-file name argument, THE Skill SHALL create a `.tf` Root_File at the repository root containing at minimum a Terraform comment block (`# ---`) as a section header and at least one placeholder resource block.
2. WHEN the plan-summary Skill is invoked with a `terraform plan` output as input, THE Skill SHALL return a summary that includes: the count of resources to be added, changed, and destroyed; a bullet list of resource addresses grouped by action; and a one-sentence risk assessment stating whether any destructive changes are present.
3. WHEN a Skill is invoked and any step returns a non-zero exit code or produces an error message, THE Skill SHALL immediately stop processing all subsequent steps and SHALL surface the error message and the name of the failed step to the developer.
4. THE Skill definitions SHALL be stored as Markdown files under `.kiro/skills/` with a YAML front-matter block that includes at minimum a `name` field (string) and a `description` field (string) delimited by opening and closing `---` lines.
