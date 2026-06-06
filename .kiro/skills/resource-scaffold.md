---
name: resource-scaffold
description: Create a new root-level Terraform resource file scaffold with a section header and placeholder resource block.
---

# Resource Scaffold Skill

## Purpose

Scaffold a new Terraform resource file at the repository root. The file will contain a `# ---` section header comment and at least one placeholder `resource` block ready for the developer to fill in.

## Input

| Argument | Type | Required | Description |
|---|---|---|---|
| `resource-file-name` | string | yes | Name of the `.tf` file to create, without the `.tf` extension (e.g., `aws-vpc` creates `aws-vpc.tf`). |

## Steps

### Step 1: Validate argument

Confirm that `resource-file-name` was provided and is a non-empty string containing only alphanumeric characters, hyphens, and underscores.

- **On error**: stop immediately. Surface the message `"resource-file-name argument is missing or invalid"` and the step name `"Validate argument"` to the developer. Do not proceed to any subsequent step.

### Step 2: Resolve target path

Derive the target file path as `<repository-root>/<resource-file-name>.tf`.

Confirm that the repository root is the current working directory (the directory containing `main.tf`).

- **On error** (e.g., repository root cannot be determined): stop immediately. Surface the error message and the step name `"Resolve target path"` to the developer. Do not proceed.

### Step 3: Check for existing file

Check whether the target file already exists at the resolved path.

If the file already exists, stop immediately. Surface the message `"File <resource-file-name>.tf already exists at the repository root"` and the step name `"Check for existing file"` to the developer. Do not overwrite the existing file.

### Step 4: Create the scaffold file

Create the file at the resolved path with the following content:

```hcl
# ---
# <resource-file-name> resources
# ---

resource "PROVIDER_RESOURCE_TYPE" "this" {
  # TODO: replace PROVIDER_RESOURCE_TYPE with the actual Terraform resource type
  # e.g., resource "aws_vpc" "this" { ... }
}
```

Replace `<resource-file-name>` in the section header comment with the actual value supplied by the developer.

- **On error** (e.g., permission denied, disk full): stop immediately. Surface the error message and the step name `"Create the scaffold file"` to the developer. Do not proceed.

### Step 5: Confirm creation

Report success to the developer with the message:

```
Created <repository-root>/<resource-file-name>.tf with a section header and placeholder resource block.
Next step: replace PROVIDER_RESOURCE_TYPE with the actual resource type and fill in the required arguments.
```

## Stop-on-Error Behaviour

If **any** step exits with a non-zero exit code or produces an error message, the skill **immediately halts all subsequent steps** and surfaces both:

1. The **error message** returned by the failed operation.
2. The **name of the failed step** (e.g., `"Validate argument"`, `"Resolve target path"`, `"Check for existing file"`, `"Create the scaffold file"`).

No partial output is committed when a step fails.
