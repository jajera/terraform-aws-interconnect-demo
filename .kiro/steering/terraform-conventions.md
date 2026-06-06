---
inclusion: auto
---

# Terraform Coding Conventions

## Naming

- Always use snake_case for all Terraform identifiers (resources, variables, outputs, locals, data sources).
- Always suffix resource names with the environment or purpose (e.g., `vpc_production`, `subnet_private`).

## Tagging

- Always apply the following tags to every taggable resource:
  - `Project` — the name of the project
  - `Environment` — the target environment (e.g., dev, staging, production)
  - `ManagedBy = Terraform`

## Security

- Never hardcode credentials, secrets, or API keys in `.tf` files. Use variables with `sensitive = true` or external secret stores.

## Repository Structure

- Never create a `modules/` directory in this repository.
- Never create an `environments/` directory in this repository.
