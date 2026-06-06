---
name: plan-summary
description: Summarise Terraform plan output with resource counts, grouped resource addresses, and a risk assessment on destructive changes.
---

# Plan Summary Skill

## Purpose

Accept `terraform plan` output and return a concise summary containing resource counts, a grouped list of affected resource addresses, and a one-sentence risk assessment highlighting any destructive changes.

## Input

| Argument | Type | Required | Description |
|---|---|---|---|
| `plan-output` | string | yes | The full text output from a `terraform plan` execution. |

## Steps

### Step 1: Validate input

Confirm that `plan-output` was provided and is a non-empty string containing recognisable Terraform plan output (e.g., includes resource action indicators or a "No changes" message).

- **On error**: stop immediately. Surface the message `"plan-output argument is missing or does not contain valid Terraform plan output"` and the step name `"Validate input"` to the developer. Do not proceed to any subsequent step.

### Step 2: Extract resource counts

Parse the plan output to determine the number of resources in each action category:

- **Add** — resources to be created
- **Change** — resources to be updated in-place
- **Destroy** — resources to be destroyed

Present the counts in the format:

```
Resources: +<add> to add, ~<change> to change, -<destroy> to destroy.
```

- **On error** (e.g., unable to parse counts from plan output): stop immediately. Surface the error message and the step name `"Extract resource counts"` to the developer. Do not proceed.

### Step 3: Group resource addresses by action

Produce a bullet list of resource addresses grouped under their action heading:

```
### Add
- <resource_address>
- <resource_address>

### Change
- <resource_address>
- <resource_address>

### Destroy
- <resource_address>
- <resource_address>
```

Omit any group that has zero resources.

- **On error** (e.g., resource addresses cannot be extracted): stop immediately. Surface the error message and the step name `"Group resource addresses by action"` to the developer. Do not proceed.

### Step 4: Produce risk assessment

Generate a single-sentence risk assessment:

- If **no** resources are being destroyed, state: `"No destructive changes detected; this plan is low-risk."`
- If **one or more** resources are being destroyed, state: `"This plan includes <N> resource destruction(s) — review the Destroy list above before applying."`

Replace `<N>` with the actual destroy count.

- **On error**: stop immediately. Surface the error message and the step name `"Produce risk assessment"` to the developer. Do not proceed.

### Step 5: Return summary

Combine the outputs from Steps 2–4 into a single formatted response and return it to the developer.

## Stop-on-Error Behaviour

If **any** step exits with a non-zero exit code or produces an error message, the skill **immediately halts all subsequent steps** and surfaces both:

1. The **error message** returned by the failed operation.
2. The **name of the failed step** (e.g., `"Validate input"`, `"Extract resource counts"`, `"Group resource addresses by action"`, `"Produce risk assessment"`).

No partial output is returned when a step fails.
